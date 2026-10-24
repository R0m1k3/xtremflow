//! Serveur XtremFlow : API REST, proxy Xtream, streaming FFmpeg,
//! enregistrements TV et fichiers de la build web Flutter.

#![allow(clippy::result_large_err)]

mod api;
mod dart_time;
mod db;
mod http;
mod models;
mod server;
mod services;
mod state;
mod util;

use crate::api::epg::{EpgApi, default_panel_xmltv};
use crate::api::proxy::ProxyHandler;
use crate::api::streaming::Streaming;
use crate::db::AppDatabase;
use crate::server::RateLimiter;
use crate::services::cleanup::CleanupService;
use crate::services::ffmpeg_sessions::FfmpegSessionManager;
use crate::services::logo_catalog::LogoCatalog;
use crate::services::nba_autorec::NbaAutoRecorder;
use crate::services::recording_scheduler::RecordingScheduler;
use crate::services::xmltv::{XmltvConfig, XmltvEpgService};
use crate::state::AppState;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

const DEFAULT_XMLTV: &str = "https://epgshare01.online/epgshare01/epg_ripper_FR1.xml.gz,https://epgshare01.online/epgshare01/epg_ripper_CH1.xml.gz,https://epgshare01.online/epgshare01/epg_ripper_BE2.xml.gz";

struct Args {
    port: u16,
    path: String,
}

/// `--port 8089` / `-p 8089` / `--port=8089`, `--path /app/web`.
fn parse_args() -> Args {
    let mut args = Args {
        port: 8089,
        path: "/app/web".to_string(),
    };
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < raw.len() {
        let (key, inline) = match raw[i].split_once('=') {
            Some((k, v)) => (k.to_string(), Some(v.to_string())),
            None => (raw[i].clone(), None),
        };
        let mut value = || {
            inline.clone().or_else(|| {
                i += 1;
                raw.get(i).cloned()
            })
        };
        match key.as_str() {
            "--port" | "-p" => {
                if let Some(v) = value() {
                    args.port = v.parse().expect("--port doit être un entier");
                }
            }
            "--path" => {
                if let Some(v) = value() {
                    args.path = v;
                }
            }
            _ => {}
        }
        i += 1;
    }
    args
}

fn http_client(redirects: reqwest::redirect::Policy) -> reqwest::Client {
    reqwest::Client::builder()
        .redirect(redirects)
        .user_agent("VLC/3.0.18 LibVLC/3.0.18")
        .connect_timeout(Duration::from_secs(30))
        .build()
        .expect("client HTTP")
}

