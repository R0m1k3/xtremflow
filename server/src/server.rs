//! Point d'entrée HTTP : middlewares puis cascade API → proxy Xtream →
//! streaming → fichiers statiques, à l'identique de l'ancien serveur.

use crate::api::{
    account, admin, auto_rules, logo, player_log, recordings, static_files, xtream_api,
};
use crate::dart_time::now_local_iso;
use crate::http::{self, Req, Resp, client_ip, extract_token, is_miss, mounted, socket_ip};
use crate::state::SharedState;
use crate::util::log_redactor::redact_url;
use axum::extract::{ConnectInfo, Request, State};
use axum::http::Method;
use std::collections::{HashMap, VecDeque};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Corps de requête maximal lu en mémoire.
const MAX_BODY: usize = 16 * 1024 * 1024;

/// Limiteur glissant par IP sur une minute.
pub struct RateLimiter {
    limit: usize,
    history: Arc<Mutex<HashMap<String, VecDeque<Instant>>>>,
}

impl RateLimiter {
    pub fn new(limit: usize) -> Self {
        let history: Arc<Mutex<HashMap<String, VecDeque<Instant>>>> = Arc::default();
        // Ménage toutes les 5 minutes (pas de fuite mémoire par IP).
        let h = history.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(300));
            interval.tick().await;
            loop {
                interval.tick().await;
                h.lock().unwrap().retain(|_, times| {
                    times.retain(|t| t.elapsed() < Duration::from_secs(120));
                    !times.is_empty()
                });
            }
        });
        Self { limit, history }
    }

    /// Enregistre une requête ; `false` si la limite est atteinte.
    pub fn allow(&self, ip: &str) -> bool {
        let mut history = self.history.lock().unwrap();
        let times = history.entry(ip.to_string()).or_default();
        while times
            .front()
            .is_some_and(|t| t.elapsed() >= Duration::from_secs(60))
        {
            times.pop_front();
        }
        if times.len() >= self.limit {
            return false;
        }
        times.push_back(Instant::now());
        true
    }
}

/// Handler axum unique : lit le corps puis applique la chaîne complète.
pub async fn entry(
    State(state): State<SharedState>,
    ConnectInfo(remote): ConnectInfo<SocketAddr>,
    request: Request,
) -> Resp {
    let (parts, body) = request.into_parts();
    let body = match axum::body::to_bytes(body, MAX_BODY).await {
        Ok(b) => b,
        Err(_) => return http::text(413, "Request Entity Too Large"),
    };
    let req = Req {
        method: parts.method,
        path: parts.uri.path().trim_start_matches('/').to_string(),
        query: parts.uri.query().unwrap_or("").to_string(),
        headers: parts.headers,
        body,
        remote: Some(remote),
        user: None,
        user_id: None,
    };
    handle(&state, req).await
}

pub async fn handle(state: &SharedState, req: Req) -> Resp {
    // Journal masqué : le chemin de /api/xtream/<url> porte les
    // identifiants Xtream en clair.
    let started = Instant::now();
    let log_target = if req.query.is_empty() {
        format!("/{}", req.path)
    } else {
        format!("/{}?{}", req.path, req.query)
    };
    let method = req.method.clone();

    let mut resp = security_chain(state, req).await;
    add_security_headers(&mut resp);

    println!(
        "{} {} {method} {} ({}ms)",
        now_local_iso(),
        resp.status().as_u16(),
        redact_url(&log_target),
        started.elapsed().as_millis()
    );
    resp
}

fn add_security_headers(resp: &mut Resp) {
    for (name, value) in [
        ("x-content-type-options", "nosniff"),
        // SAMEORIGIN : les iframes player.html restent intégrables.
        ("x-frame-options", "SAMEORIGIN"),
        ("x-xss-protection", "1; mode=block"),
        (
            "strict-transport-security",
            "max-age=63072000; includeSubDomains; preload",
        ),
        ("referrer-policy", "strict-origin-when-cross-origin"),
        // Report-Only : Flutter Web (CanvasKit/wasm) et google_fonts peuvent
        // casser sous une CSP appliquée.
        (
            "content-security-policy-report-only",
            "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'unsafe-eval'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob: https:; media-src 'self' blob:; connect-src 'self' https://fonts.gstatic.com",
        ),
    ] {
        http::set_header(resp, name, value);
    }
}

