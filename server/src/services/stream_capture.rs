//! Capture brute d'un flux MPEG-TS dans un fichier `.ts`.
//!
//! POURQUOI : FFmpeg écrivait le direct en MKV (`-c copy`) et chaque
//! coupure amont produisait une nouvelle partie, recollée à la fin. Les
//! sauts d'horloge des flux IPTV (« timestamp discontinuity ») cassaient la
//! chronologie du MKV et le recollage : Plex et Jellyfin voyaient un fichier
//! qui « finissait » avant le match. Comme un magnétoscope (Plex DVR,
//! Tvheadend), on recopie désormais les octets du flux tels quels dans un
//! seul `.ts`, complété à chaque reconnexion et même après un redémarrage
//! du serveur ; le passage en MKV se fait une seule fois, en fin de capture,
//! où FFmpeg absorbe les discontinuités de tout le fichier d'un coup.

use crate::util::log_redactor::redact_url;
use crate::util::process::ManagedChild;
use bytes::Bytes;
use futures::stream::BoxStream;
use futures::{Stream, StreamExt};
use std::future::Future;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWrite, AsyncWriteExt};

/// Sans un octet pendant ce délai, la connexion est jugée morte.
pub const STALL_TIMEOUT: Duration = Duration::from_secs(30);

/// Flux d'octets d'une source ; l'erreur est déjà lisible (sans identifiants).
pub type ByteStream = BoxStream<'static, Result<Bytes, String>>;

/// Ligne de diagnostic à verser au log de l'enregistrement.
pub type LogSink = Arc<dyn Fn(&str) + Send + Sync>;

/// Une source HLS ne se recopie pas octet par octet : FFmpeg la réassemble.
pub fn needs_ffmpeg(url: &str) -> bool {
    let path = url
        .split(['?', '#'])
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    !(url.starts_with("http://") || url.starts_with("https://")) || path.ends_with(".m3u8")
}

/// Ouvre la source : lecture HTTP directe, ou FFmpeg vers MPEG-TS pour HLS
/// et les protocoles non HTTP.
pub async fn open(
    http: &reqwest::Client,
    url: &str,
    ffmpeg: &str,
    log: LogSink,
) -> Result<ByteStream, String> {
    if needs_ffmpeg(url) {
        return open_ffmpeg(url, ffmpeg, log);
    }
    let response = http
        .get(url)
        .header("User-Agent", "VLC/3.0.18 LibVLC/3.0.18")
        .header("Accept", "*/*")
        .send()
        .await
        .map_err(|e| redact_url(&format!("connexion impossible : {e}")))?;
    let status = response.status().as_u16();
    if status != 200 {
        return Err(format!("flux refusé (HTTP {status})"));
    }
    Ok(response
        .bytes_stream()
        .map(|chunk| chunk.map_err(|e| redact_url(&format!("lecture interrompue : {e}"))))
        .boxed())
}

/// Coupe FFmpeg quand le flux qui le lit est abandonné.
struct KillOnDrop(ManagedChild);

impl Drop for KillOnDrop {
    fn drop(&mut self) {
        self.0.kill();
    }
}

