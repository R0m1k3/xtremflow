//! Proxy Xtream `/api/xtream/<url>` (images, API du panneau) avec
//! protections anti-SSRF, et mémoire des hôtes d'images hors service.

use crate::http::{self, Req, Resp, extract_token};
use crate::models::PlaylistConfig;
use crate::state::AppState;
use crate::util::log_redactor::redact_url;
use axum::body::Body;
use futures::TryStreamExt;
use serde_json::json;
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Réponse pour une image indisponible.
///
/// Statut 410 et non 404 : la cascade du serveur retombe sur l'étage suivant
/// pour tout 404 et renverrait finalement celui des fichiers statiques, sans
/// notre `cache-control`. Un 410 s'arrête ici.
///
/// Un statut d'erreur plutôt qu'une image vide : le client affiche alors son
/// propre repli (icône, initiale) au lieu d'une tuile blanche. Le `max-age`
/// est essentiel : sans lui le navigateur redemande le logo à chaque
/// affichage de la grille.
pub fn missing_image_response() -> Resp {
    http::with_headers(
        http::empty(410),
        &[
            ("cache-control", "public, max-age=600"),
            ("access-control-allow-origin", "*"),
        ],
    )
}

/// Mémoire courte des hôtes d'images injoignables.
///
/// POURQUOI : les URL de picons pointent chez l'hébergeur du revendeur, pas
/// sur le panneau. Quand cette machine tombe, elle répond 5xx en quelques
/// millisecondes, le navigateur réessaie à chaque rendu de la grille et le
/// proxy relaie des centaines de requêtes mortes par seconde. Au bout de
/// [threshold] échecs consécutifs, l'hôte est tenu pour mort pendant [ttl]
/// et les requêtes suivantes sont servies localement, sans appel sortant.
pub struct AssetFailureCache {
    threshold: u32,
    ttl: Duration,
    failures: Mutex<HashMap<String, u32>>,
    down_until: Mutex<HashMap<String, Instant>>,
}

impl AssetFailureCache {
    pub fn new(threshold: u32, ttl: Duration) -> Self {
        Self {
            threshold,
            ttl,
            failures: Mutex::default(),
            down_until: Mutex::default(),
        }
    }

    pub fn is_down(&self, host: &str) -> bool {
        self.is_down_at(host, Instant::now())
    }

    fn is_down_at(&self, host: &str, now: Instant) -> bool {
        let key = host.to_lowercase();
        let mut down = self.down_until.lock().unwrap();
        let Some(until) = down.get(&key).copied() else {
            return false;
        };
        if now < until {
            return true;
        }
        // Coupure expirée : ardoise vierge pour laisser une vraie chance.
        down.remove(&key);
        self.failures.lock().unwrap().remove(&key);
        false
    }

    pub fn record_failure(&self, host: &str) {
        self.record_failure_at(host, Instant::now());
    }

    fn record_failure_at(&self, host: &str, now: Instant) {
        let key = host.to_lowercase();
        let count = {
            let mut failures = self.failures.lock().unwrap();
            let count = failures.entry(key.clone()).or_insert(0);
            *count += 1;
            *count
        };
        if count >= self.threshold {
            self.down_until.lock().unwrap().insert(key, now + self.ttl);
        }
    }

    pub fn record_success(&self, host: &str) {
        let key = host.to_lowercase();
        self.failures.lock().unwrap().remove(&key);
        self.down_until.lock().unwrap().remove(&key);
    }
}

/// L'URL désigne-t-elle une image ou un logo ? Ces URL échappent à
/// l'allowlist de domaine (les revendeurs hébergent leurs picons ailleurs
/// que le panneau) et méritent un repli visuel plutôt qu'une erreur.
fn is_static_asset_url(url: &reqwest::Url) -> bool {
    let path = url.path();
    [".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico"]
        .iter()
        .any(|ext| path.ends_with(ext))
        || path.contains("/picons/")
        || path.contains("/logos/")
}

