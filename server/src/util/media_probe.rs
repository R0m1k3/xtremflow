//! Inspection des fichiers média locaux (enregistrements) via ffprobe.
//!
//! Les résultats sont mémorisés tant que le fichier ne change pas : une
//! liste d'enregistrements est rafraîchie toutes les 5 s pendant une capture,
//! et la playlist de lecture est rechargée en continu — sans cache, ffprobe
//! tournerait en boucle.

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::UNIX_EPOCH;

struct CacheEntry {
    size: u64,
    mtime_ms: u128,
    value: String,
}

static CACHE: LazyLock<Mutex<HashMap<String, CacheEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Binaire ffprobe : l'image Docker l'installe dans `/usr/local/bin`
/// à côté de FFmpeg ; `FFPROBE_PATH` permet de le surcharger.
pub fn ffprobe_path() -> String {
    if let Ok(path) = std::env::var("FFPROBE_PATH")
        && !path.is_empty()
    {
        return path;
    }
    if cfg!(target_os = "linux") && std::path::Path::new("/usr/local/bin/ffprobe").exists() {
        return "/usr/local/bin/ffprobe".to_string();
    }
    "ffprobe".to_string()
}

/// Durée du média en secondes, ou `None` si elle n'est pas mesurable.
pub async fn duration(path: &str) -> Option<f64> {
    let value = probe(path, "duration", &["-show_entries", "format=duration"]).await?;
    let seconds: f64 = value.parse().ok()?;
    (seconds.is_finite() && seconds > 0.0).then_some(seconds)
}

/// Codec de la première piste vidéo (`h264`, `hevc`, `mpeg2video`…).
pub async fn video_codec(path: &str) -> Option<String> {
    let value = probe(
        path,
        "videoCodec",
        &[
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=codec_name",
        ],
    )
    .await?;
    (!value.is_empty()).then(|| value.to_lowercase())
}

fn stat(path: &str) -> Option<(u64, u128)> {
    let meta = std::fs::metadata(path).ok()?;
    let mtime = meta
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_millis();
    Some((meta.len(), mtime))
}

/// Exécute ffprobe une fois par (fichier, champ) et mémorise le résultat
/// tant que taille et date de modification sont inchangées.
async fn probe(path: &str, field: &str, args: &[&str]) -> Option<String> {
    let (size, mtime_ms) = stat(path)?;
    let key = format!("{field}@{path}");
    {
        let cache = CACHE.lock().unwrap();
        if let Some(entry) = cache.get(&key)
            && entry.size == size
            && entry.mtime_ms == mtime_ms
        {
            return Some(entry.value.clone());
        }
    }

    let output = tokio::process::Command::new(ffprobe_path())
        .args(["-v", "error"])
        .args(args)
        .args(["-of", "default=noprint_wrappers=1:nokey=1", path])
        .stdin(std::process::Stdio::null())
        .output()
        .await
        .ok()?;
    // ffprobe imprime une ligne par flux : seule la première nous intéresse.
    let stdout = String::from_utf8_lossy(&output.stdout);
    let first = stdout
        .trim()
        .split('\n')
        .next()
        .unwrap_or("")
        .trim()
        .to_string();
    if first.is_empty() || first == "N/A" {
        return None;
    }
    CACHE.lock().unwrap().insert(
        key,
        CacheEntry {
            size,
            mtime_ms,
            value: first.clone(),
        },
    );
    Some(first)
}
