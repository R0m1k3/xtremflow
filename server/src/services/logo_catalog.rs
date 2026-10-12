//! Logos de chaînes de repli, tirés du dépôt public `tv-logo/tv-logos`.
//!
//! POURQUOI : les URL `stream_icon` du panneau pointent chez l'hébergeur du
//! revendeur. Quand cette machine tombe — cas observé : serveur de picons en
//! maintenance, 503 sur toutes les URL —, toute la grille reste sans logo.
//! Le dépôt `tv-logos` est maintenu, nommé de façon régulière
//! (`countries/france/rmc-sport-2-fr.png`) et s'apparie au nom de chaîne.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, LazyLock, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use bytes::Bytes;
use futures::future::{BoxFuture, FutureExt, Shared};
use regex::Regex;
use reqwest::header::{ACCEPT, USER_AGENT};

use crate::util::log_redactor::redact_url;

/// GitHub refuse les requêtes sans `User-Agent`.
const USER_AGENT_VALUE: &str = "XtremFlow";

/// Plafond d'une requête (liste ou image).
const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

type SharedListing = Shared<BoxFuture<'static, Option<Arc<Listing>>>>;

/// Catalogue de logos, partagé via `Arc<LogoCatalog>`.
pub struct LogoCatalog {
    inner: Arc<Inner>,
}

struct Inner {
    client: reqwest::Client,
    api_base: String,

    /// Durée de vie d'une liste de logos par pays. L'API GitHub non
    /// authentifiée plafonne à 60 requêtes par heure : une par jour suffit.
    listing_ttl: Duration,

    /// Recul après un échec de téléchargement de liste (limite de débit,
    /// réseau), pour ne pas marteler l'API à chaque tuile affichée.
    retry_backoff: Duration,

    state: Mutex<State>,
}

#[derive(Default)]
struct State {
    listings: HashMap<&'static str, Arc<Listing>>,
    listings_in_flight: HashMap<&'static str, SharedListing>,
    listing_failed_at: HashMap<&'static str, Instant>,
    /// URL de téléchargement → octets PNG.
    bytes: HashMap<String, Bytes>,
}

