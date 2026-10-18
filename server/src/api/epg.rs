//! API EPG — `GET /api/epg/<channel_id>`, cache 30 minutes.
//!
//! Le panneau de l'abonné reste la source de référence, mais par son dump
//! `xmltv.php` d'abord : une requête couvre toutes les chaînes, là où
//! `player_api` en réclame une par chaîne à plusieurs secondes pièce. Vient
//! ensuite la source XMLTV externe (déjà indexée en mémoire), puis
//! l'interrogation chaîne par chaîne — cas des revendeurs dont le guide est
//! figé depuis plusieurs jours.

use crate::dart_time::{DartDateTime, utc_iso};
use crate::http::{self, Resp};
use crate::models::PlaylistConfig;
use crate::services::xmltv::{XmltvConfig, XmltvEpgService};
use crate::util::b64;
use crate::util::log_redactor::redact_url;
use chrono::{TimeZone, Utc};
use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use serde_json::{Map, Value, json};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub type PanelXmltvBuilder = Arc<dyn Fn(&PlaylistConfig) -> XmltvEpgService + Send + Sync>;

/// Correspondance `stream_id` → identifiant EPG et nom, par compte. Le dump
/// XMLTV indexe par identifiant de chaîne, pas par `stream_id` du panneau.
#[derive(Default)]
struct ChannelMap {
    epg_ids: HashMap<String, String>,
    names: HashMap<String, String>,
    expires_at: Option<Instant>,
}

struct Inner {
    xmltv: Option<Arc<XmltvEpgService>>,
    http: reqwest::Client,
    panel_builder: PanelXmltvBuilder,
    /// « dns|username|channelId » → réponse JSON. La clé inclut le compte :
    /// deux panneaux peuvent partager un même `stream_id`.
    cache: Mutex<HashMap<String, (String, Instant)>>,
    channel_maps: Mutex<HashMap<String, Arc<ChannelMap>>>,
    channel_maps_in_flight: Mutex<HashMap<String, Shared<BoxFuture<'static, Arc<ChannelMap>>>>>,
    panel_xmltv: Mutex<HashMap<String, Arc<XmltvEpgService>>>,
}

#[derive(Clone)]
pub struct EpgApi {
    inner: Arc<Inner>,
}

/// Dump XMLTV servi par le panneau lui-même.
///
/// POURQUOI : `get_simple_data_table` répond en plusieurs secondes chez
/// beaucoup de revendeurs, et il faut un appel par chaîne — une grille de
/// trente chaînes demandait plus d'une minute. `xmltv.php` renvoie le guide
/// de toutes les chaînes en une requête, réutilisée pendant des heures.
pub fn default_panel_xmltv(client: reqwest::Client) -> PanelXmltvBuilder {
    Arc::new(move |playlist: &PlaylistConfig| {
        let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>();
        let mut config = XmltvConfig::new(vec![format!(
            "{}/xmltv.php?username={}&password={}",
            playlist.dns,
            enc(&playlist.username),
            enc(&playlist.password)
        )]);
        config.refresh_interval = Duration::from_secs(3 * 3600);
        // Guide facultatif : pas plusieurs minutes d'attente sur un panneau lent.
        config.download_timeout = Duration::from_secs(90);
        XmltvEpgService::new(config, client.clone())
    })
}

fn value_to_string(v: &Value) -> Option<String> {
    match v {
        Value::Null => None,
        Value::String(s) => Some(s.clone()),
        other => Some(other.to_string()),
    }
}

/// `stream_id` → (`epg_channel_id`, nom) depuis `get_live_streams`.
fn parse_channel_table(body: &[u8]) -> (HashMap<String, String>, HashMap<String, String>) {
    let mut epg_ids = HashMap::new();
    let mut names = HashMap::new();
    // UTF-8 explicite : sans charset annoncé, un décodage latin-1 abîmait
    // les noms (« Chérie », « ◉ ») et donc leur correspondance au guide.
    let text = String::from_utf8_lossy(body);
    if let Ok(Value::Array(items)) = serde_json::from_str::<Value>(&text) {
        for item in items {
            let Value::Object(item) = item else { continue };
            let Some(stream_id) = item.get("stream_id").and_then(value_to_string) else {
                continue;
            };
            if stream_id.is_empty() {
                continue;
            }
            if let Some(epg_id) = item.get("epg_channel_id").and_then(value_to_string)
                && !epg_id.is_empty()
            {
                epg_ids.insert(stream_id.clone(), epg_id);
            }
            if let Some(name) = item.get("name").and_then(value_to_string)
                && !name.is_empty()
            {
                names.insert(stream_id, name);
            }
        }
    }
    (epg_ids, names)
}

