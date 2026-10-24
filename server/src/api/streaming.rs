//! Streaming : direct (HLS transcodé, `turbo.ts`, proxy `.ts` brut), films
//! et séries (HLS), lecture des enregistrements (HLS par offset).

use crate::api::recording_playlist::{
    parse_recording_offset_key, parse_recording_start, recording_offset_key,
    rewrite_recording_playlist,
};
use crate::http::{self, Req, Resp, segments};
use crate::models::PlaylistConfig;
use crate::services::ffmpeg_sessions::{FfmpegSession, FfmpegSessionManager};
use crate::services::gpu_fallback::{GpuHealth, is_gpu_failure};
use crate::services::upstream_slots::{AccountLimits, UpstreamSlots, account_key_of};
use crate::state::AppState;
use crate::util::log_redactor::redact_url;
use crate::util::media_probe;
use crate::util::process::ManagedChild;
use axum::body::Body;
use bytes::Bytes;
use futures::StreamExt;
use regex::Regex;
use std::path::Path;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio_util::io::ReaderStream;

/// Délai sans consommation au-delà duquel un flux est tenu pour orphelin.
///
/// Un lecteur HLS redemande sa playlist toutes les 2 à 4 s ; un flux
/// `turbo.ts` reçoit au moins une rafale toutes les ~7 s même sur un panneau
/// qui livre par à-coups. 15 s laissent une marge à ces deux rythmes.
const VIEWER_GRACE: Duration = Duration::from_secs(15);

/// Reconnexions consécutives tentées avant d'abandonner un proxy `.ts`.
const LIVE_PROXY_MAX_RETRIES: u32 = 4;

const VLC_UA: &str = "VLC/3.0.18 LibVLC/3.0.18";

pub struct Streaming {
    pub sessions: Arc<FfmpegSessionManager>,
    /// Pannes GPU récentes, partagées par toutes les routes de transcodage.
    gpu_health: GpuHealth,
    /// Connexions de lecture ouvertes chez le fournisseur, par compte.
    slots: Arc<UpstreamSlots>,
    /// Quota `max_connections` de chaque compte Xtream.
    limits: AccountLimits,
    /// Numérote les flux `turbo.ts` (un FFmpeg par requête).
    turbo_counter: AtomicU64,
}

struct Attempt {
    session: Option<Arc<FfmpegSession>>,
    ready: bool,
    error: Option<String>,
}

/// Binaire FFmpeg du streaming (PATH ; exécutable portable sous Windows).
fn ffmpeg_path() -> String {
    if cfg!(windows) {
        for candidate in ["ffmpeg.exe", "bin/ffmpeg.exe", "ffmpeg/bin/ffmpeg.exe"] {
            if Path::new(candidate).exists() {
                return candidate.to_string();
            }
        }
    }
    "ffmpeg".to_string()
}

/// `source` copie la vidéo telle quelle (`-c:v copy`) : énorme gain CPU, la
/// plupart des flux Xtream étant déjà en H.264. L'audio est toujours
/// normalisé en AAC pour la compatibilité HLS.
fn sanitize_quality(quality: Option<&str>) -> &'static str {
    match quality {
        Some("source") => "source",
        Some("medium") => "medium",
        Some("low") => "low",
        _ => "high",
    }
}

static STREAM_ID: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[a-zA-Z0-9_-]+$").unwrap());
static CONTAINER_EXT: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[a-z0-9]{2,5}$").unwrap());

fn is_valid_stream_id(id: &str) -> bool {
    STREAM_ID.is_match(id)
}

/// Extension de conteneur d'un film/épisode, validée (elle finit dans l'URL
/// du panneau). `mkv` par défaut : les anciens clients sans `ext` gardent
/// leur comportement.
pub fn vod_container_extension(ext: Option<&str>) -> String {
    match ext.map(str::to_lowercase) {
        Some(v) if CONTAINER_EXT.is_match(&v) => v,
        _ => "mkv".to_string(),
    }
}

fn strings(args: &[&str]) -> Vec<String> {
    args.iter().map(|s| s.to_string()).collect()
}

/// Arguments vidéo du profil direct.
fn live_video_args(quality: &str, gpu: bool) -> Vec<String> {
    strings(match (quality, gpu) {
        ("source", _) => &["-c:v", "copy"],
        ("medium", true) => &[
            "-c:v",
            "h264_nvenc",
            "-preset",
            "p4",
            "-tune",
            "hq",
            "-b:v",
            "3000k",
            "-maxrate",
            "4500k",
            "-bufsize",
            "6000k",
            "-profile:v",
            "high",
            "-level",
            "4.0",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "50",
        ],
        ("medium", false) => &[
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-tune",
            "zerolatency",
            "-profile:v",
            "high",
            "-level",
            "4.0",
            "-b:v",
            "3000k",
            "-maxrate",
            "4500k",
            "-bufsize",
            "6000k",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "50",
        ],
        ("low", true) => &[
            "-c:v",
            "h264_nvenc",
            "-preset",
            "p4",
            "-b:v",
            "1500k",
            "-maxrate",
            "2000k",
            "-bufsize",
            "3000k",
            "-vf",
            "scale=-2:720",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "50",
        ],
        ("low", false) => &[
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-tune",
            "zerolatency",
            "-b:v",
            "1500k",
            "-maxrate",
            "2000k",
            "-bufsize",
            "3000k",
            "-vf",
            "scale=-2:720",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "50",
        ],
        (_, true) => &[
            "-c:v",
            "h264_nvenc",
            "-preset",
            "p4",
            "-tune",
            "hq",
            "-b:v",
            "8000k",
            "-maxrate",
            "12000k",
            "-bufsize",
            "16000k",
            "-profile:v",
            "high",
            "-level",
            "4.0",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "50",
        ],
        // veryfast et non medium : en direct, l'encodeur doit tenir le temps
        // réel ET produire le premier segment vite.
        (_, false) => &[
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-tune",
            "zerolatency",
            "-profile:v",
            "high",
            "-level",
            "4.0",
            "-b:v",
            "6000k",
            "-maxrate",
            "8000k",
            "-bufsize",
            "12000k",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "50",
        ],
    })
}