struct Listing {
    /// Clé normalisée → URL de téléchargement brute.
    urls: HashMap<String, String>,
    fetched_at: Instant,
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Libère la place de la requête de liste en cours quand elle se termine,
/// même en cas de panique.
struct InFlightGuard(Arc<Inner>, &'static str);

impl Drop for InFlightGuard {
    fn drop(&mut self) {
        self.0.lock().listings_in_flight.remove(self.1);
    }
}

impl LogoCatalog {
    pub fn new(client: reqwest::Client) -> Self {
        Self::with_api_base(client, "https://api.github.com".to_string())
    }

    /// `api_base` remplace `https://api.github.com` (tests).
    pub fn with_api_base(client: reqwest::Client, api_base: String) -> Self {
        Self {
            inner: Arc::new(Inner {
                client,
                api_base: api_base.trim_end_matches('/').to_string(),
                listing_ttl: Duration::from_secs(24 * 3600),
                retry_backoff: Duration::from_secs(15 * 60),
                state: Mutex::new(State::default()),
            }),
        }
    }

    /// Octets PNG du logo correspondant à `channel_name`, ou `None`.
    pub async fn logo_for(&self, channel_name: &str) -> Option<Bytes> {
        let country = country_folder_for(channel_name);
        let listing = self.listing_for(country).await?;

        let key = match_logo_key(channel_name, listing.urls.keys())?;
        let url = listing.urls.get(&key)?.clone();
        if let Some(cached) = self.inner.lock().bytes.get(&url) {
            return Some(cached.clone());
        }

        let download = async {
            let response = self
                .inner
                .client
                .get(&url)
                .header(USER_AGENT, USER_AGENT_VALUE)
                .send()
                .await
                .ok()?;
            if response.status().as_u16() != 200 {
                return None;
            }
            response.bytes().await.ok()
        };
        let bytes = tokio::time::timeout(REQUEST_TIMEOUT, download)
            .await
            .ok()
            .flatten()?;
        self.inner.lock().bytes.insert(url, bytes.clone());
        Some(bytes)
    }

    async fn listing_for(&self, country: &'static str) -> Option<Arc<Listing>> {
        let pending = {
            let mut state = self.inner.lock();
            let cached = state.listings.get(country).cloned();
            if let Some(listing) = &cached
                && listing.fetched_at.elapsed() < self.inner.listing_ttl
            {
                return cached;
            }

            if state
                .listing_failed_at
                .get(country)
                .is_some_and(|at| at.elapsed() < self.inner.retry_backoff)
            {
                // Liste périmée plutôt que rien : les logos ne changent pas
                // d'un jour à l'autre.
                return cached;
            }

            // Les tuiles d'une grille arrivent en rafale : une seule requête
            // de liste. Elle tourne dans sa propre tâche pour aller au bout
            // même si le premier demandeur abandonne.
            match state.listings_in_flight.get(country) {
                Some(pending) => pending.clone(),
                None => {
                    let inner = Arc::clone(&self.inner);
                    let task = tokio::spawn(async move {
                        let _guard = InFlightGuard(Arc::clone(&inner), country);
                        fetch_listing(&inner, country).await
                    });
                    let pending = async move { task.await.ok().flatten() }.boxed().shared();
                    state.listings_in_flight.insert(country, pending.clone());
                    pending
                }
            }
        };
        pending.await
    }
}

async fn fetch_listing(inner: &Inner, country: &'static str) -> Option<Arc<Listing>> {
    let url = format!(
        "{}/repos/tv-logo/tv-logos/contents/countries/{country}",
        inner.api_base
    );
    match request_listing(inner, &url).await {
        Ok(urls) => {
            let count = urls.len();
            let listing = Arc::new(Listing {
                urls,
                fetched_at: Instant::now(),
            });
            {
                let mut state = inner.lock();
                state.listings.insert(country, Arc::clone(&listing));
                state.listing_failed_at.remove(country);
            }
            println!("[LogoCatalog] {country} : {count} logos");
            Some(listing)
        }
        Err(error) => {
            let stale = {
                let mut state = inner.lock();
                state.listing_failed_at.insert(country, Instant::now());
                state.listings.get(country).cloned()
            };
            println!(
                "[LogoCatalog] liste {country} indisponible : {}",
                redact_url(&error)
            );
            stale
        }
    }
}

/// Liste des PNG d'un dossier pays : clé normalisée → URL brute.
async fn request_listing(inner: &Inner, url: &str) -> Result<HashMap<String, String>, String> {
    let request = async {
        let response = inner
            .client
            .get(url)
            .header(ACCEPT, "application/vnd.github+json")
            .header(USER_AGENT, USER_AGENT_VALUE)
            .send()
            .await
            .map_err(|e| error_text(&e))?;
        let status = response.status().as_u16();
        if status != 200 {
            return Err(format!("Bad state: HTTP {status}"));
        }
        response.bytes().await.map_err(|e| error_text(&e))
    };
    let body = tokio::time::timeout(REQUEST_TIMEOUT, request)
        .await
        .map_err(|_| "TimeoutException after 0:00:20.000000: Future not completed".to_string())??;

    let decoded: serde_json::Value = serde_json::from_str(&String::from_utf8_lossy(&body))
        .map_err(|e| format!("FormatException: {e}"))?;
    let mut urls = HashMap::new();
    if let serde_json::Value::Array(entries) = decoded {
        for entry in entries {
            let serde_json::Value::Object(entry) = entry else {
                continue;
            };
            let name = entry
                .get("name")
                .and_then(dart_to_string)
                .unwrap_or_default();
            let Some(download) = entry.get("download_url").and_then(dart_to_string) else {
                continue;
            };
            if !name.ends_with(".png") {
                continue;
            }
            urls.insert(key_from_file_name(&name), download);
        }
    }
    Ok(urls)
}

/// `value?.toString()` de Dart : `None` pour `null`.
fn dart_to_string(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::Null => None,
        serde_json::Value::String(s) => Some(s.clone()),
        other => Some(other.to_string()),
    }
}

/// Texte d'une erreur avec ses causes.
fn error_text(error: &dyn std::error::Error) -> String {
    let mut text = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        text.push_str(": ");
        text.push_str(&cause.to_string());
        source = cause.source();
    }
    text
}

/// `rmc-sport-2-fr.png` → `rmc-sport-2`.
fn key_from_file_name(name: &str) -> String {
    let base = &name[..name.len() - ".png".len()];
    let bytes = base.as_bytes();
    let n = bytes.len();
    if n >= 3
        && bytes[n - 3] == b'-'
        && bytes[n - 2].is_ascii_lowercase()
        && bytes[n - 1].is_ascii_lowercase()
    {
        base[..n - 3].to_string()
    } else {
        base.to_string()
    }
}