fn open_ffmpeg(url: &str, ffmpeg: &str, log: LogSink) -> Result<ByteStream, String> {
    let mut child = tokio::process::Command::new(ffmpeg)
        .args([
            "-hide_banner",
            "-nostats",
            "-loglevel",
            "warning",
            "-user_agent",
            "VLC/3.0.18 LibVLC/3.0.18",
            "-rw_timeout",
            "30000000",
            "-i",
            url,
            "-map",
            "0",
            "-c",
            "copy",
            "-f",
            "mpegts",
            "pipe:1",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| redact_url(&format!("FFmpeg impossible à lancer : {e}")))?;
    let stdout = child.stdout.take().ok_or("sortie de FFmpeg indisponible")?;
    if let Some(mut stderr) = child.stderr.take() {
        tokio::spawn(async move {
            let mut text = String::new();
            let _ = stderr.read_to_string(&mut text).await;
            for line in text.lines().filter(|l| !l.trim().is_empty()) {
                log(&redact_url(line));
            }
        });
    }
    let guard = KillOnDrop(ManagedChild::spawn(child));
    Ok(tokio_util::io::ReaderStream::new(stdout)
        .map(move |chunk| {
            let _ = &guard;
            chunk.map_err(|e| format!("lecture de FFmpeg interrompue : {e}"))
        })
        .boxed())
}

/// Fin d'une connexion.
#[derive(Debug, PartialEq)]
pub enum PumpEnd {
    /// Arrêt demandé ou fin de la fenêtre.
    Stop,
    /// Coupure : il faut se reconnecter.
    Cut(String),
}

/// Recopie [stream] dans [out] jusqu'à [stop], une coupure ou un silence de
/// [stall]. [bytes] compte ce qui a été écrit, même en cas de coupure.
pub async fn pump<S, W, F>(
    mut stream: S,
    out: &mut W,
    stall: Duration,
    bytes: &mut u64,
    stop: &mut std::pin::Pin<&mut F>,
) -> PumpEnd
where
    S: Stream<Item = Result<Bytes, String>> + Unpin,
    W: AsyncWrite + Unpin,
    F: Future<Output = ()>,
{
    loop {
        let next = tokio::select! {
            biased;
            _ = stop.as_mut() => return PumpEnd::Stop,
            next = tokio::time::timeout(stall, stream.next()) => next,
        };
        match next {
            Err(_) => return PumpEnd::Cut(format!("aucune donnée depuis {} s", stall.as_secs())),
            Ok(None) => return PumpEnd::Cut("fin du flux".into()),
            Ok(Some(Err(e))) => return PumpEnd::Cut(e),
            Ok(Some(Ok(chunk))) => {
                if let Err(e) = out.write_all(&chunk).await {
                    return PumpEnd::Cut(format!("écriture impossible : {e}"));
                }
                *bytes += chunk.len() as u64;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chunks(parts: &[&'static [u8]]) -> Vec<Result<Bytes, String>> {
        parts.iter().map(|p| Ok(Bytes::from_static(p))).collect()
    }

    #[test]
    fn sources_qui_passent_par_ffmpeg() {
        assert!(!needs_ffmpeg(
            "http://127.0.0.1:8089/api/live/1.ts?playlist=x"
        ));
        assert!(!needs_ffmpeg("https://panel.example/live/u/p/1.ts"));
        assert!(needs_ffmpeg("https://cdn.example/live/index.M3U8?token=a"));
        assert!(needs_ffmpeg("rtmp://example/live"));
    }

    #[tokio::test]
    async fn recopie_jusqu_a_la_fin_du_flux() {
        let stream = futures::stream::iter(chunks(&[b"abc", b"def"]));
        let mut out = Vec::new();
        let mut bytes = 0;
        let stop = std::future::pending::<()>();
        tokio::pin!(stop);
        let end = pump(stream, &mut out, STALL_TIMEOUT, &mut bytes, &mut stop).await;
        assert_eq!(end, PumpEnd::Cut("fin du flux".into()));
        assert_eq!(out, b"abcdef");
        assert_eq!(bytes, 6);
    }

    #[tokio::test]
    async fn erreur_apres_des_donnees() {
        let mut items = chunks(&[b"abc"]);
        items.push(Err("lecture interrompue".into()));
        let mut out = Vec::new();
        let mut bytes = 0;
        let stop = std::future::pending::<()>();
        tokio::pin!(stop);
        let end = pump(
            futures::stream::iter(items),
            &mut out,
            STALL_TIMEOUT,
            &mut bytes,
            &mut stop,
        )
        .await;
        assert_eq!(end, PumpEnd::Cut("lecture interrompue".into()));
        assert_eq!(bytes, 3);
    }

    #[tokio::test]
    async fn silence_detecte() {
        let stream = futures::stream::pending::<Result<Bytes, String>>();
        let mut out = Vec::new();
        let mut bytes = 0;
        let stop = std::future::pending::<()>();
        tokio::pin!(stop);
        let end = pump(
            stream,
            &mut out,
            Duration::from_millis(50),
            &mut bytes,
            &mut stop,
        )
        .await;
        assert_eq!(end, PumpEnd::Cut("aucune donnée depuis 0 s".into()));
    }

    #[tokio::test]
    async fn arret_prioritaire() {
        let stream = futures::stream::iter(chunks(&[b"abc"]));
        let mut out = Vec::new();
        let mut bytes = 0;
        let stop = std::future::ready(());
        tokio::pin!(stop);
        let end = pump(stream, &mut out, STALL_TIMEOUT, &mut bytes, &mut stop).await;
        assert_eq!(end, PumpEnd::Stop);
        assert!(out.is_empty());
    }
}
