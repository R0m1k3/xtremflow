//! État partagé du serveur.

use crate::api::epg::EpgApi;
use crate::api::proxy::ProxyHandler;
use crate::api::streaming::Streaming;
use crate::db::AppDatabase;
use crate::http::Req;
use crate::models::PlaylistConfig;
use crate::server::RateLimiter;
use crate::services::cleanup::CleanupService;
use crate::services::logo_catalog::LogoCatalog;
use crate::services::nba_autorec::NbaAutoRecorder;
use crate::services::recording_scheduler::RecordingScheduler;
use std::collections::HashMap;
use std::sync::Arc;

pub struct AppState {
    pub db: Arc<AppDatabase>,
    pub web_path: String,
    /// Points d'entrée réécrits avec `?v=<empreinte>` (asset_versioning).
    pub versioned: HashMap<String, String>,
    /// Client HTTP qui suit les redirections.
    pub http: reqwest::Client,
    /// Client HTTP sans suivi des redirections (revalidées à la main).
    pub http_manual: reqwest::Client,
    pub scheduler: Arc<RecordingScheduler>,
    pub nba: Arc<NbaAutoRecorder>,
    pub streaming: Arc<Streaming>,
    pub proxy: ProxyHandler,
    pub epg: EpgApi,
    pub logo_catalog: Arc<LogoCatalog>,
    pub cleanup: Arc<CleanupService>,
    pub rate_limit: RateLimiter,
    pub login_rate_limit: RateLimiter,
    pub allowed_origin: Option<String>,
    pub trusted_proxies: Vec<String>,
}

impl AppState {
    /// Playlist Xtream de la requête : la première playlist de l'utilisateur
    /// authentifié ; à défaut (proxy, streaming), celle du premier
    /// utilisateur de la base.
    pub fn get_playlist(&self, req: &Req) -> Option<PlaylistConfig> {
        let playlist = match &req.user {
            Some(user) => self.db.get_playlists(&user.id).into_iter().next(),
            None => {
                let users = self.db.get_all_users();
                users
                    .first()
                    .and_then(|u| self.db.get_playlists(&u.id).into_iter().next())
            }
        };
        match playlist {
            Some(p) => Some(PlaylistConfig {
                dns: p.server_url,
                username: p.username,
                password: p.password,
            }),
            None => {
                println!("[getPlaylist] WARNING: No playlist found, returning null");
                None
            }
        }
    }
}

pub type SharedState = Arc<AppState>;
