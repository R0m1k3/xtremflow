//! `GET /api/logo?src=<stream_icon>&name=<nom de chaîne>`
//!
//! Logo d'une chaîne, avec repli. L'URL du panneau est tentée d'abord, via
//! le proxy Xtream (mêmes protections anti-SSRF, même mémoire des hôtes
//! morts). En cas d'échec, le logo est cherché par nom dans le dépôt public
//! `tv-logos`.
//!
//! POURQUOI : quand l'hébergeur de picons du revendeur tombe, toute la grille
//! perd ses logos d'un coup, alors que les autres applications IPTV les
//! affichent encore grâce à leurs propres sources de repli.

use crate::api::proxy::missing_image_response;
use crate::http::{self, Req, Resp};
use crate::state::AppState;
use axum::http::{HeaderMap, Method};

/// Un logo trouvé change rarement : un jour de cache navigateur.
const FOUND: &str = "public, max-age=86400";

pub async fn handle(state: &AppState, req: &Req) -> Resp {
    let params = req.query_params();
    let src = params.get("src").cloned().unwrap_or_default();
    let name = params.get("name").cloned().unwrap_or_default();

    if src.starts_with("http://") || src.starts_with("https://") {
        let (path, query) = match src.split_once('?') {
            Some((p, q)) => (p, q),
            None => (src.as_str(), ""),
        };
        let path = path.split('#').next().unwrap_or("");
        let query = query.split('#').next().unwrap_or("");
        // Requête interne vers le proxy, avec la seule session du client.
        let mut headers = HeaderMap::new();
        for header in ["cookie", "authorization"] {
            if let Some(value) = req.headers.get(header) {
                headers.insert(header, value.clone());
            }
        }
        let proxied = Req {
            method: Method::GET,
            path: format!("api/xtream/{path}"),
            query: query.to_string(),
            headers,
            body: Default::default(),
            remote: req.remote,
            user: None,
            user_id: None,
        };
        let upstream = state.proxy.handle(state, &proxied).await;
        let content_type = upstream
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();
        if upstream.status().as_u16() == 200 && content_type.starts_with("image/") {
            return http::with_headers(
                http::response(200, upstream.into_body()),
                &[("content-type", &content_type), ("cache-control", FOUND)],
            );
        }
        // Réponse abandonnée : la connexion amont est refermée.
        drop(upstream);
    }

    if !name.is_empty()
        && let Some(bytes) = state.logo_catalog.logo_for(&name).await
    {
        return http::with_headers(
            http::response(200, bytes),
            &[("content-type", "image/png"), ("cache-control", FOUND)],
        );
    }
    missing_image_response()
}