/// Hôte à ne jamais atteindre par le proxy (loopback, LAN privé,
/// link-local/métadonnées cloud) — protection SSRF des URL d'images qui
/// échappent à l'allowlist de domaine.
pub fn is_forbidden_proxy_host(host: &str) -> bool {
    let lower = host.to_lowercase();
    let lower = lower.trim_start_matches('[').trim_end_matches(']');
    if lower == "localhost" || lower == "::1" {
        return true;
    }
    let Ok(ip) = lower.parse::<IpAddr>() else {
        return false; // nom d'hôte : validé par l'allowlist de domaine
    };
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            v4.is_loopback()
                || o[0] == 10
                || (o[0] == 172 && (16..=31).contains(&o[1]))
                || (o[0] == 192 && o[1] == 168)
                || (o[0] == 169 && o[1] == 254)
                || o[0] == 0
        }
        IpAddr::V6(v6) => v6.is_loopback() || (v6.segments()[0] & 0xffc0) == 0xfe80,
    }
}

fn host_of(url: &reqwest::Url) -> String {
    url.host_str()
        .unwrap_or("")
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_string()
}

const ALLOWED_RESPONSE_HEADERS: [&str; 6] = [
    "content-type",
    "content-range",
    "accept-ranges",
    "cache-control",
    "server",
    "date",
];
const ALLOWED_REQUEST_HEADERS: [&str; 4] = ["user-agent", "accept", "range", "referer"];

pub struct ProxyHandler {
    asset_failures: AssetFailureCache,
    /// Playlist servant à l'allowlist, mise en cache 5 minutes pour éviter
    /// une requête SQL par segment.
    playlist_cache: Mutex<Option<(PlaylistConfig, Instant)>>,
}

enum ProxyError {
    Response(Resp),
    Failure(String),
}

impl ProxyHandler {
    pub fn new() -> Self {
        Self {
            asset_failures: AssetFailureCache::new(3, Duration::from_secs(300)),
            playlist_cache: Mutex::new(None),
        }
    }

    fn cached_playlist(&self, state: &AppState, req: &Req) -> Option<PlaylistConfig> {
        if let Some((playlist, expiry)) = self.playlist_cache.lock().unwrap().as_ref()
            && Instant::now() < *expiry
        {
            return Some(playlist.clone());
        }
        let playlist = state.get_playlist(req)?;
        *self.playlist_cache.lock().unwrap() =
            Some((playlist.clone(), Instant::now() + Duration::from_secs(300)));
        Some(playlist)
    }

    pub async fn handle(&self, state: &AppState, req: &Req) -> Resp {
        // Le test de chemin passe AVANT tout : les autres requêtes doivent
        // retomber sur les étages suivants de la cascade.
        let Some(api_path) = req.path.strip_prefix("api/xtream/") else {
            return http::empty(404);
        };

        // Authentification par session (en-tête ou cookie HttpOnly posé au
        // login : `img src` et hls.js n'envoient que le cookie). Un proxy
        // ouvert offrait un rebond SSRF non authentifié.
        let authorized = extract_token(req)
            .is_some_and(|token| state.db.find_session_by_token(&token).is_some());
        if !authorized {
            return http::text(401, "Unauthorized");
        }

        let mut api_path = api_path.to_string();
        if api_path.starts_with("http%3A") || api_path.starts_with("https%3A") {
            api_path = percent_encoding::percent_decode_str(&api_path)
                .decode_utf8_lossy()
                .into_owned();
        }
        if !api_path.starts_with("http://") && !api_path.starts_with("https://") {
            return http::text(
                400,
                "Invalid API URL. Expected format: /api/xtream/http://...",
            );
        }
        let mut full_url = api_path;
        if !req.query.is_empty() {
            full_url.push(if full_url.contains('?') { '&' } else { '?' });
            full_url.push_str(&req.query);
        }

        let target = reqwest::Url::parse(&full_url).ok();
        match self.forward(state, req, target.clone()).await {
            Ok(resp) => resp,
            Err(ProxyError::Response(resp)) => resp,
            Err(ProxyError::Failure(error)) => {
                // Une erreur reqwest recopie l'URL amont, identifiants inclus :
                // jamais de détail vers le client, log masqué.
                println!(
                    "[ProxyHandler] error on {}: {}",
                    redact_url(&req.path),
                    redact_url(&error)
                );
                if let Some(target) = target.filter(is_static_asset_url) {
                    self.asset_failures.record_failure(&host_of(&target));
                    return missing_image_response();
                }
                http::json(500, &json!({"error": "Proxy error"}))
            }
        }
    }