/// Chemins classiques des scanners de vulnérabilités.
const HONEYPOT_PATHS: [&str; 9] = [
    "/admin/phpmyadmin",
    "/phpmyadmin",
    "/wp-admin",
    "/wp-login.php",
    "/.env",
    "/config.php",
    "/api/.env",
    "/console",
    "/actuator/health",
];

async fn security_chain(state: &SharedState, req: Req) -> Resp {
    // Honeypot : chemin exact ou préfixe de segment (pas une sous-chaîne
    // quelconque, qui bloquait des URL proxifiées légitimes).
    let path = format!("/{}", req.path);
    for trap in HONEYPOT_PATHS {
        if path == trap || path.starts_with(&format!("{trap}/")) {
            println!(
                "SECURITY ALERT: Honeypot triggered by {} on path: {path}",
                client_ip(&req, &state.trusted_proxies)
            );
            return http::text(403, "Access Denied");
        }
    }

    // Limite globale : 600 req/min/IP (une grille de chaînes déclenche une
    // requête de logo et une de guide par tuile, derrière une seule IP de
    // reverse proxy).
    // Exemption des requêtes LOCALES (captures FFmpeg du planificateur) :
    // jugée sur la socket, jamais sur X-Forwarded-For qu'un client peut
    // forger à « 127.0.0.1 ».
    let ip = client_ip(&req, &state.trusted_proxies);
    let local = socket_ip(&req).is_some_and(|ip| ip.is_loopback())
        && !req.headers.contains_key("x-forwarded-for");
    if ip != "unknown" && !local && !state.rate_limit.allow(&ip) {
        println!("SECURITY WARN: Rate limit exceeded for {ip}");
        return http::text(429, "Too Many Requests");
    }

    cors(state, req).await
}

/// CORS : l'app est servie en même origine ; les en-têtes ne servent qu'au
/// développement (localhost) ou à ALLOWED_ORIGIN. L'origine n'est renvoyée
/// que si elle est autorisée — jamais de joker.
async fn cors(state: &SharedState, req: Req) -> Resp {
    let origin = req.header("origin").map(str::to_string);
    let allowed = origin.as_deref().is_some_and(|o| {
        if state
            .allowed_origin
            .as_deref()
            .is_some_and(|a| !a.is_empty() && a == o)
        {
            return true;
        }
        url::Url::parse(o)
            .ok()
            .and_then(|u| u.host_str().map(str::to_string))
            .is_some_and(|h| h == "localhost" || h == "127.0.0.1")
    });
    let headers: Vec<(&str, String)> = match (&origin, allowed) {
        (Some(o), true) => vec![
            ("access-control-allow-origin", o.clone()),
            (
                "access-control-allow-methods",
                "GET, POST, PUT, DELETE, OPTIONS".into(),
            ),
            (
                "access-control-allow-headers",
                "Origin, Content-Type, Accept, Authorization, Range, X-Playlist-Id".into(),
            ),
            (
                "access-control-expose-headers",
                "Content-Length, Content-Range".into(),
            ),
            ("access-control-allow-credentials", "true".into()),
            ("vary", "Origin".into()),
        ],
        _ => Vec::new(),
    };

    let mut resp = if req.method == Method::OPTIONS {
        http::text(200, "")
    } else {
        cascade(state, req).await
    };
    for (name, value) in headers {
        http::set_header(&mut resp, name, &value);
    }
    resp
}

/// Cascade shelf : un 404/405 passe la main à l'étage suivant.
async fn cascade(state: &SharedState, req: Req) -> Resp {
    let resp = api_router(state, &req).await;
    if !is_miss(&resp) {
        return resp;
    }
    let resp = state.proxy.handle(state, &req).await;
    if !is_miss(&resp) {
        return resp;
    }
    let resp = protected_streaming(state, &req).await;
    if !is_miss(&resp) {
        return resp;
    }
    static_files::handle(state, &req).await
}

/// Middleware d'authentification : session valide exigée, utilisateur
/// attaché à la requête.
fn authenticate(state: &SharedState, req: &Req) -> Result<Req, Resp> {
    let Some(token) = extract_token(req) else {
        return Err(http::text(401, "Unauthorized"));
    };
    let Some(session) = state.db.find_session_by_token(&token) else {
        return Err(http::text(401, "Invalid or expired session"));
    };
    let mut authed = req.clone();
    authed.user = state.db.find_user_by_id(&session.user_id);
    authed.user_id = Some(session.user_id);
    Ok(authed)
}