/// Code pays du préfixe panneau → dossier du dépôt `tv-logos`.
fn country_folder(code: &str) -> Option<&'static str> {
    Some(match code {
        "fr" => "france",
        "be" => "belgium",
        "ch" => "switzerland",
        "uk" | "gb" => "united-kingdom",
        "us" => "united-states",
        "ca" => "canada",
        "de" => "germany",
        "es" => "spain",
        "it" => "italy",
        "pt" => "portugal",
        "nl" => "netherlands",
        _ => return None,
    })
}

/// Préfixe pays des noms panneau : `FR - `, `FR: `, `|FR| `.
///
/// `\W` et `\s` reproduits avec leur sens Dart (ASCII pour `\W`, espaces
/// JavaScript pour `\s`), les classes de `regex` étant Unicode.
static COUNTRY_PREFIX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^[^A-Za-z0-9_]*([A-Za-z]{2})[\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}\-:|]+",
    )
    .unwrap()
});

/// Dossier `tv-logos` à consulter pour `channel_name`. France par défaut :
/// c'est l'audience de l'application.
pub fn country_folder_for(channel_name: &str) -> &'static str {
    COUNTRY_PREFIX
        .captures(channel_name)
        .and_then(|caps| country_folder(&caps[1].to_lowercase()))
        .unwrap_or("france")
}

/// Mots sans rapport avec l'identité de la chaîne : qualité, codec, variante
/// de flux. Ils sont propres au panneau et absents des noms de logos.
const NOISE: &[&str] = &[
    "fhd", "uhd", "hd", "sd", "4k", "8k", "hdr", "hevc", "h264", "h265", "1080p", "720p", "50fps",
    "fps", "raw", "backup", "vip", "multi", "vf", "vo", "vostfr",
];

fn fold_accent(c: char) -> char {
    match c {
        'à' | 'á' | 'â' | 'ä' => 'a',
        'è' | 'é' | 'ê' | 'ë' => 'e',
        'ì' | 'í' | 'î' | 'ï' => 'i',
        'ò' | 'ó' | 'ô' | 'ö' => 'o',
        'ù' | 'ú' | 'û' | 'ü' => 'u',
        'ç' => 'c',
        other => other,
    }
}

fn tokens(channel_name: &str) -> Vec<String> {
    let mut name = channel_name;
    if let Some(caps) = COUNTRY_PREFIX.captures(name)
        && country_folder(&caps[1].to_lowercase()).is_some()
    {
        name = &name[caps.get(0).map_or(0, |m| m.end())..];
    }

    let folded: String = name.to_lowercase().chars().map(fold_accent).collect();
    folded
        .replace('+', " plus ")
        .replace('&', " and ")
        .split(|c: char| !matches!(c, 'a'..='z' | '0'..='9'))
        .filter(|t| !t.is_empty() && !NOISE.contains(t))
        .map(str::to_string)
        .collect()
}