/// Epoch (secondes, texte ou entier) → ISO-8601 UTC.
fn iso_utc(timestamp: Option<&Value>) -> Option<String> {
    let seconds: i64 = match timestamp? {
        Value::Number(n) => n.as_i64()?,
        Value::String(s) => s.parse().ok()?,
        _ => return None,
    };
    if seconds <= 0 {
        return None;
    }
    Utc.timestamp_opt(seconds, 0).single().map(utc_iso)
}

/// Repli : « YYYY-MM-DD HH:MM:SS » → « YYYY-MM-DDTHH:MM:SS ».
fn normalize_date(raw: &str) -> String {
    if raw.contains(' ') && !raw.contains('T') {
        raw.replacen(' ', "T", 1)
    } else {
        raw.to_string()
    }
}

/// Normalise une réponse Xtream (`epg_listings`) vers le format servi.
pub fn transform_epg_data(raw: &Value, channel_id: &str) -> Value {
    let listings: Vec<Value> = match raw {
        Value::Object(map) if map.contains_key("epg_listings") => map
            .get("epg_listings")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        Value::Array(list) => list.clone(),
        _ => Vec::new(),
    };
    let str_of = |item: &Map<String, Value>, key: &str| -> String {
        item.get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    };
    let mut programmes = Vec::new();
    for item in listings {
        let Value::Object(item) = item else {
            return json!({"channel_id": channel_id, "programmes": [], "error": "EPG indisponible"});
        };
        // Les champs texte `start`/`end` sont dans le fuseau du panneau, sans
        // indicateur de zone : le client les relisait en heure locale et
        // décalait tout le guide. Les `*_timestamp` sont de l'epoch UTC.
        let start = iso_utc(item.get("start_timestamp"))
            .unwrap_or_else(|| normalize_date(&str_of(&item, "start")));
        let end = iso_utc(item.get("stop_timestamp"))
            .or_else(|| iso_utc(item.get("end_timestamp")))
            .unwrap_or_else(|| {
                let raw = item
                    .get("stop")
                    .and_then(Value::as_str)
                    .or_else(|| item.get("end").and_then(Value::as_str))
                    .unwrap_or("");
                normalize_date(raw)
            });
        let decode = |raw: String| -> String {
            if raw.is_empty() {
                return raw;
            }
            match b64::decode_text(&raw) {
                Some(decoded) if !decoded.is_empty() => decoded,
                _ => raw,
            }
        };
        programmes.push(json!({
            "title": decode(str_of(&item, "title")),
            "description": decode(str_of(&item, "description")),
            "start": start,
            "end": end,
            "channel_id": channel_id,
        }));
    }
    json!({"channel_id": channel_id, "programmes": programmes})
}

/// Le guide contient-il un programme en cours ou à venir ? Un panneau au
/// guide figé répond avec des centaines de programmes tous terminés :
/// compter les entrées ne suffit pas.
fn has_current_programme(programmes: &[Value]) -> bool {
    let now = Utc::now();
    programmes.iter().any(|p| {
        p.get("end")
            .and_then(Value::as_str)
            .and_then(DartDateTime::parse)
            .is_some_and(|end| end.to_utc() > now)
    })
}

impl EpgApi {
    pub fn new(
        xmltv: Option<Arc<XmltvEpgService>>,
        http: reqwest::Client,
        panel_builder: PanelXmltvBuilder,
    ) -> Self {
        Self {
            inner: Arc::new(Inner {
                xmltv,
                http,
                panel_builder,
                cache: Mutex::default(),
                channel_maps: Mutex::default(),
                channel_maps_in_flight: Mutex::default(),
                panel_xmltv: Mutex::default(),
            }),
        }
    }