#[tokio::main]
async fn main() {
    let args = parse_args();
    let web_path = args.path.clone();

    let db_path =
        std::env::var("XTREMFLOW_DB_PATH").unwrap_or_else(|_| "/app/data/xtremflow.db".into());
    let db = Arc::new(AppDatabase::open(&db_path).expect("ouverture de la base"));
    db.seed_admin().expect("création du compte admin");

    let http = http_client(reqwest::redirect::Policy::limited(5));
    let http_manual = http_client(reqwest::redirect::Policy::none());
    // URL fournies par les clients (proxy d'images / API Xtream) : chaque
    // adresse résolue est contrôlée à la connexion (anti-SSRF).
    let http_guarded = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("VLC/3.0.18 LibVLC/3.0.18")
        .connect_timeout(Duration::from_secs(30))
        .dns_resolver(Arc::new(crate::util::ssrf::GuardedResolver::from_env()))
        .build()
        .expect("client HTTP");

    // Planificateur d'enregistrements (les season passes résolvent la
    // playlist de leur propriétaire à chaque scan).
    let scheduler = Arc::new(RecordingScheduler::new(db.clone(), http.clone()));
    scheduler.start();

    // Sessions FFmpeg de streaming.
    let sessions = Arc::new(FfmpegSessionManager::new(
        std::env::temp_dir().join("xtremflow_streams"),
    ));
    sessions.init();
    let streaming = Arc::new(Streaming::new(sessions.clone(), http.clone()));

    // Source XMLTV de repli. EPG_XMLTV_URLS vide = aucun appel sortant : le
    // guide se limite alors au panneau de l'abonné.
    let xmltv_urls: Vec<String> = std::env::var("EPG_XMLTV_URLS")
        .unwrap_or_else(|_| DEFAULT_XMLTV.to_string())
        .split(',')
        .map(|u| u.trim().to_string())
        .filter(|u| !u.is_empty())
        .collect();
    if xmltv_urls.is_empty() {
        println!("[EPG] Repli XMLTV désactivé (EPG_XMLTV_URLS vide)");
    } else {
        println!("[EPG] Repli XMLTV : {} source(s)", xmltv_urls.len());
    }
    let xmltv = (!xmltv_urls.is_empty()).then(|| {
        Arc::new(XmltvEpgService::new(
            XmltvConfig::new(xmltv_urls),
            http.clone(),
        ))
    });
    let epg = EpgApi::new(xmltv, http.clone(), default_panel_xmltv(http.clone()));

    // Enregistrement automatique des matchs NBA en direct sur beIN Sports FR.
    let nba = Arc::new(NbaAutoRecorder::new(db.clone(), http.clone(), epg.clone()));
    nba.start();

    // Purge des temporaires. Jamais le dossier temporaire système en
    // récursif : il contient les sessions HLS.
    let cleanup = Arc::new(CleanupService::new());
    cleanup.add_target("/app/data/logs");
    cleanup.add_target("/app/data/tmp");
    cleanup.start();

    // Libs de lecture servies depuis l'image : si elles manquent, le lecteur
    // échoue côté navigateur sans que rien ne l'ait signalé. On le dit ici.
    for lib in ["hls.min.js", "mpegts.min.js"] {
        if !std::path::Path::new(&web_path)
            .join("vendor")
            .join(lib)
            .exists()
        {
            println!(
                "[Server] ATTENTION: web/vendor/{lib} absent de {web_path} — la lecture échouera dans le navigateur."
            );
        }
    }

    let versioned = util::asset_versioning::build_versioned_entry_points(&web_path);
    let mut keys: Vec<&String> = versioned.keys().collect();
    keys.sort();
    println!(
        "[Server] Assets versionnés : {}",
        keys.iter()
            .map(|k| k.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    );

    let state = Arc::new(AppState {
        db: db.clone(),
        web_path: web_path.clone(),
        versioned,
        http: http.clone(),
        http_manual,
        http_guarded,
        scheduler: scheduler.clone(),
        nba,
        streaming,
        proxy: ProxyHandler::new(),
        epg,
        logo_catalog: Arc::new(LogoCatalog::new(http.clone())),
        cleanup,
        rate_limit: RateLimiter::new(600),
        login_rate_limit: RateLimiter::new(10),
        allowed_origin: std::env::var("ALLOWED_ORIGIN")
            .ok()
            .filter(|o| !o.is_empty()),
        trusted_proxies: std::env::var("TRUSTED_PROXIES")
            .unwrap_or_default()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
    });

    // Sessions expirées purgées toutes les heures.
    let db_clean = db.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(3600));
        interval.tick().await;
        loop {
            interval.tick().await;
            db_clean.clean_expired_sessions();
            println!("Cleaned expired sessions");
        }
    });

    // Arrêt gracieux unique (docker stop / Ctrl+C) : clôturer d'abord les
    // enregistrements (kill FFmpeg, fusion des parties, statut en base),
    // puis les sessions de streaming, puis sortir.
    tokio::spawn(shutdown_on_signal(scheduler, sessions));

    let app = axum::Router::new()
        .fallback(server::entry)
        .with_state(state);
    let addr = SocketAddr::from(([0, 0, 0, 0], args.port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("écoute sur {addr} impossible : {e}"));

    println!("Server started on port {}", args.port);
    println!("Serving static files from: {web_path}");
    println!("REST API available at: /api/auth/* and /api/playlists/*");
    println!("Xtream proxy available at: /api/xtream/* (SSRF Protected)");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .expect("serveur HTTP");
}

async fn shutdown_on_signal(
    scheduler: Arc<RecordingScheduler>,
    sessions: Arc<FfmpegSessionManager>,
) {
    let signal = wait_for_signal().await;
    println!("[Server] {signal} reçu, arrêt en cours…");
    scheduler.shutdown().await;
    sessions.kill_all();
    // Laisser SIGTERM partir vers les FFmpeg avant de sortir.
    tokio::time::sleep(Duration::from_millis(200)).await;
    std::process::exit(0);
}

#[cfg(unix)]
async fn wait_for_signal() -> &'static str {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate()).expect("SIGTERM");
    let mut int = signal(SignalKind::interrupt()).expect("SIGINT");
    tokio::select! {
        _ = term.recv() => "SIGTERM",
        _ = int.recv() => "SIGINT",
    }
}

#[cfg(not(unix))]
async fn wait_for_signal() -> &'static str {
    let _ = tokio::signal::ctrl_c().await;
    "SIGINT"
}
