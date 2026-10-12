//! Registre des processus FFmpeg de transcodage (direct, film, lecture
//! d'enregistrement).
//!
//! Responsabilités :
//! - un processus par identifiant de session (`live_{id}_{qualité}`, …)
//! - le « reaper » tue les sessions inactives au-delà d'un délai (plus aucun
//!   spectateur ne demande de segment)
//! - le dossier temporaire HLS est vidé au démarrage (orphelins d'un crash)
//! - l'arrêt du serveur tue tout (pas d'FFmpeg orphelin après `docker stop`)

use crate::util::log_redactor::redact_url;
use crate::util::process::ManagedChild;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime};
use tokio::io::{AsyncBufReadExt, BufReader};

const LIVE_IDLE_TIMEOUT: Duration = Duration::from_secs(4 * 60);
const VOD_IDLE_TIMEOUT: Duration = Duration::from_secs(15 * 60);

/// Playlist d'un direct non réécrite depuis ce délai : FFmpeg est bloqué.
const LIVE_STALL_TIMEOUT: Duration = Duration::from_secs(45);

static EPOCH: LazyLock<Instant> = LazyLock::new(Instant::now);

fn now_ms() -> u64 {
    EPOCH.elapsed().as_millis() as u64
}

/// Une session FFmpeg en cours.
pub struct FfmpegSession {
    pub id: String,
    pub child: ManagedChild,
    pub dir: PathBuf,
    pub is_live: bool,
    pub started_at: Instant,
    last_access_ms: AtomicU64,
    /// Dernières lignes de stderr, pour le diagnostic d'un échec rapide.
    recent_stderr: Mutex<VecDeque<String>>,
}

impl FfmpegSession {
    pub fn touch(&self) {
        self.last_access_ms.store(now_ms(), Ordering::Relaxed);
    }

    /// Temps écoulé depuis la dernière requête de playlist ou de segment.
    pub fn idle_for(&self) -> Duration {
        Duration::from_millis(now_ms().saturating_sub(self.last_access_ms.load(Ordering::Relaxed)))
    }

    pub fn exited(&self) -> bool {
        self.child.has_exited()
    }

    pub fn exit_code(&self) -> Option<i32> {
        self.child.exit_code()
    }

    pub fn playlist_path(&self) -> PathBuf {
        self.dir.join("playlist.m3u8")
    }

    fn stderr_text(&self) -> String {
        self.recent_stderr
            .lock()
            .unwrap()
            .iter()
            .cloned()
            .collect::<String>()
            .trim()
            .to_string()
    }
}

pub struct FfmpegSessionManager {
    pub base_dir: PathBuf,
    sessions: Mutex<HashMap<String, Arc<FfmpegSession>>>,
}

fn playlist_contains(path: &Path, needle: &str) -> bool {
    std::fs::read_to_string(path).is_ok_and(|c| c.contains(needle))
}

impl FfmpegSessionManager {
    pub fn new(base_dir: PathBuf) -> Self {
        Self {
            base_dir,
            sessions: Mutex::new(HashMap::new()),
        }
    }