    pub async fn handle(&self, playlist: Option<PlaylistConfig>, channel_id: &str) -> Resp {
        let Some(playlist) = playlist else {
            return http::json(403, &json!({"error": "Playlist non trouvée"}));
        };

        let cache_key = format!("{}|{}|{channel_id}", playlist.dns, playlist.username);
        if let Some((data, expires)) = self.inner.cache.lock().unwrap().get(&cache_key)
            && Instant::now() < *expires
        {
            return http::with_headers(
                http::response(200, data.clone()),
                &[("content-type", "application/json"), ("x-cache", "HIT")],
            );
        }

        let (programmes, source, found) = self.programmes_with_source(&playlist, channel_id).await;

        let body = json!({"channel_id": channel_id, "programmes": programmes}).to_string();
        // 30 min pour un guide trouvé ; 5 min pour un guide vide, qui vient
        // souvent d'une source momentanément indisponible.
        let ttl = Duration::from_secs(if found { 30 * 60 } else { 5 * 60 });
        self.inner
            .cache
            .lock()
            .unwrap()
            .insert(cache_key, (body.clone(), Instant::now() + ttl));

        http::with_headers(
            http::response(200, body),
            &[
                ("content-type", "application/json"),
                ("x-cache", "MISS"),
                ("x-epg-source", source),
            ],
        )
    }

    /// Programmes en cours et à venir d'une chaîne, toutes sources
    /// confondues (même cascade que `GET /api/epg`, sans le cache HTTP).
    pub async fn programmes(&self, playlist: &PlaylistConfig, channel_id: &str) -> Vec<Value> {
        self.programmes_with_source(playlist, channel_id).await.0
    }

    /// Nom de la chaîne dans la table du panneau (cache 6 h).
    pub async fn channel_name(
        &self,
        playlist: &PlaylistConfig,
        channel_id: &str,
    ) -> Option<String> {
        self.channel_map_for(playlist)
            .await
            .names
            .get(channel_id)
            .cloned()
    }

    async fn programmes_with_source(
        &self,
        playlist: &PlaylistConfig,
        channel_id: &str,
    ) -> (Vec<Value>, &'static str, bool) {
        let playlist = playlist.clone();
        // Sources par ordre de préférence. On s'arrête à la première qui
        // contient un programme en cours ou à venir ; à défaut, la première
        // non vide sert de repli.
        let mut programmes: Vec<Value> = Vec::new();
        let mut source: &'static str = "xtream";
        let mut found = false;
        for name in ["panel-xmltv", "xmltv", "xtream"] {
            let candidate = match name {
                "panel-xmltv" => self.panel_programmes(&playlist, channel_id).await,
                "xmltv" => {
                    self.programmes_from_xmltv(self.inner.xmltv.clone(), &playlist, channel_id)
                        .await
                }
                _ => self.xtream_programmes(&playlist, channel_id).await,
            };
            if candidate.is_empty() {
                continue;
            }
            let current = has_current_programme(&candidate);
            if !found || current {
                programmes = candidate;
                source = name;
                found = true;
            }
            if current {
                break;
            }
        }
        (programmes, source, found)
    }

    async fn panel_programmes(&self, playlist: &PlaylistConfig, channel_id: &str) -> Vec<Value> {
        let key = format!("{}|{}", playlist.dns, playlist.username);
        let service = self
            .inner
            .panel_xmltv
            .lock()
            .unwrap()
            .entry(key)
            .or_insert_with(|| Arc::new((self.inner.panel_builder)(playlist)))
            .clone();
        self.programmes_from_xmltv(Some(service), playlist, channel_id)
            .await
    }

    /// Programmes d'une chaîne dans un index XMLTV (panneau ou externe).
    async fn programmes_from_xmltv(
        &self,
        xmltv: Option<Arc<XmltvEpgService>>,
        playlist: &PlaylistConfig,
        channel_id: &str,
    ) -> Vec<Value> {
        let Some(xmltv) = xmltv else {
            return Vec::new();
        };
        let channels = self.channel_map_for(playlist).await;
        let epg_id = channels.epg_ids.get(channel_id).map(String::as_str);
        let name = channels.names.get(channel_id).map(String::as_str);
        if epg_id.is_none() && name.is_none() {
            return Vec::new();
        }
        let now = Utc::now();
        xmltv
            .programmes_for(epg_id, name)
            .await
            .iter()
            .filter(|p| p.stop > now)
            .take(64)
            .map(|p| p.to_json(channel_id))
            .collect()
    }

