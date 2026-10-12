//! Connexions ouvertes vers le fournisseur Xtream, par compte.
//!
//! POURQUOI : la plupart des abonnements n'autorisent qu'UNE connexion
//! simultanée (`max_connections: "1"`, vérifié en prod). Or un FFmpeg de
//! lecture survit au spectateur : 4 min pour un direct HLS, jusqu'à 15 min
//! ou la fin du téléchargement pour un film, le temps de détecter la
//! déconnexion pour `turbo.ts`. Le flux suivant tombait sur un slot occupé :
//! le panneau répondait `HTTP 551` ou ne répondait pas (timeout), d'où les
//! films « indisponibles » et les zaps qui échouent.
//!
//! Règle : avant d'ouvrir une nouvelle connexion amont, on coupe les
//! connexions ORPHELINES du même compte (plus personne ne les consomme),
//! les plus anciennes d'abord, jusqu'à lui faire de la place.
//!
//! Un flux encore regardé n'est jamais coupé : deux lecteurs ouverts sur un
//! compte à une connexion se coupaient sinon en boucle (constaté en prod).
//! Le second lecteur est refusé par le panneau et le premier continue.
//!
//! Les enregistrements n'y sont pas inscrits : ils ne sont jamais coupés.

use crate::models::PlaylistConfig;
use futures::future::BoxFuture;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

type Release = Box<dyn Fn() + Send + Sync>;
type IsActive = Box<dyn Fn() -> bool + Send + Sync>;

struct Slot {
    token: u64,
    account: String,
    /// Ordre d'inscription : les plus anciennes connexions partent d'abord.
    since: u64,
    release: Release,
    is_active: Option<IsActive>,
}

impl Slot {
    fn active(&self) -> bool {
        self.is_active.as_ref().is_some_and(|f| f())
    }
}

#[derive(Default)]
struct Inner {
    slots: HashMap<String, Slot>,
    next: u64,
}

#[derive(Default)]
pub struct UpstreamSlots {
    inner: Mutex<Inner>,
}

impl UpstreamSlots {
    pub fn new() -> Self {
        Self::default()
    }

    /// Inscrit la connexion [id] du compte [account]. [release] la coupe.
    ///
    /// Renvoie un jeton à repasser à [unregister] : une session relancée sous
    /// le même identifiant ne doit pas être désinscrite par la fin de
    /// l'ancien processus. [is_active] : vrai tant qu'un spectateur consomme
    /// le flux ; une connexion active n'est jamais coupée.
    pub fn register(
        &self,
        id: &str,
        account: &str,
        release: Release,
        is_active: Option<IsActive>,
    ) -> u64 {
        let mut inner = self.inner.lock().unwrap();
        inner.next += 1;
        let token = inner.next;
        inner.slots.insert(
            id.to_string(),
            Slot {
                token,
                account: account.to_string(),
                since: token,
                release,
                is_active,
            },
        );
        token
    }

    pub fn unregister(&self, id: &str, token: Option<u64>) {
        let mut inner = self.inner.lock().unwrap();
        let Some(slot) = inner.slots.get(id) else {
            return;
        };
        if token.is_some_and(|t| t != slot.token) {
            return;
        }
        inner.slots.remove(id);
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn count_for(&self, account: &str) -> usize {
        self.inner
            .lock()
            .unwrap()
            .slots
            .values()
            .filter(|s| s.account == account)
            .count()
    }

    /// Libère assez de connexions de [account] pour qu'une nouvelle tienne
    /// sous [max]. [keep] (la session demandée) n'est jamais coupée.
    ///
    /// [max] <= 0 = quota inconnu : on ne coupe rien plutôt que de risquer
    /// d'interrompre un autre spectateur.
    pub fn make_room(&self, account: &str, max: i64, keep: &str) -> Vec<String> {
        if max <= 0 {
            return Vec::new();
        }
        let released: Vec<(String, Release)> = {
            let mut inner = self.inner.lock().unwrap();
            let others: Vec<&String> = inner
                .slots
                .iter()
                .filter(|(id, s)| s.account == account && id.as_str() != keep)
                .map(|(id, _)| id)
                .collect();
            let excess = others.len() as i64 - (max - 1);
            if excess <= 0 {
                return Vec::new();
            }
            let mut orphans: Vec<(String, u64)> = others
                .into_iter()
                .filter(|id| !inner.slots[*id].active())
                .map(|id| (id.clone(), inner.slots[id].since))
                .collect();
            orphans.sort_by_key(|(_, since)| *since);
            orphans
                .into_iter()
                .take(excess as usize)
                .filter_map(|(id, _)| inner.slots.remove(&id).map(|s| (id, s.release)))
                .collect()
        };
        // Coupures hors du verrou : un `release` peut toucher d'autres registres.
        released
            .into_iter()
            .map(|(id, release)| {
                let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(&release));
                id
            })
            .collect()
    }
}

/// Clé de compte : deux playlists sur les mêmes identifiants partagent le
/// même quota chez le fournisseur.
pub fn account_key_of(p: &PlaylistConfig) -> String {
    format!("{}|{}", p.dns, p.username)
}