macro_rules! authed {
    ($state:expr, $req:expr) => {
        match authenticate($state, $req) {
            Ok(r) => r,
            Err(resp) => return resp,
        }
    };
}

async fn api_router(state: &SharedState, req: &Req) -> Resp {
    let path = req.path.as_str();

    if let Some(rest) = mounted(path, "api/auth") {
        // Protection brute force : 10 tentatives de login/min/IP, et 300 ms
        // de pénalité par échec.
        let is_login = req.method == Method::POST && path.ends_with("login");
        if is_login {
            let ip = client_ip(req, &state.trusted_proxies);
            if !state.login_rate_limit.allow(&ip) {
                println!("SECURITY WARN: Login rate limit exceeded for {ip}");
                return http::text(429, "Too many login attempts. Try again later.");
            }
        }
        let resp = account::auth(state, req, rest).await;
        if is_login && resp.status().as_u16() == 401 {
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
        return resp;
    }
    // Passerelle Xtream : identifiants injectés côté serveur.
    if mounted(path, "api/xtream-api").is_some() {
        let req = authed!(state, req);
        return xtream_api::handle(state, &req).await;
    }
    if let Some(rest) = mounted(path, "api/playlists") {
        let req = authed!(state, req);
        return account::playlists(state, &req, rest);
    }
    if let Some(rest) = mounted(path, "api/users") {
        let req = authed!(state, req);
        return account::users(state, &req, rest).await;
    }
    if let Some(rest) = mounted(path, "api/settings") {
        let req = authed!(state, req);
        return account::settings(state, &req, rest);
    }
    // NB : /api/recordings/stream/* traverse ce routeur (404) et atteint le
    // streaming plus bas dans la cascade.
    if let Some(rest) = mounted(path, "api/recordings") {
        let req = authed!(state, req);
        return recordings::recordings(state, &req, rest).await;
    }
    // Logos (le cookie de session accompagne les requêtes d'image).
    if path == "api/logo" && req.is_get() {
        let req = authed!(state, req);
        return logo::handle(state, &req).await;
    }
    // Incidents de lecture remontés par le lecteur web.
    if path == "api/player-log" && req.method == Method::POST {
        let _ = authed!(state, req);
        return player_log::handle(req);
    }
    if let Some(rest) = mounted(path, "api/epg") {
        let req = authed!(state, req);
        return match (req.is_get(), http::segments(rest).as_slice()) {
            (true, [channel_id]) => {
                let playlist = state.get_playlist(&req);
                state.epg.handle(playlist, channel_id).await
            }
            _ => http::not_found(),
        };
    }
    if let Some(rest) = mounted(path, "api/auto-rules") {
        let req = authed!(state, req);
        return auto_rules::auto_rules(state, &req, rest).await;
    }
    if let Some(rest) = mounted(path, "api/season-passes") {
        let req = authed!(state, req);
        return recordings::season_passes(state, &req, rest);
    }
    if let Some(rest) = mounted(path, "api/admin") {
        let req = authed!(state, req);
        return admin::admin(state, &req, rest).await;
    }
    http::not_found()
}

/// Streaming : le cookie de session HttpOnly est accepté (hls.js ne peut pas
/// envoyer d'en-tête Authorization) ; les requêtes FFmpeg locales du
/// planificateur (`http://localhost:8089/api/live/<id>.ts`, sans cookie)
/// passent sans authentification.
async fn protected_streaming(state: &SharedState, req: &Req) -> Resp {
    let path = req.path.as_str();
    let is_streaming = path.starts_with("api/live")
        || path.starts_with("api/vod")
        || path.starts_with("api/recordings/stream");
    if !is_streaming {
        return http::not_found();
    }
    let loopback = socket_ip(req).is_some_and(|ip| ip.is_loopback());
    let via_proxy = req.headers.contains_key("x-forwarded-for");
    if !(loopback && !via_proxy) {
        let valid =
            extract_token(req).is_some_and(|t| state.db.find_session_by_token(&t).is_some());
        if !valid {
            return http::text(401, "Unauthorized");
        }
    }
    let streaming = state.streaming.clone();
    if let Some(rest) = mounted(path, "api/live") {
        return streaming.live(state, req, rest).await;
    }
    if let Some(rest) = mounted(path, "api/vod") {
        return streaming.vod(state, req, rest).await;
    }
    if let Some(rest) = mounted(path, "api/recordings/stream") {
        return streaming.recording(state, req, rest).await;
    }
    http::not_found()
}