/// Clé de logo la plus proche de `channel_name` parmi `available`, ou `None`.
///
/// Par ordre de confiance : nom exact, nom sans « live », variante plus
/// longue du même identifiant (`bein-sports-1` → `bein-sports-1-french`),
/// puis la marque sans numéro de canal (`rmc-sport-live-5` → `rmc-sport-1`).
/// Aucune approximation sur un mot seul : « France » ne doit pas devenir
/// France 24.
pub fn match_logo_key<'a>(
    channel_name: &str,
    available: impl IntoIterator<Item = &'a String>,
) -> Option<String> {
    let keys: HashSet<&str> = available.into_iter().map(String::as_str).collect();
    let tokens = tokens(channel_name);
    if tokens.is_empty() {
        return None;
    }

    let without_live = |parts: &[String]| -> Vec<String> {
        parts.iter().filter(|t| *t != "live").cloned().collect()
    };

    let exact = |parts: &[String]| -> Option<String> {
        let slug = parts.join("-");
        (!parts.is_empty() && keys.contains(slug.as_str())).then_some(slug)
    };

    let longer_variant = |parts: &[String]| -> Option<String> {
        if parts.len() < 2 {
            return None;
        }
        let prefix = format!("{}-", parts.join("-"));
        // Plus courte d'abord (longueur en unités UTF-16 comme en Dart), puis
        // ordre alphabétique.
        keys.iter()
            .filter(|k| k.starts_with(&prefix))
            .min_by(|a, b| {
                a.encode_utf16()
                    .count()
                    .cmp(&b.encode_utf16().count())
                    .then_with(|| a.cmp(b))
            })
            .map(|k| k.to_string())
    };

    let no_live = without_live(&tokens);
    let direct = exact(&tokens)
        .or_else(|| exact(&no_live))
        .or_else(|| longer_variant(&tokens))
        .or_else(|| longer_variant(&no_live));
    if direct.is_some() {
        return direct;
    }

    // Marque sans numéro de canal, seulement s'il reste au moins deux mots.
    let last = tokens.last()?;
    if !last.is_empty() && last.bytes().all(|b| b.is_ascii_digit()) {
        let brand = without_live(&tokens[..tokens.len() - 1]);
        if brand.len() >= 2 {
            return exact(&brand).or_else(|| longer_variant(&brand));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::Router;
    use axum::http::{StatusCode, Uri};
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Extrait réel de `tv-logo/tv-logos/countries/france` (noms sans
    /// `-fr.png`).
    const FRANCE: &[&str] = &[
        "bein-sports-1-french",
        "bein-sports-2-french",
        "bein-sports",
        "canal-plus",
        "canal-plus-sport",
        "canal-plus-sport-360",
        "eurosport-1",
        "france-2",
        "france-24",
        "lequipe",
        "rmc-sport-1",
        "rmc-sport-2",
        "rmc-sport-access-1",
    ];

    fn matched(name: &str) -> Option<String> {
        let keys: Vec<String> = FRANCE.iter().map(|s| s.to_string()).collect();
        match_logo_key(name, &keys)
    }

    #[test]
    fn correspondance_exacte_apres_nettoyage_du_nom_panneau() {
        // Préfixe pays et suffixe de qualité sont du bruit propre au panneau.
        assert_eq!(
            matched("FR - RMC SPORT 2 FHD").as_deref(),
            Some("rmc-sport-2")
        );
        assert_eq!(matched("FR: France 2 HD").as_deref(), Some("france-2"));
        assert_eq!(
            matched("|FR| EUROSPORT 1 UHD").as_deref(),
            Some("eurosport-1")
        );
    }

    #[test]
    fn traduit_le_plus_de_canal_plus() {
        assert_eq!(
            matched("FR - CANAL+ SPORT FHD").as_deref(),
            Some("canal-plus-sport")
        );
        assert_eq!(matched("FR - CANAL+").as_deref(), Some("canal-plus"));
    }

    #[test]
    fn accepte_une_variante_plus_longue_du_meme_identifiant() {
        // Le dépôt nomme `bein-sports-1-french`, le panneau `BEIN SPORTS 1`.
        assert_eq!(
            matched("FR - BEIN SPORTS 1 FHD").as_deref(),
            Some("bein-sports-1-french")
        );
    }

    #[test]
    fn retombe_sur_la_marque_quand_le_numero_de_canal_est_inconnu() {
        // Les canaux événementiels (« Live 5 ») n'ont pas de logo propre :
        // celui de la marque vaut mieux qu'une tuile vide.
        assert_eq!(
            matched("FR - RMC SPORT LIVE 5 FHD").as_deref(),
            Some("rmc-sport-1")
        );
        assert_eq!(
            matched("FR - CANAL+ SPORT 2").as_deref(),
            Some("canal-plus-sport")
        );
    }

    #[test]
    fn ne_devine_pas_sur_un_seul_mot() {
        // « France » seul ne doit pas donner le logo de France 24.
        assert_eq!(matched("FR - FRANCE"), None);
    }

    #[test]
    fn rend_none_quand_rien_ne_correspond() {
        assert_eq!(matched("FR - DAZN FHD"), None);
        assert_eq!(matched(""), None);
    }

    #[test]
    fn country_folder_lit_le_prefixe_pays_du_nom() {
        assert_eq!(country_folder_for("FR - TF1"), "france");
        assert_eq!(country_folder_for("BE: RTL TVI"), "belgium");
        assert_eq!(country_folder_for("|UK| BBC ONE"), "united-kingdom");
    }

    #[test]
    fn country_folder_france_par_defaut_sans_prefixe_reconnu() {
        assert_eq!(country_folder_for("TF1 HD"), "france");
    }

    #[test]
    fn cle_depuis_le_nom_de_fichier() {
        assert_eq!(key_from_file_name("rmc-sport-2-fr.png"), "rmc-sport-2");
        assert_eq!(key_from_file_name("lequipe.png"), "lequipe");
        assert_eq!(key_from_file_name("bbc-one-uk.png"), "bbc-one");
    }

    /// Mini serveur HTTP local (remplace le `MockClient` Dart) : compte les
    /// requêtes et répond selon le chemin. `{base}` dans le corps est
    /// remplacé par l'adresse du serveur.
    async fn serve(
        respond: impl Fn(&Uri) -> (StatusCode, String) + Send + Sync + 'static,
    ) -> (String, Arc<Mutex<Vec<String>>>) {
        let requested = Arc::new(Mutex::new(Vec::new()));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let respond = Arc::new(respond);
        let log = Arc::clone(&requested);
        let base_for_body = base.clone();
        let app = Router::new().fallback(move |uri: Uri| {
            let respond = Arc::clone(&respond);
            let log = Arc::clone(&log);
            let base = base_for_body.clone();
            async move {
                log.lock().unwrap().push(uri.to_string());
                let (status, body) = respond(&uri);
                (status, body.replace("{base}", &base))
            }
        });
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        (base, requested)
    }

    #[tokio::test]
    async fn telecharge_le_logo_apparie_et_le_garde_en_cache() {
        let (base, requested) = serve(|uri| {
            if uri.path().starts_with("/repos/") {
                (
                    StatusCode::OK,
                    serde_json::json!([
                        {"name": "rmc-sport-2-fr.png", "download_url": "{base}/raw/rmc-sport-2-fr.png"},
                        {"name": "README.md", "download_url": "{base}/r"},
                    ])
                    .to_string(),
                )
            } else {
                (StatusCode::OK, "\u{1}\u{2}\u{3}".to_string())
            }
        })
        .await;

        let catalog = LogoCatalog::with_api_base(reqwest::Client::new(), base);
        let first = catalog.logo_for("FR - RMC SPORT 2 FHD").await;
        let second = catalog.logo_for("FR - RMC SPORT 2 FHD").await;

        assert_eq!(first.as_deref(), Some(&[1u8, 2, 3][..]));
        assert_eq!(second.as_deref(), Some(&[1u8, 2, 3][..]));
        // Une liste et un logo, pas un aller-retour par affichage.
        let requested = requested.lock().unwrap().clone();
        assert_eq!(requested.len(), 2, "{requested:?}");
        assert_eq!(
            requested[0],
            "/repos/tv-logo/tv-logos/contents/countries/france"
        );
    }

    #[tokio::test]
    async fn rend_none_sans_correspondance_sans_telecharger_d_image() {
        let downloads = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&downloads);
        let (base, _) = serve(move |uri| {
            if uri.path().starts_with("/repos/") {
                (StatusCode::OK, "[]".to_string())
            } else {
                counter.fetch_add(1, Ordering::SeqCst);
                (StatusCode::OK, "\u{1}".to_string())
            }
        })
        .await;

        let catalog = LogoCatalog::with_api_base(reqwest::Client::new(), base);
        assert_eq!(catalog.logo_for("FR - CHAINE INCONNUE").await, None);
        assert_eq!(downloads.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn espace_les_tentatives_quand_la_liste_est_injoignable() {
        let (base, requested) =
            serve(|_| (StatusCode::FORBIDDEN, "rate limited".to_string())).await;

        let catalog = LogoCatalog::with_api_base(reqwest::Client::new(), base);
        catalog.logo_for("FR - RMC SPORT 2").await;
        catalog.logo_for("FR - RMC SPORT 1").await;

        assert_eq!(requested.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn une_seule_requete_de_liste_pour_une_rafale_de_tuiles() {
        let (base, requested) = serve(|uri| {
            if uri.path().starts_with("/repos/") {
                (StatusCode::OK, "[]".to_string())
            } else {
                (StatusCode::OK, String::new())
            }
        })
        .await;

        let catalog = LogoCatalog::with_api_base(reqwest::Client::new(), base);
        futures::future::join_all((0..8).map(|i| {
            let name = format!("FR - CHAINE {i}");
            let catalog = &catalog;
            async move { catalog.logo_for(&name).await }
        }))
        .await;

        assert_eq!(requested.lock().unwrap().len(), 1);
    }
}