/// Arguments vidéo du profil film/série.
fn vod_video_args(quality: &str, gpu: bool) -> Vec<String> {
    strings(match (quality, gpu) {
        ("source", _) => &["-c:v", "copy"],
        ("medium", true) => &[
            "-c:v",
            "h264_nvenc",
            "-preset",
            "p4",
            "-tune",
            "hq",
            "-rc",
            "cbr",
            "-b:v",
            "2500k",
            "-maxrate",
            "3000k",
            "-bufsize",
            "5000k",
            "-g",
            "48",
            "-bf",
            "2",
            "-pix_fmt",
            "yuv420p",
        ],
        ("medium", false) => &[
            "-c:v", "libx264", "-preset", "fast", "-crf", "23", "-maxrate", "6000k", "-bufsize",
            "12000k", "-pix_fmt", "yuv420p", "-g", "48", "-threads", "0",
        ],
        ("low", true) => &[
            "-c:v",
            "h264_nvenc",
            "-preset",
            "p4",
            "-rc",
            "cbr",
            "-b:v",
            "1500k",
            "-maxrate",
            "2000k",
            "-bufsize",
            "3000k",
            "-vf",
            "scale=-2:720",
            "-g",
            "48",
            "-pix_fmt",
            "yuv420p",
        ],
        ("low", false) => &[
            "-c:v",
            "libx264",
            "-preset",
            "fast",
            "-crf",
            "26",
            "-maxrate",
            "3000k",
            "-bufsize",
            "6000k",
            "-vf",
            "scale=-2:720",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "48",
            "-threads",
            "0",
        ],
        (_, true) => &[
            "-c:v",
            "h264_nvenc",
            "-preset",
            "p4",
            "-tune",
            "hq",
            "-rc",
            "cbr",
            "-b:v",
            "4000k",
            "-maxrate",
            "4500k",
            "-bufsize",
            "8000k",
            "-g",
            "48",
            "-bf",
            "2",
            "-pix_fmt",
            "yuv420p",
        ],
        (_, false) => &[
            "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-maxrate", "12000k", "-bufsize",
            "24000k", "-pix_fmt", "yuv420p", "-g", "48", "-threads", "0",
        ],
    })
}

/// Audio : AAC simple en `source`, downmix + normalisation sinon.
fn audio_args(with_filters: bool) -> Vec<String> {
    let mut args = strings(&[
        "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "48000", "-af",
    ]);
    args.push(if with_filters {
        "pan=stereo|FL=1.0*FL+0.707*FC+0.5*BL+0.5*SL+0.5*LFE|FR=1.0*FR+0.707*FC+0.5*BR+0.5*SR+0.5*LFE,dynaudnorm=f=150:g=15".to_string()
    } else {
        "aresample=async=1".to_string()
    });
    args
}

