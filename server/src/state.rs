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
    /// Playlist explicitement choisie par le client (en-tête ou paramètre),
    /// si l'utilisateur y a droit. Sert à filtrer les listes par IPTV ; sans
    /// choix explicite (anciens clients), rien n'est filtré.
    pub fn selected_playlist_id(&self, req: &Req) -> Option<String> {
        let requested = req
            .query_param("playlist")
            .filter(|p| !p.trim().is_empty())
            .or_else(|| req.header("x-playlist-id").map(str::to_string))?;
        let requested = requested.trim().to_string();
        self.get_playlist(req)
            .map(|p| p.id)
            .filter(|id| *id == requested)
    }

    /// Playlist Xtream de la requête.
    ///
    /// La playlist choisie par le client (paramètre `?playlist=` de l'URL,
    /// prioritaire, sinon en-tête `x-playlist-id` = sélection globale) fait
    /// foi : sans elle, toutes les fonctions
    /// (direct, guide, enregistrements) tombaient sur la playlist la plus
    /// récente, même quand une autre IPTV était sélectionnée. Un utilisateur
    /// authentifié n'accède qu'à ses playlists (admin : toutes). Sans
    /// utilisateur (flux déjà validés par jeton, ou capture FFmpeg locale),
    /// l'identifiant — un UUID — suffit.
    ///
    /// À défaut : la playlist la plus récente de l'utilisateur, sinon celle
    /// du premier utilisateur de la base.
    pub fn get_playlist(&self, req: &Req) -> Option<PlaylistConfig> {
        let requested = req
            .query_param("playlist")
            .filter(|p| !p.trim().is_empty())
            .or_else(|| req.header("x-playlist-id").map(str::to_string))
            .filter(|id| !id.trim().is_empty());
        if let Some(id) = requested
            && let Some(p) = self.db.get_playlist_by_id(id.trim())
        {
            let allowed = match &req.user {
                Some(u) => u.is_admin || p.user_id == u.id,
                None => true,
            };
            if allowed {
                return Some(p.into());
            }
            println!("[getPlaylist] Playlist demandée refusée pour cet utilisateur");
        }
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
            Some(p) => Some(p.into()),
            None => {
                println!("[getPlaylist] WARNING: No playlist found, returning null");
                None
            }
        }
    }
}

pub type SharedState = Arc<AppState>;