    /// Interrogation du panneau chaîne par chaîne : chemin lent, plusieurs
    /// secondes par action, réservé aux chaînes absentes des dumps.
    async fn xtream_programmes(&self, playlist: &PlaylistConfig, channel_id: &str) -> Vec<Value> {
        // `get_simple_data_table` d'abord : seule action réellement
        // universelle. `get_epg` manque sur beaucoup de panneaux, qui
        // renvoient alors le payload d'authentification.
        for action in ["get_simple_data_table", "get_short_epg"] {
            let url = format!(
                "{}/player_api.php?username={}&password={}&action={action}&stream_id={channel_id}",
                playlist.dns, playlist.username, playlist.password
            );
            let fetch = async {
                let response = self.inner.http.get(&url).send().await?;
                let status = response.status().as_u16();
                Ok::<_, reqwest::Error>((status, response.bytes().await?))
            };
            let (status, body) = match tokio::time::timeout(Duration::from_secs(20), fetch).await {
                Ok(Ok(r)) => r,
                Ok(Err(e)) => {
                    // Une source parmi d'autres, pas une raison de répondre 500.
                    println!(
                        "[EpgApi] player_api {action} indisponible pour {channel_id} : {}",
                        redact_url(&format!("{e:?}"))
                    );
                    continue;
                }
                Err(_) => {
                    println!(
                        "[EpgApi] player_api {action} indisponible pour {channel_id} : TimeoutException after 0:00:20.000000"
                    );
                    continue;
                }
            };
            if status != 200 {
                continue;
            }
            let Ok(raw) = serde_json::from_str::<Value>(&String::from_utf8_lossy(&body)) else {
                continue;
            };
            let programmes: Vec<Value> = transform_epg_data(&raw, channel_id)["programmes"]
                .as_array()
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .filter(Value::is_object)
                .collect();
            if !programmes.is_empty() {
                return programmes;
            }
        }
        Vec::new()
    }

    /// Table des chaînes du compte, rafraîchie toutes les 6 heures. Les
    /// requêtes simultanées partagent un seul téléchargement : la grille
    /// demande le guide de 30 chaînes d'un coup (7 Mo de table en prod).
    async fn channel_map_for(&self, playlist: &PlaylistConfig) -> Arc<ChannelMap> {
        let key = format!("{}|{}", playlist.dns, playlist.username);
        if let Some(map) = self.inner.channel_maps.lock().unwrap().get(&key)
            && map.expires_at.is_some_and(|e| Instant::now() < e)
        {
            return map.clone();
        }
        let shared = {
            let mut in_flight = self.inner.channel_maps_in_flight.lock().unwrap();
            match in_flight.get(&key) {
                Some(f) => f.clone(),
                None => {
                    let inner = self.inner.clone();
                    let playlist = playlist.clone();
                    let task_key = key.clone();
                    // Tâche détachée : le téléchargement aboutit même si le
                    // client qui l'a déclenché est parti.
                    let handle = tokio::spawn(async move {
                        let map = Arc::new(load_channel_map(&inner.http, &playlist).await);
                        inner
                            .channel_maps
                            .lock()
                            .unwrap()
                            .insert(task_key.clone(), map.clone());
                        inner
                            .channel_maps_in_flight
                            .lock()
                            .unwrap()
                            .remove(&task_key);
                        map
                    });
                    let f = async move { handle.await.unwrap_or_default() }
                        .boxed()
                        .shared();
                    in_flight.insert(key, f.clone());
                    f
                }
            }
        };
        shared.await
    }
}