/// Ajoute `?playlist=<id>` à chaque URI de segment d'un m3u8.
///
/// POURQUOI : le lecteur résout les segments relativement au m3u8 et perd
/// sa query ; sans elle, le segment serait cherché dans la session d'une
/// autre IPTV (même `stream_id`).
fn with_segment_query(m3u8: &str, playlist_id: &str) -> String {
    let enc: String = url::form_urlencoded::byte_serialize(playlist_id.as_bytes()).collect();
    m3u8.lines()
        .map(|line| {
            let t = line.trim();
            if t.is_empty() || t.starts_with('#') {
                line.to_string()
            } else if t.contains('?') {
                format!("{t}&playlist={enc}")
            } else {
                format!("{t}?playlist={enc}")
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
        + "\n"
}

/// Playlist explicitement demandée par la requête (à propager aux segments).
fn requested_playlist(req: &Req) -> Option<String> {
    req.query_param("playlist").filter(|p| !p.trim().is_empty())
}

/// Étiquette de l'IPTV servie, pour séparer les sessions de deux playlists.
fn playlist_tag(state: &AppState, req: &Req) -> String {
    state
        .get_playlist(req)
        .map(|p| p.tag())
        .unwrap_or_else(|| "default".into())
}

/// `?playlist=…` à recopier dans une redirection.
fn playlist_suffix(req: &Req, first: bool) -> String {
    match requested_playlist(req) {
        Some(p) => {
            let enc: String = url::form_urlencoded::byte_serialize(p.as_bytes()).collect();
            format!("{}playlist={enc}", if first { '?' } else { '&' })
        }
        None => String::new(),
    }
}

fn hls_headers(resp: Resp) -> Resp {
    http::with_headers(
        resp,
        &[
            ("content-type", "application/vnd.apple.mpegurl"),
            ("cache-control", "no-cache"),
            ("x-content-type-options", "nosniff"),
        ],
    )
}

/// Sert un segment `.ts` d'une session (404 s'il n'existe pas/plus).
async fn serve_segment(path: &Path, max_age: u32) -> Resp {
    match tokio::fs::File::open(path).await {
        Ok(file) => http::with_headers(
            http::response(200, Body::from_stream(ReaderStream::new(file))),
            &[
                ("content-type", "video/mp2t"),
                ("cache-control", &format!("max-age={max_age}")),
            ],
        ),
        Err(_) => http::text(404, "Segment not found"),
    }
}

/// Termine FFmpeg quand le corps de réponse est abandonné (client parti).
struct TerminateOnDrop(ManagedChild);

impl Drop for TerminateOnDrop {
    fn drop(&mut self) {
        self.0.terminate();
    }
}

impl Streaming {
    pub fn new(sessions: Arc<FfmpegSessionManager>, panel_client: reqwest::Client) -> Self {
        Self {
            sessions,
            gpu_health: GpuHealth::default(),
            slots: Arc::new(UpstreamSlots::new()),
            limits: AccountLimits::from_panel(panel_client),
            turbo_counter: AtomicU64::new(0),
        }
    }

    /// Fait de la place chez le fournisseur avant d'ouvrir la connexion [id].
    async fn claim_upstream(&self, playlist: &PlaylistConfig, id: &str) {
        let max = self.limits.max_for(playlist);
        let freed = self.slots.make_room(&account_key_of(playlist), max, id);
        if freed.is_empty() {
            return;
        }
        println!(
            "[Upstream] {id} : {} coupé(s) (quota fournisseur : {max} connexion(s))",
            freed.join(", ")
        );
        // Laisser le panneau constater la fermeture : rouvrir aussitôt se
        // fait refuser sur les comptes à une seule connexion.
        tokio::time::sleep(Duration::from_secs(1)).await;
    }

    /// Inscrit [child] comme connexion amont de [playlist] tant qu'il vit.
    fn register_upstream(
        &self,
        playlist: &PlaylistConfig,
        id: &str,
        child: ManagedChild,
        release: Box<dyn Fn() + Send + Sync>,
        idle_for: Box<dyn Fn() -> Duration + Send + Sync>,
    ) {
        let token = self.slots.register(
            id,
            &account_key_of(playlist),
            release,
            Some(Box::new(move || idle_for() < VIEWER_GRACE)),
        );
        let slots = self.slots.clone();
        let id = id.to_string();
        tokio::spawn(async move {
            child.wait().await;
            slots.unregister(&id, Some(token));
        });
    }

    /// Démarre (ou récupère) la session [id] et attend sa playlist.
    /// [upstream] : playlist dont la session ouvre une connexion chez le
    /// fournisseur (direct, film) ; `None` pour un enregistrement sur disque.
    async fn run_session(
        &self,
        id: &str,
        is_live: bool,
        args: &[String],
        min_segments: usize,
        upstream: Option<&PlaylistConfig>,
    ) -> Attempt {
        let starting = self.sessions.needs_start(id, is_live);
        if let (Some(playlist), true) = (upstream, starting) {
            self.claim_upstream(playlist, id).await;
        }
        let session = match self
            .sessions
            .get_or_start(id, is_live, &ffmpeg_path(), args)
        {
            Ok(s) => s,
            // Serveur à court de processus/mémoire : échec ordinaire, pas un 500.
            Err(e) => {
                return Attempt {
                    session: None,
                    ready: false,
                    error: Some(format!("FFmpeg start failed: {e}")),
                };
            }
        };
        if let (Some(playlist), true) = (upstream, starting) {
            let sessions = self.sessions.clone();
            let release_id = id.to_string();
            let watched = session.clone();
            self.register_upstream(
                playlist,
                id,
                session.child.clone(),
                Box::new(move || sessions.kill_session(&release_id)),
                // Touchée à chaque requête de playlist ou de segment.
                Box::new(move || watched.idle_for()),
            );
        }
        let (ready, error) = self
            .sessions
            .wait_for_playlist(&session, min_segments)
            .await;
        Attempt {
            session: Some(session),
            ready,
            error,
        }
    }

    /// Comme [run_session], avec repli CPU si l'encodage GPU échoue. Le repli
    /// garde le même identifiant : le lecteur ne s'aperçoit de rien.
    async fn run_with_gpu_fallback(
        &self,
        id: &str,
        is_live: bool,
        want_gpu: bool,
        build_args: impl Fn(bool) -> Vec<String>,
        min_segments: usize,
        upstream: Option<&PlaylistConfig>,
    ) -> Attempt {
        let gpu = want_gpu && self.gpu_health.available();
        let mut attempt = self
            .run_session(id, is_live, &build_args(gpu), min_segments, upstream)
            .await;
        if !attempt.ready && gpu && is_gpu_failure(attempt.error.as_deref()) {
            self.gpu_health.mark_failed();
            println!(
                "[GPU] {id} : encodage GPU refusé ({}) — repli sur le CPU",
                redact_url(attempt.error.as_deref().unwrap_or(""))
            );
            self.sessions.kill_session(id);
            attempt = self
                .run_session(id, is_live, &build_args(false), min_segments, upstream)
                .await;
        }
        attempt
    }

    async fn serve_session_playlist(
        &self,
        id: &str,
        attempt: Attempt,
        label: &str,
        playlist_query: Option<&str>,
    ) -> Resp {
        let session = match attempt.session {
            Some(s) if attempt.ready => s,
            _ => {
                self.sessions.kill_session(id);
                // stderr de FFmpeg : peut recopier l'URL amont, identifiants
                // compris — masqué avant d'être rendu au client.
                return http::text(
                    502,
                    format!(
                        "{label} transcoder failed: {}",
                        redact_url(attempt.error.as_deref().unwrap_or("null"))
                    ),
                );
            }
        };
        session.touch();
        match tokio::fs::read(session.playlist_path()).await {
            Ok(bytes) => {
                let body = match playlist_query {
                    Some(q) => with_segment_query(&String::from_utf8_lossy(&bytes), q).into_bytes(),
                    None => bytes,
                };
                hls_headers(http::response(200, body))
            }
            Err(_) => http::text(502, format!("{label} transcoder failed: playlist missing")),
        }
    }

    // ==========================================
    // 1. DIRECT
    // ==========================================

    pub async fn live(&self, state: &AppState, req: &Req, rest: &str) -> Resp {
        if !req.is_get() {
            return http::not_found();
        }
        match segments(rest).as_slice() {
            [id, quality, "playlist.m3u8"] => {
                self.live_playlist(state, req, id, sanitize_quality(Some(quality)))
                    .await
            }
            // Ancienne route (?quality=…) : redirection pour que les URL
            // relatives des segments se résolvent sous le chemin de qualité.
            [id, "playlist.m3u8"] => {
                let quality = sanitize_quality(req.query_param("quality").as_deref());
                http::redirect(&format!(
                    "/api/live/{id}/{quality}/playlist.m3u8{}",
                    playlist_suffix(req, true)
                ))
            }
            [id, "turbo.ts"] => self.turbo(state, req, id).await,
            [file] if file.len() > 3 && file.ends_with(".ts") => {
                self.direct_proxy(state, req, &file[..file.len() - 3]).await
            }
            [id, quality, segment] => {
                if !is_valid_stream_id(id) || segment.contains("..") {
                    return http::text(400, "Invalid request");
                }
                let session_id = format!(
                    "live_{}_{id}_{}",
                    playlist_tag(state, req),
                    sanitize_quality(Some(quality))
                );
                self.sessions.touch(&session_id);
                serve_segment(&self.sessions.base_dir.join(&session_id).join(segment), 60).await
            }
            _ => http::not_found(),
        }
    }

    async fn live_playlist(
        &self,
        state: &AppState,
        req: &Req,
        stream_id: &str,
        quality: &str,
    ) -> Resp {
        if !is_valid_stream_id(stream_id) {
            return http::text(400, "Invalid stream ID");
        }
        let Some(playlist) = state.get_playlist(req) else {
            return http::text(403, "No playlist");
        };
        let target = format!(
            "{}/live/{}/{}/{stream_id}.ts",
            playlist.dns, playlist.username, playlist.password
        );
        let use_gpu = state.db.is_nvidia_gpu_enabled();
        let session_id = format!("live_{}_{stream_id}_{quality}", playlist.tag());
        if !self.sessions.contains(&session_id) {
            println!("[Live HLS] Starting {session_id}: {}", redact_url(&target));
        }

        let build = |gpu: bool| {
            let mut args = strings(&["-hide_banner", "-loglevel", "warning"]);
            if gpu {
                args.extend(strings(&["-hwaccel", "cuda"]));
            }
            args.extend(strings(&[
                "-headers",
                "User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n",
                "-reconnect",
                "1",
                "-reconnect_streamed",
                "1",
                "-reconnect_at_eof",
                "1",
                "-reconnect_delay_max",
                "10",
                // Lecture bloquée 30 s → reconnexion plutôt que blocage éternel.
                "-rw_timeout",
                "30000000",
                // Démarrage rapide : sans borne, FFmpeg sonde plusieurs secondes.
                "-fflags",
                "nobuffer",
                "-probesize",
                "1000000",
                "-analyzeduration",
                "1000000",
                "-i",
            ]));
            args.push(target.clone());
            args.extend(live_video_args(quality, gpu));
            args.extend(audio_args(false));
            // Fenêtre glissante 10 × 2 s ; premier segment clos après ~1 s.
            args.extend(strings(&[
                "-f",
                "hls",
                "-hls_init_time",
                "1",
                "-hls_time",
                "2",
                "-hls_list_size",
                "10",
                "-hls_flags",
                "delete_segments+independent_segments",
                "-hls_segment_type",
                "mpegts",
                "-hls_segment_filename",
                "seg_%03d.ts",
                "playlist.m3u8",
            ]));
            args
        };

        let attempt = self
            .run_with_gpu_fallback(
                &session_id,
                true,
                use_gpu && quality != "source",
                build,
                1,
                Some(&playlist),
            )
            .await;
        self.serve_session_playlist(
            &session_id,
            attempt,
            "Live",
            requested_playlist(req).as_deref(),
        )
        .await
    }

    /// `/api/live/{id}/turbo.ts` — flux MPEG-TS continu pour mpegts.js : vidéo
    /// copiée, audio TOUJOURS réencodé en AAC.
    ///
    /// POURQUOI : mpegts.js ne démuxe que l'AAC et le MP3 ; les chaînes en
    /// AC-3/E-AC-3 ou MPEG-1 Layer II donnaient une image sans aucun son. Le
    /// réencodage audio seul coûte quelques % de CPU et garde le zapping
    /// instantané (pas de segmentation HLS à amorcer).
    async fn turbo(&self, state: &AppState, req: &Req, stream_id: &str) -> Resp {
        if !is_valid_stream_id(stream_id) {
            return http::text(400, "Invalid stream ID");
        }
        let Some(playlist) = state.get_playlist(req) else {
            return http::text(403, "No playlist");
        };
        let target = format!(
            "{}/live/{}/{}/{stream_id}.ts",
            playlist.dns, playlist.username, playlist.password
        );
        println!("[Live Turbo] {stream_id}: {}", redact_url(&target));

        // Un identifiant par requête : deux onglets sur la même chaîne sont
        // deux connexions distinctes chez le fournisseur.
        let n = self.turbo_counter.fetch_add(1, Ordering::SeqCst) + 1;
        let upstream_id = format!("turbo_{stream_id}_{n}");
        self.claim_upstream(&playlist, &upstream_id).await;

        let mut args = strings(&[
            "-hide_banner",
            "-loglevel",
            "warning",
            "-headers",
            "User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n",
            "-reconnect",
            "1",
            "-reconnect_streamed",
            "1",
            "-reconnect_at_eof",
            "1",
            "-reconnect_delay_max",
            "10",
            "-rw_timeout",
            "30000000",
            // Démarrage rapide : pas de tampon d'analyse, sonde réduite.
            "-fflags",
            "nobuffer",
            "-flags",
            "low_delay",
            "-probesize",
            "1000000",
            "-analyzeduration",
            "1000000",
            "-i",
        ]);
        args.push(target);
        args.extend(strings(&[
            "-c:v",
            "copy",
            "-c:a",
            "aac",
            "-b:a",
            "160k",
            "-ac",
            "2",
            "-ar",
            "48000",
            "-af",
            "aresample=async=1",
            // Pas de délai de mux : les paquets partent dès qu'ils existent.
            "-muxdelay",
            "0",
            "-muxpreload",
            "0",
            "-f",
            "mpegts",
            "pipe:1",
        ]));

        let spawned = tokio::process::Command::new(ffmpeg_path())
            .args(&args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let mut child = match spawned {
            Ok(c) => c,
            Err(e) => {
                // Serveur saturé : un 503 que le lecteur sait traiter.
                println!(
                    "[Live Turbo] {stream_id} : FFmpeg n'a pas démarré ({})",
                    redact_url(&e.to_string())
                );
                return http::text(503, "FFmpeg start failed");
            }
        };
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let process = ManagedChild::spawn(child);

        // Dernier octet remis au client : un lecteur vivant en reçoit à chaque
        // rafale ; un client parti n'en reçoit plus (contre-pression).
        let started = Instant::now();
        let last_delivered = Arc::new(AtomicU64::new(0));
        let ld = last_delivered.clone();
        let release_process = process.clone();
        self.register_upstream(
            &playlist,
            &upstream_id,
            process.clone(),
            Box::new(move || release_process.terminate()),
            Box::new(move || {
                let elapsed = started.elapsed().as_millis() as u64;
                Duration::from_millis(elapsed.saturating_sub(ld.load(Ordering::Relaxed)))
            }),
        );

        // Erreurs FFmpeg journalisées (masquées) sans bloquer le flux.
        if let Some(stderr) = stderr {
            let id = stream_id.to_string();
            tokio::spawn(async move {
                let mut lines = BufReader::new(stderr).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let trimmed = line.trim();
                    if !trimmed.is_empty() {
                        println!("[Live Turbo] {id} ffmpeg: {}", redact_url(trimmed));
                    }
                }
            });
        }

        let Some(stdout) = stdout else {
            process.terminate();
            return http::text(503, "FFmpeg start failed");
        };
        // Relais avec contre-pression (hyper ne lit stdout qu'au rythme du
        // client) ; FFmpeg est tué dès que le client zappe ou ferme l'onglet,
        // sinon les processus s'accumulent à chaque zap.
        let guard = TerminateOnDrop(process);
        let body = ReaderStream::new(stdout).map(move |chunk| {
            let _keep = &guard;
            last_delivered.store(started.elapsed().as_millis() as u64, Ordering::Relaxed);
            chunk
        });
        http::with_headers(
            http::response(200, Body::from_stream(body)),
            &[
                ("content-type", "video/mp2t"),
                ("cache-control", "no-store"),
            ],
        )
    }

    /// `/api/live/{id}.ts` — proxy brut (enregistrements, lecture directe),
    /// avec reconnexion amont.
    ///
    /// Les panneaux ferment régulièrement la connexion en cours de route
    /// (bascule de source, limite de connexions, recyclage nginx). Sans
    /// reprise, le `MediaSource` du navigateur s'arrête net (« ça coupe au
    /// bout de 30 s ») : on rouvre la source tant que le client écoute.
    async fn direct_proxy(&self, state: &AppState, req: &Req, stream_id: &str) -> Resp {
        let Some(playlist) = state.get_playlist(req) else {
            return http::text(403, "No playlist");
        };
        let target = format!(
            "{}/live/{}/{}/{stream_id}.ts",
            playlist.dns, playlist.username, playlist.password
        );
        println!(
            "[Live Proxy] Forwarding {stream_id}: {}",
            redact_url(&target)
        );

        // Compte à une connexion : un FFmpeg de lecture orphelin (spectateur
        // parti, session pas encore expirée) garde le slot et le panneau
        // refuse l'enregistrement. On coupe les orphelins comme les autres
        // routes ; un flux encore regardé n'est jamais coupé.
        self.claim_upstream(&playlist, &format!("direct_{stream_id}"))
            .await;

        // Première connexion hors du générateur : elle seule décide du code
        // de réponse.
        let client = state.http.clone();
        let Some(first) = open_live_upstream(&client, &target).await else {
            println!("[Live Proxy] {stream_id} : fournisseur injoignable");
            return http::text(502, "Upstream connection failed");
        };
        let status = first.status().as_u16();
        if status != 200 {
            // FFmpeg ne journalise que « 4XX » : le code exact n'est qu'ici.
            println!("[Live Proxy] {stream_id} : refusé par le fournisseur (HTTP {status})");
            return http::text(status, "Upstream refused");
        }

        let id = stream_id.to_string();
        let body = async_stream::stream! {
            let mut upstream = first;
            let mut attempt = 0;
            loop {
                let started = Instant::now();
                let mut bytes: u64 = 0;
                let mut stream = upstream.bytes_stream();
                while let Some(chunk) = stream.next().await {
                    match chunk {
                        Ok(chunk) => {
                            bytes += chunk.len() as u64;
                            yield Ok::<Bytes, std::io::Error>(chunk);
                        }
                        Err(e) => {
                            // L'erreur recopie l'URL amont, identifiants compris.
                            println!(
                                "[Live Proxy] {id} : coupure amont ({})",
                                redact_url(&format!("{e:?}"))
                            );
                            break;
                        }
                    }
                }
                drop(stream);
                let lasted = started.elapsed();
                // Une connexion restée saine remet le quota de reprises à zéro :
                // une coupure toutes les 10 minutes ne doit pas l'épuiser.
                if lasted > Duration::from_secs(60) && bytes > 0 {
                    attempt = 0;
                }
                println!("[Live Proxy] {id} : flux terminé après {}s ({bytes} octets)", lasted.as_secs());

                let mut next = None;
                while next.is_none() && attempt < LIVE_PROXY_MAX_RETRIES {
                    attempt += 1;
                    // Laisser le panneau libérer le slot précédent.
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    match open_live_upstream(&client, &target).await {
                        Some(r) if r.status().as_u16() == 200 => next = Some(r),
                        other => println!(
                            "[Live Proxy] {id} : reconnexion {attempt}/{LIVE_PROXY_MAX_RETRIES} échouée ({})",
                            other.map_or("injoignable".to_string(), |r| format!("HTTP {}", r.status().as_u16()))
                        ),
                    }
                }
                match next {
                    Some(r) => upstream = r,
                    None => {
                        println!("[Live Proxy] {id} : abandon, source injoignable");
                        break;
                    }
                }
            }
        };
        http::with_headers(
            http::response(200, Body::from_stream(body)),
            &[("content-type", "video/mp2t")],
        )
    }

    // ==========================================
    // 2. FILMS / SÉRIES
    // ==========================================

    pub async fn vod(&self, state: &AppState, req: &Req, rest: &str) -> Resp {
        if !req.is_get() {
            return http::not_found();
        }
        match segments(rest).as_slice() {
            [id, quality, "playlist.m3u8"] => {
                self.vod_playlist(state, req, id, sanitize_quality(Some(quality)))
                    .await
            }
            [id, "playlist.m3u8"] => {
                let params = req.query_params();
                let quality = sanitize_quality(params.get("quality").map(String::as_str));
                let mut query = url::form_urlencoded::Serializer::new(String::new());
                for key in ["type", "ext"] {
                    if let Some(value) = params.get(key) {
                        query.append_pair(key, value);
                    }
                }
                if let Some(p) = requested_playlist(req) {
                    query.append_pair("playlist", &p);
                }
                let query = query.finish();
                let suffix = if query.is_empty() {
                    String::new()
                } else {
                    format!("?{query}")
                };
                http::redirect(&format!("/api/vod/{id}/{quality}/playlist.m3u8{suffix}"))
            }
            [id, quality, segment] => {
                if !is_valid_stream_id(id) || segment.contains("..") {
                    return http::text(400, "Invalid request");
                }
                let session_id = format!(
                    "vod_{}_{id}_{}",
                    playlist_tag(state, req),
                    sanitize_quality(Some(quality))
                );
                self.sessions.touch(&session_id);
                serve_segment(
                    &self.sessions.base_dir.join(&session_id).join(segment),
                    3600,
                )
                .await
            }
            _ => http::not_found(),
        }
    }

    async fn vod_playlist(
        &self,
        state: &AppState,
        req: &Req,
        stream_id: &str,
        quality: &str,
    ) -> Resp {
        if !is_valid_stream_id(stream_id) {
            return http::text(400, "Invalid stream ID");
        }
        let Some(playlist) = state.get_playlist(req) else {
            return http::text(500, "No playlist");
        };
        let params = req.query_params();
        // ?type=series ou ?type=movie choisit le chemin amont.
        let content_type = params
            .get("type")
            .cloned()
            .unwrap_or_else(|| "movie".into());
        let base_path = if content_type == "series" {
            "series"
        } else {
            "movie"
        };
        // Extension réelle (`container_extension`) : le panneau refuse un
        // `.mkv` imposé à un film stocké en `.mp4`.
        let target = format!(
            "{}/{base_path}/{}/{}/{stream_id}.{}",
            playlist.dns,
            playlist.username,
            playlist.password,
            vod_container_extension(params.get("ext").map(String::as_str))
        );
        let use_gpu = state.db.is_nvidia_gpu_enabled();
        let session_id = format!("vod_{}_{stream_id}_{quality}", playlist.tag());
        if !self.sessions.contains(&session_id) {
            println!(
                "[VOD] Starting {session_id} ({content_type}): {}",
                redact_url(&target)
            );
        }

        let build = |gpu: bool| {
            let mut args = strings(&["-hide_banner", "-loglevel", "warning"]);
            if gpu {
                args.extend(strings(&["-hwaccel", "cuda"]));
            }
            args.extend(strings(&[
                "-headers",
                "User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n",
                "-reconnect",
                "1",
                "-reconnect_at_eof",
                "1",
                "-reconnect_streamed",
                "1",
                "-reconnect_delay_max",
                "10",
                "-rw_timeout",
                "30000000",
                "-timeout",
                "30000000",
                // Sonde réduite : sur un amont lent, 10 Mo avant la première
                // image ajoutaient plusieurs secondes au démarrage.
                "-analyzeduration",
                "2000000",
                "-probesize",
                "5000000",
                "-i",
            ]));
            args.push(target.clone());
            args.extend(vod_video_args(quality, gpu));
            args.extend(audio_args(quality != "source"));
            args.extend(strings(&[
                "-f",
                "hls",
                "-hls_time",
                "4",
                "-hls_list_size",
                "0",
                "-hls_playlist_type",
                "event",
                "-hls_allow_cache",
                "1",
                "-hls_flags",
                "independent_segments",
                "-hls_segment_type",
                "mpegts",
                "-hls_segment_filename",
                "segment_%03d.ts",
                "-start_number",
                "0",
                "playlist.m3u8",
            ]));
            args
        };
        let attempt = self
            .run_with_gpu_fallback(
                &session_id,
                false,
                use_gpu && quality != "source",
                build,
                1,
                Some(&playlist),
            )
            .await;
        self.serve_session_playlist(
            &session_id,
            attempt,
            "VOD",
            requested_playlist(req).as_deref(),
        )
        .await
    }

    // ==========================================
    // 3. LECTURE DES ENREGISTREMENTS
    // ==========================================

    pub async fn recording(&self, state: &AppState, req: &Req, rest: &str) -> Resp {
        if !req.is_get() {
            return http::not_found();
        }
        match segments(rest).as_slice() {
            [id, "playlist.m3u8"] => self.recording_playlist(state, req, id).await,
            [id, offset_key, segment] => self.recording_segment(id, offset_key, segment).await,
            // Compat : playlist d'avant les offsets, encore en cache.
            [id, segment] => {
                self.recording_segment(id, &recording_offset_key(0), segment)
                    .await
            }
            _ => http::not_found(),
        }
    }

    async fn recording_segment(&self, id: &str, offset_key: &str, segment: &str) -> Resp {
        if !is_valid_stream_id(id)
            || parse_recording_offset_key(offset_key).is_none()
            || segment.contains("..")
            || segment.contains('/')
        {
            return http::text(400, "Invalid request");
        }
        let session_id = format!("rec_{id}_{offset_key}");
        self.sessions.touch(&session_id);
        serve_segment(
            &self.sessions.base_dir.join(&session_id).join(segment),
            3600,
        )
        .await
    }

    async fn recording_playlist(&self, state: &AppState, req: &Req, id: &str) -> Resp {
        if !is_valid_stream_id(id) {
            return http::text(400, "Invalid request");
        }
        let Some(recording) = state.db.get_recording_by_id(id) else {
            return http::text(404, "Recording not found");
        };
        // Comme la liste : un compte ne lit que ses enregistrements (admin :
        // tous). Sans utilisateur = requête locale du serveur lui-même.
        if let Some(user) = &req.user
            && !user.is_admin
            && recording.user_id != user.id
        {
            return http::text(403, "Forbidden");
        }
        // Lisible seulement terminé ou en cours.
        match recording.status.as_str() {
            "scheduled" => return http::text(202, "Recording not yet started"),
            "failed" => {
                return http::text(
                    422,
                    format!(
                        "Recording failed: {}",
                        recording.error_reason.as_deref().unwrap_or("unknown error")
                    ),
                );
            }
            "completed" | "recording" => {}
            other => return http::text(500, format!("Invalid recording status: {other}")),
        }
        let Some(file) = recording.file_path.clone() else {
            return http::text(500, "Recording file path not set");
        };
        if !Path::new(&file).exists() {
            return http::text(500, "Physical recording file not found");
        }

        let start = parse_recording_start(req.query_param("start").as_deref());
        let offset_key = recording_offset_key(start);
        let session_prefix = format!("rec_{id}_t");
        let session_id = format!("rec_{id}_{offset_key}");

        // Capture en `-c copy` : presque toujours du H.264, directement
        // lisible en HLS. Le ré-encoder tenait à peine le temps réel en 1080p ;
        // en copie, la segmentation va à la vitesse du disque. Seuls les codecs
        // illisibles par le navigateur (HEVC, MPEG-2…) justifient un ré-encodage.
        let codec = media_probe::video_codec(&file).await;
        let can_copy = codec.as_deref() == Some("h264");

        let build = |copy_video: bool, gpu: bool| -> Vec<String> {
            let gpu = !copy_video && gpu;
            let mut args = strings(&["-hide_banner", "-loglevel", "warning"]);
            if gpu {
                args.extend(strings(&["-hwaccel", "cuda"]));
            }
            // -ss AVANT -i : recherche rapide par index ; la sortie repart de
            // 0, le lecteur ré-ajoute l'offset.
            if start > 0 {
                args.extend(["-ss".to_string(), start.to_string()]);
            }
            args.extend(["-i".to_string(), file.clone()]);
            if copy_video {
                args.extend(strings(&["-c:v", "copy"]));
            } else if gpu {
                args.extend(strings(&[
                    "-c:v",
                    "h264_nvenc",
                    "-preset",
                    "p4",
                    "-tune",
                    "hq",
                    "-rc",
                    "cbr",
                    "-b:v",
                    "3000k",
                    "-maxrate",
                    "3500k",
                    "-bufsize",
                    "6000k",
                    "-g",
                    "48",
                    "-bf",
                    "2",
                    "-pix_fmt",
                    "yuv420p",
                ]));
            } else {
                // veryfast/crf 20 : rendu identique, temps réel tenu en 1080p.
                args.extend(strings(&[
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-maxrate", "12000k",
                    "-bufsize", "24000k", "-pix_fmt", "yuv420p", "-g", "48", "-threads", "0",
                ]));
            }
            args.extend(audio_args(true));
            // `event` et non `vod` : hls.js relit la playlist et la zone
            // navigable grandit avec l'encodage.
            args.extend(strings(&[
                "-f",
                "hls",
                "-hls_time",
                "4",
                "-hls_list_size",
                "0",
                "-hls_playlist_type",
                "event",
                "-hls_allow_cache",
                "1",
                "-hls_flags",
                "independent_segments",
                "-hls_segment_type",
                "mpegts",
                "-hls_segment_filename",
                "segment_%03d.ts",
                "-start_number",
                "0",
                "playlist.m3u8",
            ]));
            args
        };

        // Trois segments d'avance avant de rendre la main : la marge qui
        // manquait au démarrage. En copie, c'est une fraction de seconde.
        let run = |copy_video: bool| {
            if !self.sessions.contains(&session_id) {
                println!(
                    "[Recording] {session_id} : {} (codec source : {})",
                    if copy_video {
                        "copie vidéo"
                    } else {
                        "ré-encodage"
                    },
                    codec.as_deref().unwrap_or("inconnu")
                );
            }
            let build = &build;
            let session_id = session_id.clone();
            let use_gpu = state.db.is_nvidia_gpu_enabled();
            async move {
                if copy_video {
                    self.run_session(&session_id, false, &build(true, false), 3, None)
                        .await
                } else {
                    self.run_with_gpu_fallback(
                        &session_id,
                        false,
                        use_gpu,
                        |gpu| build(false, gpu),
                        3,
                        None,
                    )
                    .await
                }
            }
        };

        let mut attempt = run(can_copy).await;
        // Copie refusée (conteneur, horodatages) : repli sur le ré-encodage.
        if !attempt.ready && can_copy {
            println!(
                "[Recording] {session_id} : copie vidéo refusée ({}) — repli sur le ré-encodage",
                attempt.error.as_deref().unwrap_or("null")
            );
            self.sessions.kill_session(&session_id);
            attempt = run(false).await;
        }

        let session = match attempt.session {
            Some(s) if attempt.ready => s,
            _ => {
                self.sessions.kill_session(&session_id);
                return http::text(
                    502,
                    format!(
                        "Recording transcoder failed: {}",
                        attempt.error.as_deref().unwrap_or("null")
                    ),
                );
            }
        };
        session.touch();
        // Ménage des offsets abandonnés, une fois la nouvelle session lancée.
        self.sessions
            .kill_idle_siblings(&session_prefix, &session_id);

        match tokio::fs::read_to_string(session.playlist_path()).await {
            Ok(playlist) => hls_headers(http::response(
                200,
                rewrite_recording_playlist(&playlist, &offset_key),
            )),
            Err(_) => http::text(502, "Recording transcoder failed: playlist missing"),
        }
    }
}

async fn open_live_upstream(client: &reqwest::Client, url: &str) -> Option<reqwest::Response> {
    client
        .get(url)
        .header("User-Agent", VLC_UA)
        .header("Accept", "*/*")
        .send()
        .await
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extension_vod() {
        assert_eq!(vod_container_extension(Some("mp4")), "mp4");
        assert_eq!(vod_container_extension(Some("MKV")), "mkv");
        assert_eq!(vod_container_extension(Some("avi")), "avi");
        assert_eq!(vod_container_extension(None), "mkv");
        assert_eq!(vod_container_extension(Some("")), "mkv");
        assert_eq!(vod_container_extension(Some("mp4/../x")), "mkv");
        assert_eq!(vod_container_extension(Some("mp4?a=b")), "mkv");
        assert_eq!(vod_container_extension(Some("toolongext")), "mkv");
    }

    #[test]
    fn qualites() {
        assert_eq!(sanitize_quality(Some("source")), "source");
        assert_eq!(sanitize_quality(Some("bogus")), "high");
        assert_eq!(sanitize_quality(None), "high");
        assert_eq!(live_video_args("source", true), vec!["-c:v", "copy"]);
        assert_eq!(
            with_segment_query("#EXTM3U\n#EXTINF:4,\nseg_000.ts\nseg_001.ts?x=1\n", "ab-1"),
            "#EXTM3U\n#EXTINF:4,\nseg_000.ts?playlist=ab-1\nseg_001.ts?x=1&playlist=ab-1\n"
        );
        assert!(live_video_args("high", true).contains(&"h264_nvenc".to_string()));
        assert!(vod_video_args("low", false).contains(&"scale=-2:720".to_string()));
    }

    #[test]
    fn identifiants_de_flux() {
        assert!(is_valid_stream_id("12345"));
        assert!(is_valid_stream_id("abc_-1"));
        assert!(!is_valid_stream_id("../x"));
        assert!(!is_valid_stream_id(""));
    }
}