/// `user_info.max_connections` d'une réponse `player_api.php`, ou `None`.
pub fn parse_max_connections(json: &serde_json::Value) -> Option<i64> {
    let raw = json.get("user_info")?.as_object()?.get("max_connections")?;
    let value = match raw {
        serde_json::Value::Number(n) => n.as_i64(),
        serde_json::Value::String(s) => s.parse().ok(),
        _ => None,
    }?;
    (value > 0).then_some(value)
}

pub type FetchLimit = Arc<dyn Fn(PlaylistConfig) -> BoxFuture<'static, Option<i64>> + Send + Sync>;

/// Quota de connexions par compte, lu chez le fournisseur et mis en cache.
///
/// Ne fait JAMAIS attendre un flux : `player_api.php` met jusqu'à 4 s à
/// répondre (mesuré en prod). La valeur connue (même périmée), sinon
/// [FALLBACK], est rendue immédiatement ; la lecture chez le panneau se fait
/// en arrière-plan. Sans risque : le quota ne sert qu'à décider quels flux
/// ORPHELINS couper.
pub struct AccountLimits {
    ttl: Duration,
    fetch: FetchLimit,
    cache: Arc<Mutex<HashMap<String, (i64, Instant)>>>,
    refreshing: Arc<Mutex<HashSet<String>>>,
}

impl AccountLimits {
    /// Valeur retenue tant que le panneau n'a pas répondu : un seul flux, le
    /// cas de loin le plus courant chez les fournisseurs Xtream.
    pub const FALLBACK: i64 = 1;

    pub fn new(ttl: Duration, fetch: FetchLimit) -> Self {
        Self {
            ttl,
            fetch,
            cache: Arc::default(),
            refreshing: Arc::default(),
        }
    }

    /// Lecture réelle chez le panneau.
    pub fn from_panel(client: reqwest::Client) -> Self {
        let fetch: FetchLimit = Arc::new(move |p: PlaylistConfig| {
            let client = client.clone();
            Box::pin(async move {
                let mut url = reqwest::Url::parse(&format!("{}/player_api.php", p.dns)).ok()?;
                url.query_pairs_mut()
                    .append_pair("username", &p.username)
                    .append_pair("password", &p.password);
                let send = client
                    .get(url)
                    .header("User-Agent", "VLC/3.0.18 LibVLC/3.0.18")
                    .send();
                let response = tokio::time::timeout(Duration::from_secs(5), send)
                    .await
                    .ok()?
                    .ok()?;
                if response.status().as_u16() != 200 {
                    return None;
                }
                let body = tokio::time::timeout(Duration::from_secs(5), response.bytes())
                    .await
                    .ok()?
                    .ok()?;
                let json: serde_json::Value = serde_json::from_slice(&body).ok()?;
                parse_max_connections(&json)
            })
        });
        Self::new(Duration::from_secs(600), fetch)
    }

    pub fn max_for(&self, p: &PlaylistConfig) -> i64 {
        let key = account_key_of(p);
        let cached = self.cache.lock().unwrap().get(&key).copied();
        if cached.is_none_or(|(_, at)| at.elapsed() >= self.ttl) {
            self.refresh(key, p.clone());
        }
        cached.map(|(max, _)| max).unwrap_or(Self::FALLBACK)
    }