async fn load_channel_map(client: &reqwest::Client, playlist: &PlaylistConfig) -> ChannelMap {
    let url = format!(
        "{}/player_api.php?username={}&password={}&action=get_live_streams",
        playlist.dns, playlist.username, playlist.password
    );
    let fetch = async {
        let response = client.get(&url).send().await?;
        let status = response.status().as_u16();
        Ok::<_, reqwest::Error>((status, response.bytes().await?))
    };
    let (mut epg_ids, mut names) = (HashMap::new(), HashMap::new());
    match tokio::time::timeout(Duration::from_secs(90), fetch).await {
        Ok(Ok((200, body))) => {
            // Décodage hors du runtime : 7 Mo de JSON gelaient sinon le relais
            // des flux en cours.
            match tokio::task::spawn_blocking(move || parse_channel_table(&body)).await {
                Ok(parsed) => (epg_ids, names) = parsed,
                Err(e) => println!("[EpgApi] table des chaînes illisible : {e}"),
            }
        }
        Ok(Ok(_)) => {}
        Ok(Err(e)) => println!(
            "[EpgApi] table des chaînes indisponible : {}",
            redact_url(&format!("{e:?}"))
        ),
        Err(_) => println!(
            "[EpgApi] table des chaînes indisponible : TimeoutException after 0:01:30.000000"
        ),
    }
    // Une table vide (panneau en échec) n'est gardée que 2 minutes : la
    // garder 6 h privait TOUTES les chaînes du repli XMLTV pendant 6 h.
    let ttl = if names.is_empty() {
        Duration::from_secs(120)
    } else {
        Duration::from_secs(6 * 3600)
    };
    ChannelMap {
        epg_ids,
        names,
        expires_at: Some(Instant::now() + ttl),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::{Query, Request};
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn convertit_les_epoch_en_utc_et_decode_le_base64() {
        let raw = json!({"epg_listings": [{
            "title": "Sm91cm5hbCBkZSAyMGg=",
            "start": "2026-08-11 20:00:00",
            "end": "2026-08-11 20:35:00",
            "description": "TCdpbmZvIGR1IHNvaXI=",
            "start_timestamp": "1786471200",
            "stop_timestamp": "1786473300",
        }]});
        let result = transform_epg_data(&raw, "845452");
        let p = &result["programmes"][0];
        assert_eq!(p["start"], "2026-08-11T18:00:00.000Z");
        assert_eq!(p["end"], "2026-08-11T18:35:00.000Z");
        assert_eq!(p["title"], "Journal de 20h");
        assert_eq!(p["description"], "L'info du soir");
        assert_eq!(p["channel_id"], "845452");
    }

    #[test]
    fn retombe_sur_les_champs_texte() {
        let raw = json!({"epg_listings": [{
            "title": "Sm91cm5hbCBkZSAyMGg=",
            "start": "2026-08-11 20:00:00",
            "stop": "2026-08-11 20:35:00",
        }]});
        let p = &transform_epg_data(&raw, "845452")["programmes"][0];
        assert_eq!(p["start"], "2026-08-11T20:00:00");
        assert_eq!(p["end"], "2026-08-11T20:35:00");
    }

    #[test]
    fn liste_vide_sans_epg_listings() {
        let raw = json!({"user_info": {"auth": 1}, "server_info": {"url": "x"}});
        assert_eq!(transform_epg_data(&raw, "1")["programmes"], json!([]));
    }

    // ---------- handle() contre un faux panneau ----------

    type Handler = Arc<dyn Fn(&str, &HashMap<String, String>) -> (u16, String) + Send + Sync>;

    async fn mock(handler: Handler) -> String {
        let app = axum::Router::new().fallback(
            move |Query(q): Query<HashMap<String, String>>, req: Request| {
                let handler = handler.clone();
                async move {
                    // Laisser respirer les requêtes concurrentes (mutualisation).
                    tokio::time::sleep(Duration::from_millis(30)).await;
                    let (status, body) = handler(req.uri().path(), &q);
                    (axum::http::StatusCode::from_u16(status).unwrap(), body)
                }
            },
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        format!("http://{addr}")
    }

    fn stamp(d: chrono::DateTime<Utc>) -> String {
        d.format("%Y%m%d%H%M%S +0000").to_string()
    }

    fn dump(
        id: &str,
        name: &str,
        start: chrono::DateTime<Utc>,
        stop: chrono::DateTime<Utc>,
    ) -> String {
        format!(
            r#"<?xml version="1.0" encoding="utf-8" ?><tv><channel id="{id}"><display-name>{name}</display-name></channel><programme start="{}" stop="{}" channel="{id}"><title lang="fr">Journal de 20h</title><desc lang="fr">L'info du soir</desc></programme></tv>"#,
            stamp(start),
            stamp(stop)
        )
    }

    fn playlist(base: &str) -> PlaylistConfig {
        PlaylistConfig {
            dns: base.to_string(),
            username: "u".into(),
            password: "p".into(),
        }
    }

    fn api(base: &str, external: bool) -> EpgApi {
        let client = reqwest::Client::new();
        let xmltv = external.then(|| {
            Arc::new(XmltvEpgService::new(
                XmltvConfig::new(vec![format!("{base}/ext/epg.xml")]),
                client.clone(),
            ))
        });
        let c = client.clone();
        let builder: PanelXmltvBuilder = Arc::new(move |p: &PlaylistConfig| {
            XmltvEpgService::new(
                XmltvConfig::new(vec![format!("{}/xmltv.php", p.dns)]),
                c.clone(),
            )
        });
        EpgApi::new(xmltv, client, builder)
    }

    async fn body_json(resp: Resp) -> Value {
        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        serde_json::from_slice(&bytes).unwrap()
    }

    #[tokio::test]
    async fn sert_le_dump_du_panneau_sans_appel_par_chaine() {
        let now = Utc::now();
        let actions = Arc::new(Mutex::new(Vec::<String>::new()));
        let a = actions.clone();
        let base = mock(Arc::new(move |path, q| {
            if path.ends_with("/xmltv.php") {
                return (200, dump("France2.fr", "FRANCE 2", now - chrono::Duration::minutes(5), now + chrono::Duration::minutes(25)));
            }
            let action = q.get("action").cloned().unwrap_or_default();
            a.lock().unwrap().push(action.clone());
            if action == "get_live_streams" {
                return (200, json!([{"stream_id": 845452, "name": "FRANCE 2", "epg_channel_id": "France2.fr"}]).to_string());
            }
            (200, "{}".into())
        }))
        .await;
        let resp = api(&base, false)
            .handle(Some(playlist(&base)), "845452")
            .await;
        assert_eq!(resp.status().as_u16(), 200);
        assert_eq!(resp.headers()["x-epg-source"], "panel-xmltv");
        let body = body_json(resp).await;
        assert_eq!(body["programmes"][0]["title"], "Journal de 20h");
        assert_eq!(*actions.lock().unwrap(), vec!["get_live_streams"]);
    }

    #[tokio::test]
    async fn retombe_sur_player_api_quand_le_dump_ne_couvre_pas_la_chaine() {
        let future = chrono::Local::now() + chrono::Duration::minutes(10);
        let panel_stamp =
            |d: chrono::DateTime<chrono::Local>| d.format("%Y-%m-%d %H:%M:%S").to_string();
        let start = panel_stamp(future);
        let end = panel_stamp(future + chrono::Duration::hours(2));
        let base = mock(Arc::new(move |path, q| {
            if path.ends_with("/xmltv.php") {
                return (200, "<tv></tv>".into());
            }
            match q.get("action").map(String::as_str) {
                Some("get_live_streams") => (200, "[]".into()),
                Some("get_simple_data_table") => (
                    200,
                    json!({"epg_listings": [{"title": "TWF0Y2g=", "description": "", "start": start, "end": end}]}).to_string(),
                ),
                _ => (200, "{}".into()),
            }
        }))
        .await;
        let resp = api(&base, false).handle(Some(playlist(&base)), "999").await;
        assert_eq!(resp.headers()["x-epg-source"], "xtream");
        assert_eq!(body_json(resp).await["programmes"][0]["title"], "Match");
    }

    #[tokio::test]
    async fn un_panneau_qui_plante_ne_prive_pas_du_dump_externe() {
        let now = Utc::now();
        let base = mock(Arc::new(move |path, q| {
            if path == "/ext/epg.xml" {
                return (
                    200,
                    dump("TF1.fr", "TF1", now, now + chrono::Duration::hours(1)),
                );
            }
            if path.ends_with("/xmltv.php") {
                return (200, "<tv></tv>".into());
            }
            if q.get("action").map(String::as_str) == Some("get_live_streams") {
                return (
                    200,
                    json!([{"stream_id": 1, "name": "FR - TF1 FHD ◉", "epg_channel_id": ""}])
                        .to_string(),
                );
            }
            (500, "boom".into())
        }))
        .await;
        let resp = api(&base, true).handle(Some(playlist(&base)), "1").await;
        assert_eq!(resp.status().as_u16(), 200);
        assert_eq!(resp.headers()["x-epg-source"], "xmltv");
        assert_eq!(
            body_json(resp).await["programmes"][0]["title"],
            "Journal de 20h"
        );
    }

    #[tokio::test]
    async fn le_dump_externe_passe_avant_l_appel_lent() {
        let now = Utc::now();
        let actions = Arc::new(Mutex::new(Vec::<String>::new()));
        let a = actions.clone();
        let base = mock(Arc::new(move |path, q| {
            if path == "/ext/epg.xml" {
                return (
                    200,
                    dump("TF1.fr", "TF1", now, now + chrono::Duration::hours(1)),
                );
            }
            if path.ends_with("/xmltv.php") {
                return (200, "<tv></tv>".into());
            }
            let action = q.get("action").cloned().unwrap_or_default();
            a.lock().unwrap().push(action.clone());
            if action == "get_live_streams" {
                return (
                    200,
                    json!([{"stream_id": 1, "name": "TF1", "epg_channel_id": "TF1.fr"}])
                        .to_string(),
                );
            }
            (200, "{}".into())
        }))
        .await;
        let resp = api(&base, true).handle(Some(playlist(&base)), "1").await;
        assert_eq!(resp.headers()["x-epg-source"], "xmltv");
        assert!(
            !actions
                .lock()
                .unwrap()
                .contains(&"get_simple_data_table".to_string())
        );
    }

    #[tokio::test]
    async fn la_grille_partage_un_seul_telechargement_de_la_table() {
        let now = Utc::now();
        let calls = Arc::new(AtomicUsize::new(0));
        let c = calls.clone();
        let base = mock(Arc::new(move |path, q| {
            if path == "/ext/epg.xml" {
                return (
                    200,
                    dump("TF1.fr", "TF1", now, now + chrono::Duration::hours(1)),
                );
            }
            if path.ends_with("/xmltv.php") {
                return (200, "<tv></tv>".into());
            }
            if q.get("action").map(String::as_str) == Some("get_live_streams") {
                c.fetch_add(1, Ordering::SeqCst);
                let list: Vec<Value> = (1..=5)
                    .map(|i| json!({"stream_id": i, "name": "TF1", "epg_channel_id": "TF1.fr"}))
                    .collect();
                return (200, Value::Array(list).to_string());
            }
            (200, "{}".into())
        }))
        .await;
        let api = api(&base, true);
        let ids: Vec<String> = (1..=5).map(|i| i.to_string()).collect();
        let responses =
            futures::future::join_all(ids.iter().map(|id| api.handle(Some(playlist(&base)), id)))
                .await;
        assert!(responses.iter().all(|r| r.status().as_u16() == 200));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn cache_hit_au_second_appel() {
        let now = Utc::now();
        let base = mock(Arc::new(move |path, q| {
            if path.ends_with("/xmltv.php") {
                return (
                    200,
                    dump(
                        "France2.fr",
                        "FRANCE 2",
                        now,
                        now + chrono::Duration::minutes(25),
                    ),
                );
            }
            if q.get("action").map(String::as_str) == Some("get_live_streams") {
                return (
                    200,
                    json!([{"stream_id": 7, "name": "FRANCE 2", "epg_channel_id": "France2.fr"}])
                        .to_string(),
                );
            }
            (200, "{}".into())
        }))
        .await;
        let api = api(&base, false);
        let first = api.handle(Some(playlist(&base)), "7").await;
        assert_eq!(first.headers()["x-cache"], "MISS");
        let second = api.handle(Some(playlist(&base)), "7").await;
        assert_eq!(second.headers()["x-cache"], "HIT");
        assert!(api.handle(None, "7").await.status().as_u16() == 403);
    }
}
