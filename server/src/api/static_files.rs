//! Fichiers statiques de la build web, avec politique de cache.

use crate::http::{self, Req, Resp};
use crate::state::AppState;
use axum::body::Body;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use tokio_util::io::ReaderStream;

const NO_STORE: [(&str, &str); 3] = [
    (
        "cache-control",
        "no-store, no-cache, must-revalidate, max-age=0",
    ),
    ("pragma", "no-cache"),
    ("expires", "0"),
];

/// Sert la build web en appliquant la politique de cache :
/// - points d'entrée versionnés (`?v=<empreinte>`) servis réécrits, jamais
///   mis en cache ;
/// - `.html`, `.js`, `.json` sans cache pour que les mises à jour soient vues
///   tout de suite, sauf les libs vendorisées (hls.js/mpegts.js, ~750 Ko,
///   versions figées) ;
/// - le reste en cache un jour.
pub async fn handle(state: &AppState, req: &Req) -> Resp {
    let path = req.path.as_str();
    let key = if path.is_empty() { "index.html" } else { path };
    if req.is_get()
        && let Some(content) = state.versioned.get(key)
    {
        let content_type = if path.ends_with(".js") {
            "text/javascript; charset=utf-8"
        } else {
            "text/html; charset=utf-8"
        };
        let mut resp = http::with_headers(
            http::response(200, content.clone()),
            &[("content-type", content_type)],
        );
        for (name, value) in NO_STORE {
            http::set_header(&mut resp, name, value);
        }
        return resp;
    }

    let resp = serve_file(&state.web_path, req).await;
    let vendored = path.starts_with("vendor/");
    if !vendored
        && (path.is_empty()
            || path.ends_with(".html")
            || path.ends_with(".js")
            || path.ends_with(".json"))
    {
        return http::with_headers(resp, &NO_STORE);
    }
    http::with_headers(resp, &[("cache-control", "public, max-age=86400")])
}

/// Chemin disque de la requête, ou `None` s'il sort de la racine.
fn resolve(root: &str, path: &str) -> Option<PathBuf> {
    let mut resolved = PathBuf::from(root);
    for segment in path.split('/').filter(|s| !s.is_empty()) {
        let decoded = percent_encoding::percent_decode_str(segment)
            .decode_utf8()
            .ok()?;
        if decoded == "." || decoded == ".." || decoded.contains(['/', '\\', ':', '\0']) {
            return None;
        }
        resolved.push(decoded.as_ref());
    }
    Some(resolved)
}

fn http_date(time: SystemTime) -> String {
    let dt: chrono::DateTime<chrono::Utc> = time.into();
    dt.format("%a, %d %b %Y %H:%M:%S GMT").to_string()
}

async fn serve_file(root: &str, req: &Req) -> Resp {
    if !req.is_get() {
        return http::text(405, "Method Not Allowed");
    }
    let Some(mut file_path) = resolve(root, &req.path) else {
        return http::not_found();
    };
    if file_path.is_dir() {
        // Répertoire sans `/` final : redirection, comme shelf_static.
        if !req.path.is_empty() && !req.path.ends_with('/') {
            let index = file_path.join("index.html");
            if index.is_file() {
                let mut resp = http::empty(301);
                http::set_header(&mut resp, "location", &format!("/{}/", req.path));
                return resp;
            }
            return http::not_found();
        }
        file_path = file_path.join("index.html");
    }
    let Ok(meta) = tokio::fs::metadata(&file_path).await else {
        return http::not_found();
    };
    if !meta.is_file() {
        return http::not_found();
    }

    let modified = meta.modified().ok();
    if let (Some(modified), Some(since)) = (modified, req.header("if-modified-since"))
        && let Ok(since) = chrono::DateTime::parse_from_rfc2822(since)
    {
        let modified: chrono::DateTime<chrono::Utc> = modified.into();
        if modified.timestamp() <= since.timestamp() {
            return http::empty(304);
        }
    }

    let content_type = content_type_of(&file_path);
    let body = if req.method == axum::http::Method::HEAD {
        Body::empty()
    } else {
        match tokio::fs::File::open(&file_path).await {
            Ok(file) => Body::from_stream(ReaderStream::new(file)),
            Err(_) => return http::not_found(),
        }
    };
    let mut resp = http::response(200, body);
    http::set_header(&mut resp, "content-length", &meta.len().to_string());
    if let Some(ct) = content_type {
        http::set_header(&mut resp, "content-type", &ct);
    }
    if let Some(modified) = modified {
        http::set_header(&mut resp, "last-modified", &http_date(modified));
    }
    resp
}

fn content_type_of(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?.to_lowercase();
    Some(match ext.as_str() {
        "js" | "mjs" => "text/javascript".to_string(),
        "html" | "htm" => "text/html".to_string(),
        "wasm" => "application/wasm".to_string(),
        _ => mime_guess::from_ext(&ext).first_raw()?.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuse_la_traversee() {
        assert!(resolve("/app/web", "../etc/passwd").is_none());
        assert!(resolve("/app/web", "a/%2e%2e/b").is_none());
        assert!(resolve("/app/web", "a/..%2Fb").is_none());
        assert_eq!(
            resolve("/app/web", "vendor/hls.min.js").unwrap(),
            PathBuf::from("/app/web").join("vendor").join("hls.min.js")
        );
    }
}