    async fn forward(
        &self,
        state: &AppState,
        req: &Req,
        target: Option<reqwest::Url>,
    ) -> Result<Resp, ProxyError> {
        let target =
            target.ok_or_else(|| ProxyError::Failure("FormatException: invalid URL".into()))?;
        if target.scheme() != "http" && target.scheme() != "https" {
            return Err(ProxyError::Response(http::text(
                403,
                "Unsupported URL scheme",
            )));
        }
        let target_host = host_of(&target);
        if is_forbidden_proxy_host(&target_host) {
            println!("[Proxy] Blocked SSRF attempt to private host: {target_host}");
            return Err(ProxyError::Response(http::text(
                403,
                "Access to this host is forbidden",
            )));
        }

        // Images : tout hôte autorisé (CDN de picons des revendeurs).
        let is_static_asset = is_static_asset_url(&target);
        // Hôte d'images déjà constaté mort : réponse immédiate, sans appel
        // sortant ni log — c'est précisément le flot qu'on veut éteindre.
        if is_static_asset && self.asset_failures.is_down(&target_host) {
            return Ok(missing_image_response());
        }

        let mut allowed_host = None;
        if !is_static_asset {
            // Appels d'API : allowlist de domaine.
            let Some(playlist) = self.cached_playlist(state, req) else {
                return Err(ProxyError::Response(http::text(
                    403,
                    "No active playlist configuration found to validate request",
                )));
            };
            let allowed = reqwest::Url::parse(&playlist.dns)
                .map(|u| host_of(&u).to_lowercase())
                .unwrap_or_default();
            if target_host.to_lowercase() != allowed {
                println!(
                    "[Proxy] Blocked SSRF attempt to {} (Allowed: {allowed})",
                    target_host.to_lowercase()
                );
                return Err(ProxyError::Response(http::text(
                    403,
                    "Access to this domain is forbidden by policy",
                )));
            }
            allowed_host = Some(allowed);
        }

        let mut headers = reqwest::header::HeaderMap::new();
        let mut set = |name: &str, value: &str| {
            if let (Ok(n), Ok(v)) = (
                reqwest::header::HeaderName::from_bytes(name.as_bytes()),
                reqwest::header::HeaderValue::from_str(value),
            ) {
                headers.insert(n, v);
            }
        };
        set("user-agent", "VLC/3.0.18 LibVLC/3.0.18");
        set("accept", "*/*");
        set("accept-encoding", "identity");
        for name in ALLOWED_REQUEST_HEADERS {
            if let Some(value) = req.header(name) {
                set(name, value);
            }
        }

        println!("[Proxy] Forwarding to: {}", redact_url(target.as_str()));
        let method = reqwest::Method::from_bytes(req.method.as_str().as_bytes())
            .unwrap_or(reqwest::Method::GET);
        let post_body = (req.method == axum::http::Method::POST).then(|| req.body.clone());

        // Redirections suivies À LA MAIN : chaque destination est revalidée
        // (hôte privé, allowlist). Une 302 du serveur amont suffisait sinon à
        // atteindre un hôte interne malgré l'anti-SSRF.
        let mut current = target.clone();
        let mut redirects = 0;
        let response = loop {
            let mut builder = state
                .http_manual
                .request(method.clone(), current.clone())
                .headers(headers.clone());
            if let Some(body) = &post_body {
                builder = builder.body(body.clone());
            }
            // 90 s : laisse le front (60 s) abandonner proprement le premier.
            let response = tokio::time::timeout(Duration::from_secs(90), builder.send())
                .await
                .map_err(|_| ProxyError::Failure("TimeoutException after 0:01:30.000000".into()))?
                .map_err(|e| ProxyError::Failure(format!("{e:?}")))?;

            let status = response.status().as_u16();
            let location = response
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .map(str::to_string);
            let Some(location) = location.filter(|_| (300..400).contains(&status)) else {
                break response;
            };
            redirects += 1;
            if redirects > 3 {
                return Err(ProxyError::Response(http::text(403, "Too many redirects")));
            }
            current = current
                .join(&location)
                .map_err(|e| ProxyError::Failure(e.to_string()))?;
            if current.scheme() != "http" && current.scheme() != "https" {
                return Err(ProxyError::Response(http::text(
                    403,
                    "Unsupported redirect scheme",
                )));
            }
            let host = host_of(&current);
            if is_forbidden_proxy_host(&host) {
                println!("[Proxy] Blocked SSRF redirect to private host: {host}");
                return Err(ProxyError::Response(http::text(
                    403,
                    "Access to this host is forbidden",
                )));
            }
            if let Some(allowed) = &allowed_host
                && host.to_lowercase() != *allowed
            {
                println!("[Proxy] Blocked redirect to {host} (Allowed: {allowed})");
                return Err(ProxyError::Response(http::text(
                    403,
                    "Access to this domain is forbidden by policy",
                )));
            }
        };

        // Une image en erreur n'a rien à transmettre au navigateur : relayer
        // le 503 déclenchait un nouveau cycle de requêtes à chaque rendu.
        // L'échec est compté sur l'hôte DEMANDÉ (clé du garde-fou ci-dessus).
        let status = response.status().as_u16();
        if is_static_asset {
            if status >= 400 {
                self.asset_failures.record_failure(&target_host);
                return Ok(missing_image_response());
            }
            self.asset_failures.record_success(&target_host);
        }

        let upstream_headers = response.headers().clone();
        let mut resp = http::response(
            status,
            Body::from_stream(response.bytes_stream().map_err(std::io::Error::other)),
        );
        http::set_header(&mut resp, "access-control-allow-origin", "*");
        for name in ALLOWED_RESPONSE_HEADERS {
            let values: Vec<&str> = upstream_headers
                .get_all(name)
                .iter()
                .filter_map(|v| v.to_str().ok())
                .collect();
            if !values.is_empty() {
                http::set_header(&mut resp, name, &values.join(", "));
            }
        }
        Ok(resp)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bloque_le_loopback() {
        assert!(is_forbidden_proxy_host("127.0.0.1"));
        assert!(is_forbidden_proxy_host("localhost"));
        assert!(is_forbidden_proxy_host("::1"));
        assert!(is_forbidden_proxy_host("[::1]"));
    }

    #[test]
    fn bloque_les_plages_privees() {
        assert!(is_forbidden_proxy_host("10.0.0.5"));
        assert!(is_forbidden_proxy_host("172.16.0.1"));
        assert!(is_forbidden_proxy_host("172.31.255.255"));
        assert!(is_forbidden_proxy_host("192.168.1.10"));
        assert!(is_forbidden_proxy_host("169.254.169.254"));
        assert!(is_forbidden_proxy_host("0.0.0.0"));
    }

    #[test]
    fn autorise_les_ip_publiques_et_les_noms() {
        assert!(!is_forbidden_proxy_host("8.8.8.8"));
        assert!(!is_forbidden_proxy_host("172.32.0.1"));
        assert!(!is_forbidden_proxy_host("cdn.example.com"));
    }

    #[test]
    fn cache_des_hotes_morts() {
        let cache = AssetFailureCache::new(3, Duration::from_secs(300));
        let t0 = Instant::now();
        assert!(!cache.is_down_at("cdn.example", t0));
        cache.record_failure_at("cdn.example", t0);
        assert!(!cache.is_down_at("cdn.example", t0));
        cache.record_failure_at("cdn.example", t0);
        cache.record_success("cdn.example");
        cache.record_failure_at("cdn.example", t0);
        assert!(!cache.is_down_at("cdn.example", t0));
        cache.record_failure_at("CDN.example", t0);
        cache.record_failure_at("cdn.example", t0);
        assert!(cache.is_down_at("cdn.example", t0));
        // Coupure expirée : ardoise vierge.
        assert!(!cache.is_down_at("cdn.example", t0 + Duration::from_secs(301)));
        cache.record_failure_at("cdn.example", t0);
        assert!(!cache.is_down_at("cdn.example", t0));
    }
}
