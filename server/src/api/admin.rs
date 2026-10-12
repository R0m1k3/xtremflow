//! `/api/admin` : purge des temporaires et diagnostic du délai de zap.

use crate::http::{self, Req, Resp, json_as_text, segments};
use crate::models::PlaylistConfig;
use crate::state::SharedState;
use serde_json::{Value, json};
use std::time::{Duration, Instant};

pub async fn admin(state: &SharedState, req: &Req, rest: &str) -> Resp {
    match (req.method.as_str(), segments(rest).as_slice()) {
        ("POST", ["purge"]) => {
            if !req.user.as_ref().is_some_and(|u| u.is_admin) {
                return json_as_text(403, &json!({"error": "Admin access required"}));
            }
            http::json(200, &state.cleanup.run_cleanup().await)
        }
        ("GET" | "HEAD", ["upstream-probe"]) => {
            if !req.user.as_ref().is_some_and(|u| u.is_admin) {
                return json_as_text(403, &json!({"error": "Admin access required"}));
            }
            let stream = req.query_param("stream").unwrap_or_default();
            if stream.is_empty() || !stream.bytes().all(|b| b.is_ascii_digit()) {
                return http::text(400, "stream=<id numérique> requis");
            }
            let Some(playlist) = state.get_playlist(req) else {
                return http::text(403, "No playlist");
            };
            http::json(
                200,
                &probe_upstream(&state.http_manual, &playlist, &stream).await,
            )
        }
        _ => http::not_found(),
    }
}

/// Diagnostic admin : chronomètre l'ouverture d'une chaîne chez le
/// fournisseur, en `.ts` et en `.m3u8`.
///
/// POURQUOI : ~4,3 s des ~4,6 s d'un zap se passent avant le premier octet
/// du panneau (mesuré en prod). Reste à savoir lequel des deux formats
/// démarre le plus vite, et où part le temps. Les identifiants n'apparaissent
/// jamais dans la réponse : seuls l'hôte et les durées sont rendus.
///
/// [client] ne doit PAS suivre les redirections (chaque saut est chronométré).
pub async fn probe_upstream(
    client: &reqwest::Client,
    playlist: &PlaylistConfig,
    stream_id: &str,
) -> Value {
    let base = format!(
        "{}/live/{}/{}/{stream_id}",
        playlist.dns, playlist.username, playlist.password
    );
    let ts = match reqwest::Url::parse(&format!("{base}.ts")) {
        Ok(url) => probe_stream(client, url).await,
        Err(_) => json!({"error": "FormatException", "afterMs": 0}),
    };
    // Laisser le panneau libérer la connexion (comptes à une connexion).
    tokio::time::sleep(Duration::from_secs(2)).await;
    let hls = match reqwest::Url::parse(&format!("{base}.m3u8")) {
        Ok(url) => probe_hls(client, url).await,
        Err(_) => json!({"error": "FormatException", "afterMs": 0}),
    };
    json!({"stream": stream_id, "ts": ts, "m3u8": hls})
}

/// Suit les redirections à la main pour chronométrer chaque saut.
async fn open(
    client: &reqwest::Client,
    url: reqwest::Url,
    started: Instant,
) -> Result<(Option<reqwest::Response>, Vec<Value>, reqwest::Url), String> {
    let mut hops = Vec::new();
    let mut current = url;
    for _ in 0..5 {
        let send = client
            .get(current.clone())
            .header("User-Agent", "VLC/3.0.18 LibVLC/3.0.18")
            .send();
        let response = tokio::time::timeout(Duration::from_secs(20), send)
            .await
            .map_err(|_| "TimeoutException".to_string())?
            .map_err(|_| "ClientException".to_string())?;
        let status = response.status().as_u16();
        hops.push(json!({
            "host": current.host_str().unwrap_or(""),
            "status": status,
            "headersMs": started.elapsed().as_millis() as u64,
        }));
        let location = response
            .headers()
            .get("location")
            .and_then(|v| v.to_str().ok())
            .map(str::to_string);
        if let (true, Some(location)) = ([301, 302, 303, 307, 308].contains(&status), location) {
            drop(response);
            current = current
                .join(&location)
                .map_err(|_| "FormatException".to_string())?;
            continue;
        }
        return Ok((Some(response), hops, current));
    }
    Ok((None, hops, current))
}

fn status_error(response: Option<&reqwest::Response>) -> String {
    match response {
        Some(r) => format!("status {}", r.status().as_u16()),
        None => "status null".to_string(),
    }
}

async fn probe_stream(client: &reqwest::Client, url: reqwest::Url) -> Value {
    let started = Instant::now();
    let (response, hops, _) = match open(client, url, started).await {
        Ok(r) => r,
        Err(e) => return json!({"error": e, "afterMs": started.elapsed().as_millis() as u64}),
    };
    let mut response = match response {
        Some(r) if r.status().as_u16() == 200 => r,
        other => return json!({"hops": hops, "error": status_error(other.as_ref())}),
    };
    let mut bytes = 0usize;
    let mut first_byte_ms: Option<u64> = None;
    // 1 Mo suffit à voir le premier envoi (préchargement du panneau).
    let read = async {
        while let Ok(Some(chunk)) = response.chunk().await {
            first_byte_ms.get_or_insert(started.elapsed().as_millis() as u64);
            bytes += chunk.len();
            if bytes > 1_000_000 {
                break;
            }
        }
    };
    let _ = tokio::time::timeout(Duration::from_secs(15), read).await;
    json!({
        "hops": hops,
        "firstByteMs": first_byte_ms,
        "firstMegabyteMs": (bytes > 1_000_000).then(|| started.elapsed().as_millis() as u64),
    })
}

async fn probe_hls(client: &reqwest::Client, url: reqwest::Url) -> Value {
    let started = Instant::now();
    let (response, hops, final_url) = match open(client, url, started).await {
        Ok(r) => r,
        Err(e) => return json!({"error": e, "afterMs": started.elapsed().as_millis() as u64}),
    };
    let response = match response {
        Some(r) if r.status().as_u16() == 200 => r,
        other => return json!({"hops": hops, "error": status_error(other.as_ref())}),
    };
    let body = match response.text().await {
        Ok(b) => b,
        Err(_) => {
            return json!({"error": "ClientException", "afterMs": started.elapsed().as_millis() as u64});
        }
    };
    let playlist_ms = started.elapsed().as_millis() as u64;
    let lines: Vec<&str> = body.lines().collect();
    let segments: Vec<&str> = lines
        .iter()
        .copied()
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .collect();
    let target = lines
        .iter()
        .find(|l| l.starts_with("#EXT-X-TARGETDURATION"))
        .map(|l| l.rsplit(':').next().unwrap_or("").to_string())
        .unwrap_or_default();
    if segments.is_empty() {
        return json!({"hops": hops, "playlistMs": playlist_ms, "segments": 0});
    }
    // Un lecteur démarre près du direct : chronométrer l'avant-dernier.
    let pick = if segments.len() >= 2 {
        segments[segments.len() - 2]
    } else {
        segments[segments.len() - 1]
    };
    let segment = match final_url.join(pick) {
        Ok(url) => Box::pin(probe_stream(client, url)).await,
        Err(_) => json!({"error": "FormatException"}),
    };
    json!({
        "hops": hops,
        "playlistMs": playlist_ms,
        "segments": segments.len(),
        "targetDuration": target,
        "segment": segment,
        "segmentStartedAtMs": playlist_ms,
    })
}