    /// Vide les dossiers orphelins et démarre le reaper. Une fois au démarrage.
    pub fn init(self: &Arc<Self>) {
        if self.base_dir.exists()
            && let Err(e) = std::fs::remove_dir_all(&self.base_dir)
        {
            println!("[FFmpegManager] Could not wipe temp dir: {e}");
        }
        let _ = std::fs::create_dir_all(&self.base_dir);

        let this = self.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(60));
            interval.tick().await;
            loop {
                interval.tick().await;
                this.reap();
            }
        });
    }

    pub fn get(&self, id: &str) -> Option<Arc<FfmpegSession>> {
        self.sessions.lock().unwrap().get(id).cloned()
    }

    /// Marque une session comme utilisée (routes de playlist ET de segment).
    pub fn touch(&self, id: &str) {
        if let Some(session) = self.get(id) {
            session.touch();
        }
    }

    pub fn contains(&self, id: &str) -> bool {
        self.sessions.lock().unwrap().contains_key(id)
    }

    fn needs_start_for(existing: Option<&Arc<FfmpegSession>>, is_live: bool) -> bool {
        let Some(existing) = existing else {
            return true;
        };
        if !existing.exited() {
            return false;
        }
        // Un transcodage VOD/enregistrement terminé proprement reste lisible
        // depuis ses segments : on le réutilise au lieu de retranscoder.
        is_live
            || existing.exit_code() != Some(0)
            || !playlist_contains(&existing.playlist_path(), "#EXT-X-ENDLIST")
    }

    /// Vrai si [get_or_start] lancerait un nouveau processus — donc une
    /// nouvelle connexion au fournisseur.
    pub fn needs_start(&self, id: &str, is_live: bool) -> bool {
        let sessions = self.sessions.lock().unwrap();
        Self::needs_start_for(sessions.get(id), is_live)
    }

    /// Session saine existante, ou nouveau processus FFmpeg. Le dossier de
    /// session est recréé pour une nouvelle session ; [args] y est exécuté.
    pub fn get_or_start(
        &self,
        id: &str,
        is_live: bool,
        ffmpeg_path: &str,
        args: &[String],
    ) -> std::io::Result<Arc<FfmpegSession>> {
        let mut sessions = self.sessions.lock().unwrap();
        let existing = sessions.get(id).cloned();
        if let Some(existing) = &existing {
            if !Self::needs_start_for(Some(existing), is_live) {
                existing.touch();
                return Ok(existing.clone());
            }
            // Processus mort : nettoyer avant de relancer.
            sessions.remove(id);
            existing.child.terminate();
            let _ = std::fs::remove_dir_all(&existing.dir);
        }

        let dir = self.base_dir.join(id);
        if dir.exists() {
            let _ = std::fs::remove_dir_all(&dir);
        }
        std::fs::create_dir_all(&dir)?;

        let mut child = tokio::process::Command::new(ffmpeg_path)
            .args(args)
            .current_dir(&dir)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()?;
        let stderr = child.stderr.take();
        let managed = ManagedChild::spawn(child);

        let session = Arc::new(FfmpegSession {
            id: id.to_string(),
            child: managed,
            dir,
            is_live,
            started_at: Instant::now(),
            last_access_ms: AtomicU64::new(now_ms()),
            recent_stderr: Mutex::new(VecDeque::new()),
        });
        sessions.insert(id.to_string(), session.clone());
        drop(sessions);

        if let Some(stderr) = stderr {
            let s = session.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(stderr).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    {
                        let mut recent = s.recent_stderr.lock().unwrap();
                        recent.push_back(format!("{line}\n"));
                        if recent.len() > 20 {
                            recent.pop_front();
                        }
                    }
                    // FFmpeg rappelle l'URL d'entrée (« Input #0 … from
                    // 'http://…' ») : masquer les identifiants Xtream.
                    println!("[FFmpeg {}] {}", s.id, redact_url(&line));
                }
            });
        }

        let s = session.clone();
        tokio::spawn(async move {
            let code = s.child.wait().await;
            println!("[FFmpegManager] Session {} exited with code {code}", s.id);
        });

        Ok(session)
    }

    /// Attend que la playlist de la session référence au moins
    /// [min_segments] segments. Échoue vite si le processus meurt avant d'avoir
    /// produit quoi que ce soit, en renvoyant son stderr récent.
    ///
    /// [min_segments] > 1 donne au lecteur une avance de démarrage. Une
    /// playlist déjà close (`#EXT-X-ENDLIST`) est rendue telle quelle.
    pub async fn wait_for_playlist(
        &self,
        session: &FfmpegSession,
        min_segments: usize,
    ) -> (bool, Option<String>) {
        let playlist = session.playlist_path();
        let deadline = Instant::now() + Duration::from_secs(30);

        while Instant::now() < deadline {
            if let Ok(content) = tokio::fs::read_to_string(&playlist).await {
                let segments = content.matches(".ts").count();
                if segments >= min_segments || (segments > 0 && content.contains("#EXT-X-ENDLIST"))
                {
                    return (true, None);
                }
            }
            if session.exited() {
                // Un encodeur terminé proprement avec moins de segments que
                // demandé a simplement fini : c'est un succès.
                if session.exit_code() == Some(0) && playlist_contains(&playlist, ".ts") {
                    return (true, None);
                }
                return (
                    false,
                    Some(format!(
                        "FFmpeg exited ({}): {}",
                        session.exit_code().unwrap_or(-1),
                        session.stderr_text()
                    )),
                );
            }
            // 100 ms : à 500 ms, on ajoutait en moyenne un quart de seconde
            // de latence pure entre la disponibilité de la playlist et sa
            // réponse.
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        // Délai écoulé : mieux vaut servir ce qui existe que rien.
        if playlist_contains(&playlist, ".ts") {
            return (true, None);
        }
        (false, Some("Timeout waiting for transcoder".to_string()))
    }

    pub fn kill_session(&self, id: &str) {
        let Some(session) = self.sessions.lock().unwrap().remove(id) else {
            return;
        };
        session.child.terminate();
        if session.dir.exists()
            && let Err(e) = std::fs::remove_dir_all(&session.dir)
        {
            println!("[FFmpegManager] Could not delete dir for {id}: {e}");
        }
    }

    /// Tue les sessions sœurs d'un même contenu (`rec_<id>_t0`,
    /// `rec_<id>_t600`…) que plus personne ne consomme depuis 30 s.
    ///
    /// Chaque saut hors de la zone déjà transcodée démarre un FFmpeg à un
    /// nouvel offset ; sans ce ménage, une poignée d'allers-retours dans la
    /// barre de progression laisserait autant de processus vivants jusqu'au
    /// TTL de 15 minutes.
    pub fn kill_idle_siblings(&self, prefix: &str, keep: &str) {
        let stale: Vec<String> = self
            .sessions
            .lock()
            .unwrap()
            .values()
            .filter(|s| s.id != keep && s.id.starts_with(prefix))
            .filter(|s| s.idle_for() >= Duration::from_secs(30))
            .map(|s| s.id.clone())
            .collect();
        for id in stale {
            println!("[FFmpegManager] Dropping stale sibling {id}");
            self.kill_session(&id);
        }
    }

    pub fn kill_all(&self) {
        let ids: Vec<String> = self.sessions.lock().unwrap().keys().cloned().collect();
        println!("[FFmpegManager] Killing {} session(s)", ids.len());
        for id in ids {
            self.kill_session(&id);
        }
    }

    fn reap(&self) {
        let sessions: Vec<Arc<FfmpegSession>> =
            self.sessions.lock().unwrap().values().cloned().collect();
        for session in sessions {
            let timeout = if session.is_live {
                LIVE_IDLE_TIMEOUT
            } else {
                VOD_IDLE_TIMEOUT
            };
            let idle = session.idle_for();

            // Les sessions terminées gardent leurs segments jusqu'au délai
            // d'inactivité : un film transcodé est souvent encore regardé.
            if idle > timeout {
                println!(
                    "[FFmpegManager] Reaping idle session {} (idle {}s)",
                    session.id,
                    idle.as_secs()
                );
                self.kill_session(&session.id);
                continue;
            }

            // Chien de garde : un direct dont la playlist n'est plus réécrite
            // est bloqué sur une source figée. Le tuer laisse la prochaine
            // requête du lecteur relancer le transcodeur.
            if session.is_live && !session.exited() && Self::is_stalled(&session) {
                println!(
                    "[FFmpegManager] Restarting stalled live session {}",
                    session.id
                );
                self.kill_session(&session.id);
            }
        }
    }

    fn is_stalled(session: &FfmpegSession) -> bool {
        match std::fs::metadata(session.playlist_path()).and_then(|m| m.modified()) {
            Ok(modified) => SystemTime::now()
                .duration_since(modified)
                .is_ok_and(|age| age > LIVE_STALL_TIMEOUT),
            // Jamais rien produit : délai compté depuis le démarrage.
            Err(_) => session.started_at.elapsed() > LIVE_STALL_TIMEOUT,
        }
    }
}
