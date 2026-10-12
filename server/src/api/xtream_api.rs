//! Passerelle authentifiée vers `player_api.php` du panneau Xtream.
//!
//! Le front ne voit jamais les identifiants Xtream : il appelle
//! `GET /api/xtream-api?action=...` avec son jeton de session et le serveur
//! injecte username/password de la playlist de l'utilisateur.

use crate::http::{self, Req, Resp};
use crate::state::AppState;
use crate::util::log_redactor::redact_url;
use axum::body::Body;
use futures::TryStreamExt;
use serde_json::json;
use std::time::Duration;

/// Paramètres que le client peut transmettre à Xtream.
const ALLOWED_PARAMS: [&str; 7] = [
    "action",
    "category_id",
    "stream_id",
    "series_id",
    "vod_id",
    "limit",
    "type",
];

pub async fn handle(state: &AppState, req: &Req) -> Resp {
    let Some(playlist) = state.get_playlist(req) else {
        return http::json(403, &json!({"error": "No playlist configured"}));
    };

    let Ok(mut target) = reqwest::Url::parse(&format!("{}/player_api.php", playlist.dns)) else {
        return http::json(500, &json!({"error": "Upstream Xtream API error"}));
    };
    {
        let mut pairs = target.query_pairs_mut();
        pairs.clear();
        pairs.append_pair("username", &playlist.username);
        pairs.append_pair("password", &playlist.password);
        // Ordre et dédoublonnage de la query cliente, comme `queryParameters`.
        let mut seen = Vec::new();
        for (key, _) in url::form_urlencoded::parse(req.query.as_bytes()) {
            if ALLOWED_PARAMS.contains(&key.as_ref()) && !seen.contains(&key) {
                seen.push(key);
            }
        }
        let params = req.query_params();
        for key in seen {
            if let Some(value) = params.get(key.as_ref()) {
                pairs.append_pair(&key, value);
            }
        }
    }

    let send = state
        .http
        .get(target.clone())
        .header("User-Agent", "VLC/3.0.18 LibVLC/3.0.18")
        .header("Accept", "*/*")
        .send();
    let response = match tokio::time::timeout(Duration::from_secs(90), send).await {
        Ok(Ok(r)) => r,
        Ok(Err(e)) => return upstream_error(&target, &format!("{e:?}")),
        Err(_) => return upstream_error(&target, "TimeoutException after 0:01:30.000000"),
    };
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/json")
        .to_string();
    let status = response.status().as_u16();
    http::with_headers(
        http::response(
            status,
            Body::from_stream(response.bytes_stream().map_err(std::io::Error::other)),
        ),
        &[
            ("content-type", &content_type),
            ("cache-control", "no-store"),
        ],
    )
}

fn upstream_error(target: &reqwest::Url, error: &str) -> Resp {
    println!(
        "[XtreamApi] Error forwarding to {}: {}",
        redact_url(target.as_str()),
        redact_url(error)
    );
    http::json(500, &json!({"error": "Upstream Xtream API error"}))
}