    fn refresh(&self, key: String, p: PlaylistConfig) {
        if !self.refreshing.lock().unwrap().insert(key.clone()) {
            return; // une seule lecture à la fois
        }
        let fetch = self.fetch.clone();
        let cache = self.cache.clone();
        let refreshing = self.refreshing.clone();
        tokio::spawn(async move {
            // Un échec n'est pas mis en cache : on réessaiera au prochain flux.
            if let Some(value) = fetch(p).await {
                cache
                    .lock()
                    .unwrap()
                    .insert(key.clone(), (value, Instant::now()));
            }
            refreshing.lock().unwrap().remove(&key);
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn collector() -> (Arc<Mutex<Vec<String>>>, impl Fn(&str) -> Release) {
        let released = Arc::new(Mutex::new(Vec::new()));
        let r = released.clone();
        let make = move |id: &str| -> Release {
            let r = r.clone();
            let id = id.to_string();
            Box::new(move || r.lock().unwrap().push(id.clone()))
        };
        (released, make)
    }

    #[test]
    fn compte_a_une_connexion_le_flux_precedent_est_coupe() {
        let slots = UpstreamSlots::new();
        let (released, make) = collector();
        slots.register("live_1_source", "acc", make("live_1_source"), None);
        assert_eq!(
            slots.make_room("acc", 1, "live_2_source"),
            vec!["live_1_source"]
        );
        assert_eq!(*released.lock().unwrap(), vec!["live_1_source"]);
        assert_eq!(slots.count_for("acc"), 0);
    }

    #[test]
    fn la_session_demandee_n_est_jamais_coupee() {
        let slots = UpstreamSlots::new();
        let (released, make) = collector();
        slots.register("live_1_source", "acc", make("live_1_source"), None);
        assert!(slots.make_room("acc", 1, "live_1_source").is_empty());
        assert!(released.lock().unwrap().is_empty());
    }

    #[test]
    fn les_plus_anciennes_partent_d_abord() {
        let slots = UpstreamSlots::new();
        let (_released, make) = collector();
        for id in ["a", "b", "c"] {
            slots.register(id, "acc", make(id), None);
        }
        assert_eq!(slots.make_room("acc", 3, "new"), vec!["a"]);
        assert_eq!(slots.count_for("acc"), 2);
    }

    #[test]
    fn un_autre_compte_n_est_jamais_touche() {
        let slots = UpstreamSlots::new();
        let (_released, make) = collector();
        slots.register("x", "other", make("x"), None);
        assert!(slots.make_room("acc", 1, "new").is_empty());
        assert_eq!(slots.count_for("other"), 1);
    }

    #[test]
    fn jeton_perime_ne_libere_pas_la_session_relancee() {
        let slots = UpstreamSlots::new();
        let old = slots.register("s", "acc", Box::new(|| {}), None);
        slots.register("s", "acc", Box::new(|| {}), None);
        slots.unregister("s", Some(old));
        assert_eq!(slots.count_for("acc"), 1);
    }

    #[test]
    fn un_flux_regarde_n_est_jamais_coupe() {
        let slots = UpstreamSlots::new();
        let (released, make) = collector();
        slots.register("watched", "acc", make("watched"), Some(Box::new(|| true)));
        assert!(slots.make_room("acc", 1, "new").is_empty());
        assert!(released.lock().unwrap().is_empty());
        assert_eq!(slots.count_for("acc"), 1);
    }

    #[test]
    fn seuls_les_orphelins_partent() {
        let slots = UpstreamSlots::new();
        let (released, make) = collector();
        slots.register("watched", "acc", make("watched"), Some(Box::new(|| true)));
        slots.register("orphan", "acc", make("orphan"), None);
        assert_eq!(slots.make_room("acc", 1, "new"), vec!["orphan"]);
        assert_eq!(*released.lock().unwrap(), vec!["orphan"]);
    }

    #[test]
    fn quota_inconnu_rien_n_est_coupe() {
        let slots = UpstreamSlots::new();
        let (_released, make) = collector();
        slots.register("a", "acc", make("a"), None);
        assert!(slots.make_room("acc", 0, "new").is_empty());
    }

    fn playlist() -> PlaylistConfig {
        PlaylistConfig {
            dns: "http://panel.test".into(),
            username: "u".into(),
            password: "x".into(),
        }
    }

    #[tokio::test]
    async fn ne_fait_jamais_attendre_un_flux() {
        let (tx, rx) = tokio::sync::oneshot::channel::<Option<i64>>();
        let rx = Arc::new(Mutex::new(Some(rx)));
        let fetch: FetchLimit = Arc::new(move |_| {
            let rx = rx.lock().unwrap().take();
            Box::pin(async move {
                match rx {
                    Some(rx) => rx.await.ok().flatten(),
                    None => None,
                }
            })
        });
        let limits = AccountLimits::new(Duration::from_secs(600), fetch);
        assert_eq!(limits.max_for(&playlist()), AccountLimits::FALLBACK);
        tx.send(Some(3)).unwrap();
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(limits.max_for(&playlist()), 3);
    }

    #[tokio::test]
    async fn valeur_perimee_servie_pendant_le_rafraichissement() {
        let calls = Arc::new(AtomicUsize::new(0));
        let c = calls.clone();
        let fetch: FetchLimit = Arc::new(move |_| {
            let n = c.fetch_add(1, Ordering::SeqCst) + 1;
            Box::pin(async move { Some(if n == 1 { 2 } else { 5 }) })
        });
        let limits = AccountLimits::new(Duration::ZERO, fetch);
        limits.max_for(&playlist());
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(limits.max_for(&playlist()), 2);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(limits.max_for(&playlist()), 5);
    }

    #[tokio::test]
    async fn panneau_en_echec_repli_sans_exception() {
        let fetch: FetchLimit = Arc::new(|_| Box::pin(async { None }));
        let limits = AccountLimits::new(Duration::from_secs(600), fetch);
        assert_eq!(limits.max_for(&playlist()), AccountLimits::FALLBACK);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(limits.max_for(&playlist()), AccountLimits::FALLBACK);
    }

    #[test]
    fn lit_max_connections() {
        use serde_json::json;
        assert_eq!(
            parse_max_connections(&json!({"user_info": {"max_connections": "1"}})),
            Some(1)
        );
        assert_eq!(
            parse_max_connections(&json!({"user_info": {"max_connections": 3}})),
            Some(3)
        );
        assert_eq!(parse_max_connections(&json!({"user_info": {}})), None);
        assert_eq!(parse_max_connections(&json!("oops")), None);
        assert_eq!(
            parse_max_connections(&json!({"user_info": {"max_connections": "0"}})),
            None
        );
    }
}
