//! Planificateur des enregistrements TV : démarrage à l'heure, capture
//! FFmpeg (`-c copy`), relances après coupure amont, reprise après
//! redémarrage du serveur, fusion des parties, season passes et rotation
//! disque.

use crate::dart_time::{DartDateTime, display_local, now_display};
use crate::db::AppDatabase;
use crate::models::Recording;
use crate::services::recording_decision::{
    OrphanAction, PostExitAction, RecordingAction, capture_duration, decide_orphan_action,
    decide_post_exit_action, decide_recording_action, describe_ffmpeg_exit, ffmpeg_retry_delay,
};
use crate::util::b64;
use crate::util::log_redactor::redact_url;
use crate::util::process::ManagedChild;
use chrono::Utc;
use futures::FutureExt;
use regex::Regex;
use serde_json::Value;
use std::collections::HashMap;
use std::io::Write;
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};
use tokio::io::AsyncReadExt;
use tokio::task::JoinHandle;

/// Dossier où sont écrits les enregistrements et leurs logs.
pub fn recordings_dir_path() -> String {
    std::env::var("RECORDINGS_DIR").unwrap_or_else(|_| "/app/recordings".to_string())
}

/// Binaire FFmpeg de la capture et de la fusion des parties.
pub fn resolve_ffmpeg_path() -> String {
    if let Ok(path) = std::env::var("FFMPEG_PATH")
        && !path.is_empty()
    {
        return path;
    }
    if cfg!(target_os = "linux") && Path::new("/usr/local/bin/ffmpeg").exists() {
        return "/usr/local/bin/ffmpeg".to_string();
    }
    "ffmpeg".to_string()
}

fn env_int(name: &str, default: i64) -> i64 {
    std::env::var(name)
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(default)
}

/// Journal d'un enregistrement, tolérant aux erreurs d'écriture : la
/// capture reste prioritaire sur sa journalisation.
struct RecordingLog {
    file: Mutex<Option<std::fs::File>>,
}

impl RecordingLog {
    fn open(path: &Path, append: bool) -> Option<Self> {
        let result = std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .append(append)
            .truncate(!append)
            .open(path);
        match result {
            Ok(file) => Some(Self {
                file: Mutex::new(Some(file)),
            }),
            Err(e) => {
                println!(
                    "[RecordingScheduler] AVERTISSEMENT: log indisponible ({}): {e}",
                    path.display()
                );
                None
            }
        }
    }

    fn add(&self, data: &[u8]) {
        let mut guard = self.file.lock().unwrap();
        if let Some(file) = guard.as_mut()
            && file.write_all(data).is_err()
        {
            // Fichier cassé : on arrête d'écrire plutôt que de propager.
            *guard = None;
        }
    }

    fn writeln(&self, line: &str) {
        self.add(format!("{line}\n").as_bytes());
    }

    fn close(&self) {
        if let Some(mut file) = self.file.lock().unwrap().take() {
            let _ = file.flush();
        }
    }
}

struct ActiveState {
    /// Fichiers additionnels écrits après une relance, dans l'ordre.
    extra_parts: Vec<String>,
    /// Index du lancement FFmpeg en cours (0 = fichier principal).
    attempt: u32,
    /// Échecs consécutifs, remis à zéro quand une capture tient assez longtemps.
    consecutive_failures: u32,
    launched_at: Instant,
    process: Option<ManagedChild>,
}

struct ActiveRecording {
    recording: Recording,
    /// Fichier principal (celui exposé par l'API).
    file_path: String,
    log: Option<RecordingLog>,
    state: Mutex<ActiveState>,
    /// Arrêt volontaire : la sortie de FFmpeg ne doit pas déclencher de relance.
    stopping: AtomicBool,
}

impl ActiveRecording {
    fn log(&self, line: &str) {
        if let Some(log) = &self.log {
            log.writeln(line);
        }
    }
}

pub struct RecordingScheduler {
    db: Arc<AppDatabase>,
    http: reqwest::Client,
    active: Mutex<HashMap<String, Arc<ActiveRecording>>>,
    is_running: AtomicBool,
    timers: Mutex<Vec<JoinHandle<()>>>,
    /// Enregistrements simultanés (MAX_CONCURRENT_RECORDINGS).
    pub max_concurrent: usize,
    /// Espace libre minimal (Mo) exigé pour démarrer une capture.
    min_free_disk_mb: i64,
    /// Quota du dossier d'enregistrements en Go (0 = rotation désactivée).
    recordings_quota_gb: i64,
    /// Enregistrements créés au plus par season pass et par scan.
    season_pass_max_per_scan: i64,
}

static UNSAFE_FILENAME_CHAR: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[^a-zA-Z0-9_\-]").unwrap());

impl RecordingScheduler {
    pub fn new(db: Arc<AppDatabase>, http: reqwest::Client) -> Self {
        Self {
            db,
            http,
            active: Mutex::new(HashMap::new()),
            is_running: AtomicBool::new(false),
            timers: Mutex::new(Vec::new()),
            max_concurrent: env_int("MAX_CONCURRENT_RECORDINGS", 2).max(0) as usize,
            min_free_disk_mb: env_int("MIN_FREE_DISK_MB", 500),
            recordings_quota_gb: env_int("RECORDINGS_QUOTA_GB", 0),
            season_pass_max_per_scan: env_int("SEASON_PASS_MAX_PER_SCAN", 10),
        }
    }

    /// Un enregistrement est-il activement capturé par un processus FFmpeg ?
    pub fn is_capturing(&self, id: &str) -> bool {
        self.active.lock().unwrap().contains_key(id)
    }

    /// Relances FFmpeg de l'enregistrement actif [id] (`None` si inactif).
    pub fn retry_count_of(&self, id: &str) -> Option<u32> {
        let active = self.active.lock().unwrap().get(id).cloned()?;
        let failures = active.state.lock().unwrap().consecutive_failures;
        Some(failures)
    }

    fn get_active(&self, id: &str) -> Option<Arc<ActiveRecording>> {
        self.active.lock().unwrap().get(id).cloned()
    }

    fn is_current(&self, active: &Arc<ActiveRecording>) -> bool {
        self.get_active(&active.recording.id)
            .is_some_and(|current| Arc::ptr_eq(&current, active))
    }

    pub fn start(self: &Arc<Self>) {
        println!(
            "[RecordingScheduler] Démarrage du planificateur d'enregistrements TV (max simultanés: {})",
            self.max_concurrent
        );
        let mut timers = self.timers.lock().unwrap();

        // Toutes les 10 secondes (démarrage quasi immédiat), premier passage tout de suite.
        let this = self.clone();
        timers.push(tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(10));
            loop {
                interval.tick().await;
                this.check_and_run_recordings().await;
            }
        }));

        // Season passes : un premier scan après 30 s (laisser le serveur
        // démarrer), puis toutes les 4 heures.
        let this = self.clone();
        timers.push(tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(30)).await;
            this.check_season_passes().await;
        }));
        let this = self.clone();
        timers.push(tokio::spawn(async move {
            let period = Duration::from_secs(4 * 3600);
            let mut interval =
                tokio::time::interval_at(tokio::time::Instant::now() + period, period);
            loop {
                interval.tick().await;
                this.check_season_passes().await;
            }
        }));
    }

    /// Arrêt gracieux pour un `docker stop` : arrête les timers, clôt chaque
    /// enregistrement actif (kill FFmpeg, fusion des parties, statut en base)
    /// et attend la fin des clôtures dans la limite de 8 secondes.
    ///
    /// Sans cette attente, le conteneur meurt avant la clôture : les
    /// enregistrements restent au statut « recording » et la reprise
    /// d'orphelins doit systématiquement rattraper au redémarrage.
    pub async fn shutdown(self: &Arc<Self>) {
        for timer in self.timers.lock().unwrap().drain(..) {
            timer.abort();
        }
        let ids: Vec<String> = self.active.lock().unwrap().keys().cloned().collect();
        let closings: Vec<JoinHandle<()>> = ids
            .iter()
            .filter_map(|id| self.stop_active_recording(id, Some("Arrêt du serveur")))
            .collect();
        if !closings.is_empty() {
            println!(
                "[RecordingScheduler] Clôture de {} enregistrement(s)…",
                closings.len()
            );
            let _ =
                tokio::time::timeout(Duration::from_secs(8), futures::future::join_all(closings))
                    .await;
        }
        println!("[RecordingScheduler] Arrêté proprement");
    }

    async fn check_and_run_recordings(self: &Arc<Self>) {
        if self.is_running.swap(true, Ordering::SeqCst) {
            return;
        }
        let result = AssertUnwindSafe(self.run_tick()).catch_unwind().await;
        if let Err(panic) = result {
            println!("[RecordingScheduler] ERREUR CRITIQUE: {panic:?}");
        }
        self.is_running.store(false, Ordering::SeqCst);
    }

    async fn run_tick(self: &Arc<Self>) {
        // Toujours comparer en UTC pour éviter les problèmes de fuseau horaire.
        let now = Utc::now();

        // Arrêter les enregistrements actifs dont l'heure de fin est passée.
        let actives: Vec<Arc<ActiveRecording>> =
            self.active.lock().unwrap().values().cloned().collect();
        for active in actives {
            if now > active.recording.end_utc() {
                println!(
                    "[RecordingScheduler] Fin de l'enregistrement : {}",
                    active.recording.title
                );
                self.stop_active_recording(&active.recording.id, None);
            }
        }

        // Lire la base APRÈS les arrêts : un instantané pris avant ferait
        // passer l'enregistrement tout juste terminé pour un orphelin.
        for recording in self.db.get_pending_recordings() {
            // « recording » sans processus associé : le serveur a redémarré
            // (ou l'enregistrement n'a jamais démarré).
            if recording.status == "recording" && !self.is_capturing(&recording.id) {
                self.recover_orphan(&recording, now).await;
                continue;
            }
            if recording.status != "scheduled" {
                continue;
            }
            let active_count = self.active.lock().unwrap().len();
            match decide_recording_action(
                now,
                recording.start_utc(),
                recording.end_utc(),
                active_count,
                self.max_concurrent,
            ) {
                RecordingAction::Start => {
                    println!(
                        "[RecordingScheduler] *** DÉMARRAGE DE L'ENREGISTREMENT : {} ***",
                        recording.title
                    );
                    self.start_recording(recording, false).await;
                }
                RecordingAction::Wait => {
                    // Capacité atteinte, fenêtre encore ouverte : on garde le
                    // statut "scheduled" et on réessaiera au prochain tick.
                    println!(
                        "[RecordingScheduler] Capacité max atteinte ({active_count}/{}), \"{}\" en attente.",
                        self.max_concurrent, recording.title
                    );
                }
                RecordingAction::Fail => {
                    println!(
                        "[RecordingScheduler] Enregistrement \"{}\" manqué (fin dépassée).",
                        recording.title
                    );
                    self.db.update_recording_status(
                        &recording.id,
                        "failed",
                        None,
                        Some("Heure de fin dépassée avant le démarrage"),
                        false,
                    );
                }
                RecordingAction::None => {}
            }
        }
    }

    /// Reprend (ou clôture) un enregistrement laissé au statut "recording"
    /// par une interruption du serveur.
    async fn recover_orphan(self: &Arc<Self>, recording: &Recording, now: chrono::DateTime<Utc>) {
        // Le statut a pu changer depuis la lecture : ne jamais requalifier un
        // enregistrement sur une donnée périmée.
        let Some(current) = self.db.get_recording_by_id(&recording.id) else {
            return;
        };
        if current.status != "recording" {
            return;
        }
        match decide_orphan_action(
            now,
            current.end_utc(),
            file_has_data(current.file_path.as_deref()),
        ) {
            OrphanAction::Resume => {
                if self.active.lock().unwrap().len() >= self.max_concurrent {
                    return; // pas de slot libre : prochain tick
                }
                println!(
                    "[RecordingScheduler] Reprise après interruption : {}",
                    current.title
                );
                self.start_recording(current, true).await;
            }
            OrphanAction::Finish => {
                println!(
                    "[RecordingScheduler] Enregistrement interrompu conservé (partiel): {}",
                    current.title
                );
                self.db.update_recording_status(
                    &current.id,
                    "completed",
                    None,
                    Some("Interruption du serveur pendant la capture : fichier partiel"),
                    false,
                );
            }
            OrphanAction::Fail => {
                println!(
                    "[RecordingScheduler] Enregistrement orphelin sans fichier: {}",
                    current.id
                );
                self.db.update_recording_status(
                    &current.id,
                    "failed",
                    None,
                    Some("Interruption inattendue du serveur"),
                    false,
                );
            }
        }
    }

    /// Titre normalisé pour la correspondance : minuscules, espaces réduits.
    fn normalize_title(title: &str) -> String {
        title
            .to_lowercase()
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn title_matches(title: &str, show_title: &str, match_mode: &str) -> bool {
        let t = Self::normalize_title(title);
        let s = Self::normalize_title(show_title);
        if s.is_empty() {
            return false;
        }
        if match_mode == "contains" {
            t.contains(&s)
        } else {
            t == s
        }
    }

    async fn check_season_passes(self: &Arc<Self>) {
        let passes = self.db.get_all_season_passes();
        if passes.is_empty() {
            return;
        }
        println!(
            "[SeasonPass] Vérification de {} Season Pass(s)...",
            passes.len()
        );
        for pass in passes {
            let show_title = pass
                .get("show_title")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            if let Err(e) = self.scan_season_pass(&pass, &show_title).await {
                // Jamais l'erreur brute : elle peut contenir l'URL amont avec
                // les identifiants Xtream.
                println!(
                    "[SeasonPass] Erreur pour le pass \"{show_title}\": {}",
                    redact_url(&e)
                );
            }
        }
    }

    async fn scan_season_pass(
        &self,
        pass: &serde_json::Map<String, Value>,
        show_title: &str,
    ) -> Result<(), String> {
        let field = |name: &str| {
            pass.get(name)
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string()
        };
        let channel_id = field("channel_id");
        let stream_url = field("stream_url");
        let user_id = field("user_id");
        let match_mode = pass
            .get("match_mode")
            .and_then(Value::as_str)
            .unwrap_or("contains")
            .to_string();

        // IPTV du pass ; à défaut (pass ancien), la plus récente du
        // propriétaire, résolue au moment du scan.
        let pass_playlist_id = field("playlist_id");
        let playlists: Vec<crate::models::Playlist> = self
            .db
            .get_playlist_by_id(&pass_playlist_id)
            .filter(|p| p.user_id == user_id)
            .into_iter()
            .chain(self.db.get_playlists(&user_id))
            .collect();
        let Some(playlist) = playlists.first() else {
            println!(
                "[SeasonPass] Aucune playlist pour le propriétaire du pass \"{show_title}\", scan ignoré"
            );
            return Ok(());
        };

        // Prochains programmes de la chaîne (`limit` = nombre de programmes).
        let url = format!(
            "{}/player_api.php?username={}&password={}&action=get_simple_data_table&stream_id={channel_id}&type=epg&limit=48",
            playlist.server_url, playlist.username, playlist.password
        );
        let request = self.http.get(&url).send();
        let response = tokio::time::timeout(Duration::from_secs(60), request)
            .await
            .map_err(|_| "TimeoutException after 0:01:00.000000".to_string())?
            .map_err(|e| e.to_string())?;
        if response.status().as_u16() != 200 {
            return Ok(());
        }
        let body = tokio::time::timeout(Duration::from_secs(60), response.bytes())
            .await
            .map_err(|_| "TimeoutException after 0:01:00.000000".to_string())?
            .map_err(|e| e.to_string())?;
        let raw: Value = serde_json::from_slice(&body).map_err(|e| e.to_string())?;
        let listings = match &raw {
            Value::Object(map) => map.get("epg_listings").and_then(Value::as_array).cloned(),
            Value::Array(list) => Some(list.clone()),
            _ => None,
        }
        .unwrap_or_default();

        let mut created = 0;
        for item in listings {
            let raw_title = item.get("title").and_then(Value::as_str).unwrap_or("");
            let title = b64::decode_text(raw_title).unwrap_or_else(|| raw_title.to_string());
            if !Self::title_matches(&title, show_title, &match_mode) {
                continue;
            }

            let start_str = item.get("start").and_then(Value::as_str).unwrap_or("");
            let end_str = item
                .get("stop")
                .and_then(Value::as_str)
                .or_else(|| item.get("end").and_then(Value::as_str))
                .unwrap_or("");
            if start_str.is_empty() || end_str.is_empty() {
                continue;
            }
            let (Some(start), Some(end)) =
                (DartDateTime::parse(start_str), DartDateTime::parse(end_str))
            else {
                continue;
            };
            let (start, end) = (start.to_utc(), end.to_utc());

            // Programme déjà terminé : rien à créer.
            if end < Utc::now() {
                continue;
            }

            // Déduplication : cet épisode est-il déjà planifié/enregistré ?
            if let Some(existing) =
                self.db
                    .find_recording_for_episode(&title, start, chrono::Duration::minutes(2))
            {
                // Programme déplacé dans l'EPG depuis la planification :
                // réaligner la fenêtre tant que la capture n'a pas commencé.
                if existing.status == "scheduled"
                    && (existing.start_utc() != start || existing.end_utc() != end)
                {
                    self.db.update_recording_window(&existing.id, start, end);
                    println!(
                        "[SeasonPass] \"{title}\" réaligné sur le nouvel horaire {}",
                        display_local(start)
                    );
                }
                continue;
            }

            if created >= self.season_pass_max_per_scan {
                println!(
                    "[SeasonPass] Plafond de {} créations atteint pour \"{show_title}\" sur ce scan",
                    self.season_pass_max_per_scan
                );
                break;
            }

            let stream_url = crate::models::stream_url_for_playlist(&stream_url, &playlist.id);
            let rec = self
                .db
                .create_recording(&user_id, &channel_id, &stream_url, &title, start, end)
                .map_err(|e| e.to_string())?;
            self.db.set_recording_playlist(&rec.id, &playlist.id);
            created += 1;
            println!(
                "[SeasonPass] ✓ Planifié automatiquement: \"{title}\" le {}",
                display_local(start)
            );
        }
        Ok(())
    }

    async fn start_recording(self: &Arc<Self>, recording: Recording, resume: bool) {
        // Un (re)démarrage rend obsolète un éventuel motif d'échec précédent.
        self.db
            .update_recording_status(&recording.id, "recording", None, None, true);

        let id = recording.id.clone();
        if let Err(e) = self.try_start_recording(recording, resume).await {
            // `io::Error` d'un spawn peut citer la commande : masquer.
            println!(
                "[RecordingScheduler] ERREUR dans _startRecording: {}",
                redact_url(&e)
            );
            self.db.update_recording_status(
                &id,
                "failed",
                None,
                Some(&format!("Erreur au lancement: {e}")),
                false,
            );
            if let Some(active) = self.active.lock().unwrap().remove(&id)
                && let Some(log) = &active.log
            {
                log.close();
            }
        }
    }

    async fn try_start_recording(
        self: &Arc<Self>,
        recording: Recording,
        resume: bool,
    ) -> Result<(), String> {
        // L'URL finit en `-i` de FFmpeg, qui résout le nom lui-même : contrôle
        // anti-SSRF refait ici (lignes anciennes, season passes, NBA auto),
        // au plus près de la connexion.
        crate::util::ssrf::check_stream_url(&recording.stream_url)
            .await
            .map_err(|e| format!("URL de flux refusée : {e}"))?;
        let dir = PathBuf::from(recordings_dir_path());
        if !dir.exists() {
            std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        }

        // Libérer de la place si le quota est dépassé.
        self.check_disk_space_and_rotate(&dir).await;

        // Refuser de démarrer sur un volume plein : mieux vaut un échec
        // explicite immédiat qu'une capture qui meurt à mi-parcours.
        if let Some(free) = free_disk_bytes(&dir) {
            let min = self.min_free_disk_mb.max(0) as u64 * 1024 * 1024;
            if free < min {
                let free_mb = free / (1024 * 1024);
                println!(
                    "[RecordingScheduler] Espace disque insuffisant ({free_mb} Mo libres, minimum {} Mo) : \"{}\" refusé",
                    self.min_free_disk_mb, recording.title
                );
                self.db.update_recording_status(
                    &recording.id,
                    "failed",
                    None,
                    Some(&format!(
                        "Espace disque insuffisant ({free_mb} Mo libres, minimum {} Mo)",
                        self.min_free_disk_mb
                    )),
                    false,
                );
                return Ok(());
            }
        }

        // Un dossier non inscriptible (droits modifiés côté hôte) ferait
        // échouer chaque relance de FFmpeg pendant toute la fenêtre, sans
        // même de log : on le signale tout de suite.
        if let Err(e) = check_writable(&dir) {
            println!(
                "[RecordingScheduler] Dossier {} non accessible en écriture ({e}) : \"{}\" refusé",
                dir.display(),
                recording.title
            );
            self.db.update_recording_status(
                &recording.id,
                "failed",
                None,
                Some(&format!(
                    "Dossier d'enregistrement non accessible en écriture ({e}). Vérifier les droits du dossier hôte (PUID/PGID)."
                )),
                false,
            );
            return Ok(());
        }

        let file_path = dir
            .join(file_name_for(&recording))
            .to_string_lossy()
            .into_owned();
        let log_path = Path::new(&file_path).with_extension("log");
        // Une reprise complète le log existant au lieu de l'écraser.
        let log = RecordingLog::open(&log_path, resume);

        let mut state = ActiveState {
            extra_parts: Vec::new(),
            attempt: 0,
            consecutive_failures: 0,
            launched_at: Instant::now(),
            process: None,
        };
        if resume {
            // Le fichier principal (et d'éventuelles parties) survivent au
            // redémarrage : on repart sur une nouvelle partie.
            state.extra_parts = existing_parts(&file_path);
            state.attempt = if file_has_data(Some(&file_path)) || !state.extra_parts.is_empty() {
                state.extra_parts.len() as u32 + 1
            } else {
                0
            };
        }
        let active = Arc::new(ActiveRecording {
            file_path: file_path.clone(),
            log,
            state: Mutex::new(state),
            stopping: AtomicBool::new(false),
            recording,
        });
        if resume {
            active.log(&format!(
                "\n[{}] Reprise après interruption du serveur",
                now_display()
            ));
        } else {
            active.log(&format!(
                "[{}] Démarrage: {}",
                now_display(),
                active.recording.title
            ));
            active.log(&format!("Destination: {file_path}"));
        }

        self.active
            .lock()
            .unwrap()
            .insert(active.recording.id.clone(), active.clone());

        // Chemin du fichier en base.
        self.db.update_recording_status(
            &active.recording.id,
            "recording",
            Some(&file_path),
            None,
            false,
        );

        self.launch_ffmpeg(&active).map_err(|e| e.to_string())
    }

    /// Lance (ou relance) FFmpeg pour un enregistrement actif.
    fn launch_ffmpeg(self: &Arc<Self>, active: &Arc<ActiveRecording>) -> std::io::Result<()> {
        let recording = &active.recording;
        let output = {
            let mut state = active.state.lock().unwrap();
            let output = if state.attempt == 0 {
                active.file_path.clone()
            } else {
                part_path(&active.file_path, state.attempt)
            };
            if state.attempt > 0 && !state.extra_parts.contains(&output) {
                state.extra_parts.push(output.clone());
            }
            output
        };

        // URL relative → absolue : le serveur écoute sur 8089 dans le conteneur.
        let mut stream_url = recording.stream_url.clone();
        if stream_url.starts_with('/') {
            stream_url = format!("http://localhost:8089{stream_url}");
        }

        let duration = capture_duration(Utc::now(), recording.end_utc());
        let args: Vec<String> = [
            "-hide_banner",
            // Les logs sont relus entièrement par l'API : sans -nostats, une
            // heure de capture produit des mégaoctets de lignes de progression.
            "-nostats",
            "-user_agent",
            "VLC/3.0.18 LibVLC/3.0.18",
            // Une coupure amont ne doit pas terminer la capture : FFmpeg
            // rouvre le flux lui-même.
            "-reconnect",
            "1",
            "-reconnect_at_eof",
            "1",
            "-reconnect_streamed",
            "1",
            "-reconnect_delay_max",
            "30",
            "-rw_timeout",
            "30000000",
            "-y",
            "-i",
        ]
        .iter()
        .map(|s| s.to_string())
        .chain([
            stream_url.clone(),
            "-c".into(),
            "copy".into(),
            "-t".into(),
            duration.num_seconds().to_string(),
            output,
        ])
        .collect();

        let ffmpeg = resolve_ffmpeg_path();
        // Le log est exposé via l'API : jamais d'identifiants dedans.
        let redacted = args
            .iter()
            .map(|a| redact_url(a))
            .collect::<Vec<_>>()
            .join(" ");
        active.log(&format!("URL: {}", redact_url(&stream_url)));
        active.log(&format!("Commande: {ffmpeg} {redacted}\n"));
        println!("[RecordingScheduler] Exécution: {ffmpeg} {redacted}");

        let mut child = tokio::process::Command::new(&ffmpeg)
            .args(&args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let process = ManagedChild::spawn(child);
        {
            let mut state = active.state.lock().unwrap();
            state.process = Some(process.clone());
            state.launched_at = Instant::now();
        }

        // stdout/stderr vers le log ; on attend la fin des deux flux avant de
        // traiter la sortie, sinon les derniers morceaux seraient perdus.
        let pipes: Vec<JoinHandle<()>> = [
            stdout.map(|s| Box::new(s) as Box<dyn tokio::io::AsyncRead + Send + Unpin>),
            stderr.map(|s| Box::new(s) as Box<dyn tokio::io::AsyncRead + Send + Unpin>),
        ]
        .into_iter()
        .flatten()
        .map(|mut stream| {
            let active = active.clone();
            tokio::spawn(async move {
                let mut buf = vec![0u8; 8192];
                while let Ok(n) = stream.read(&mut buf).await {
                    if n == 0 {
                        break;
                    }
                    if let Some(log) = &active.log {
                        log.add(&buf[..n]);
                    }
                }
            })
        })
        .collect();

        let this = self.clone();
        let active = active.clone();
        tokio::spawn(async move {
            let code = process.wait().await;
            for pipe in pipes {
                let _ = pipe.await;
            }
            let result = AssertUnwindSafe(this.on_ffmpeg_exit(active, code))
                .catch_unwind()
                .await;
            if let Err(panic) = result {
                println!("[RecordingScheduler] ERREUR à la sortie de FFmpeg: {panic:?}");
            }
        });
        Ok(())
    }

    /// Suite à donner quand un processus FFmpeg se termine.
    async fn on_ffmpeg_exit(self: Arc<Self>, active: Arc<ActiveRecording>, exit_code: i32) {
        let recording = &active.recording;

        // Arrêt volontaire, ou enregistrement repris ailleurs : la clôture est
        // gérée par celui qui a demandé l'arrêt.
        if active.stopping.load(Ordering::SeqCst) || !self.is_current(&active) {
            return;
        }

        // Une capture qui a tenu longtemps repart du délai de relance minimal.
        let (lasted, has_data) = {
            let state = active.state.lock().unwrap();
            (
                state.launched_at.elapsed(),
                active_has_data(&active.file_path, &state.extra_parts),
            )
        };
        if lasted > Duration::from_secs(120) && has_data {
            active.state.lock().unwrap().consecutive_failures = 0;
        }

        match decide_post_exit_action(Utc::now(), recording.end_utc(), exit_code, has_data) {
            PostExitAction::Retry => {
                let failures = {
                    let mut state = active.state.lock().unwrap();
                    state.attempt += 1;
                    state.consecutive_failures += 1;
                    state.consecutive_failures
                };
                let delay = ffmpeg_retry_delay(failures);
                let cause = describe_ffmpeg_exit(exit_code)
                    .map(|c| format!(", {c}"))
                    .unwrap_or_default();
                let message = format!(
                    "FFmpeg s'est arrêté (code {exit_code}{cause}) après {}s, avant la fin prévue — relance dans {}s (échec consécutif n°{failures})",
                    lasted.as_secs(),
                    delay.as_secs(),
                );
                println!("[RecordingScheduler] {}: {message}", recording.title);
                active.log(&format!("\n[{}] {message}", now_display()));
                // Laisser la source respirer : sur les comptes limités en
                // connexions simultanées, rouvrir immédiatement se fait refuser.
                tokio::time::sleep(delay).await;
                if active.stopping.load(Ordering::SeqCst) || !self.is_current(&active) {
                    return;
                }
                if let Err(e) = self.launch_ffmpeg(&active) {
                    println!(
                        "[RecordingScheduler] Relance impossible: {}",
                        redact_url(&e.to_string())
                    );
                    self.active.lock().unwrap().remove(&recording.id);
                    self.finalize(
                        &active,
                        "failed",
                        Some(&format!("Relance de FFmpeg impossible: {e}")),
                    )
                    .await;
                }
            }
            PostExitAction::Complete => {
                println!(
                    "[RecordingScheduler] Enregistrement terminé: {}",
                    recording.title
                );
                self.active.lock().unwrap().remove(&recording.id);
                self.finalize(&active, "completed", None).await;
            }
            PostExitAction::Fail => {
                println!(
                    "[RecordingScheduler] Erreur FFmpeg (code: {exit_code}) pour {}",
                    recording.title
                );
                self.active.lock().unwrap().remove(&recording.id);
                self.finalize(
                    &active,
                    "failed",
                    Some(&match describe_ffmpeg_exit(exit_code) {
                        Some(cause) => {
                            format!("Erreur FFmpeg code {exit_code} : {cause}. Voir logs.")
                        }
                        None => format!("Erreur FFmpeg code {exit_code}. Voir logs."),
                    }),
                )
                .await;
            }
        }
    }

    /// Clôture : fusion des parties, fermeture du log, statut.
    async fn finalize(&self, active: &ActiveRecording, status: &str, error_reason: Option<&str>) {
        if let Err(e) = self.merge_parts(active).await {
            println!("[RecordingScheduler] Fusion des parties impossible: {e}");
        }
        active.log(&format!(
            "\n[{}] Enregistrement clôturé avec le statut \"{status}\"",
            now_display()
        ));
        if let Some(log) = &active.log {
            log.close();
        }
        self.db.update_recording_status(
            &active.recording.id,
            status,
            Some(&active.file_path),
            error_reason,
            false,
        );
        // Matchs NBA automatiques : vignettes Plex/Jellyfin, .nfo et pochette
        // intégrée au MKV.
        if status == "completed"
            && active.recording.source_rule_id.is_some()
            && file_has_data(Some(&active.file_path))
            && let Some(game) = self.db.get_nba_game_by_recording(&active.recording.id)
        {
            crate::services::nba_artwork::finish_recording(
                &self.http,
                Path::new(&recordings_dir_path()),
                &game,
                Path::new(&active.file_path),
                &active.recording.title,
                &resolve_ffmpeg_path(),
            )
            .await;
        }
    }

    /// Recolle les parties issues des relances dans le fichier principal.
    ///
    /// Les parties viennent de la même source en `-c copy` : le demuxer
    /// `concat` les rassemble sans réencodage. En cas d'échec, fichier
    /// principal et parties sont conservés tels quels.
    async fn merge_parts(&self, active: &ActiveRecording) -> std::io::Result<()> {
        let parts: Vec<String> = {
            let state = active.state.lock().unwrap();
            state
                .extra_parts
                .iter()
                .filter(|p| file_has_data(Some(p)))
                .cloned()
                .collect()
        };
        if parts.is_empty() {
            return Ok(());
        }
        let mut segments = Vec::new();
        if file_has_data(Some(&active.file_path)) {
            segments.push(active.file_path.clone());
        }
        segments.extend(parts.iter().cloned());
        if segments.len() < 2 {
            // Fichier principal vide : la première partie le remplace.
            return tokio::fs::rename(&segments[0], &active.file_path).await;
        }

        let list_file = format!("{}.parts.txt", active.file_path);
        let list = segments
            .iter()
            .map(|s| format!("file '{}'", s.replace('\'', r"'\''")))
            .collect::<Vec<_>>()
            .join("\n");
        tokio::fs::write(&list_file, list).await?;
        let merged = format!("{}.merged.mkv", active.file_path);

        active.log(&format!(
            "\n[{}] Fusion de {} parties…",
            now_display(),
            segments.len()
        ));
        let result = tokio::process::Command::new(resolve_ffmpeg_path())
            .args([
                "-hide_banner",
                "-nostats",
                "-y",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                &list_file,
                "-c",
                "copy",
                &merged,
            ])
            .stdin(Stdio::null())
            .output()
            .await;
        delete_quietly(&list_file);

        let code = result
            .as_ref()
            .map(|o| o.status.code().unwrap_or(-1))
            .unwrap_or(-1);
        if code != 0 || !file_has_data(Some(&merged)) {
            active.log(&format!(
                "Fusion échouée (code {code}) : les parties sont conservées séparément."
            ));
            delete_quietly(&merged);
            return Ok(());
        }
        tokio::fs::rename(&merged, &active.file_path).await?;
        for part in parts {
            delete_quietly(&part);
        }
        active.log("Fusion terminée.");
        Ok(())
    }

    /// Arrête un enregistrement en cours (appelé depuis l'API).
    pub fn stop_recording(self: &Arc<Self>, id: &str) -> bool {
        let Some(active) = self.get_active(id) else {
            return false; // pas d'enregistrement actif avec cet ID
        };
        println!(
            "[RecordingScheduler] Arrêt demandé pour: {}",
            active.recording.title
        );
        self.stop_active_recording(id, None);
        true
    }

    /// Arrête l'enregistrement actif [id] et renvoie la tâche de clôture
    /// (fusion + statut), ou `None` si aucun n'est actif.
    fn stop_active_recording(
        self: &Arc<Self>,
        id: &str,
        reason: Option<&str>,
    ) -> Option<JoinHandle<()>> {
        let active = self.active.lock().unwrap().remove(id)?;
        active.stopping.store(true, Ordering::SeqCst);
        if let Some(reason) = reason {
            println!(
                "[RecordingScheduler] Arrêt: {reason} ({})",
                active.recording.title
            );
        }
        active.log(&format!(
            "\n[{}] Arrêt: {}",
            now_display(),
            reason.unwrap_or("fin de la fenêtre programmée")
        ));
        let process = active.state.lock().unwrap().process.clone();
        if let Some(process) = &process {
            process.terminate();
        }
        self.db
            .update_recording_status(id, "completed", None, None, false);

        let this = self.clone();
        Some(tokio::spawn(async move {
            // Attendre la fin effective de FFmpeg avant de clôturer.
            if let Some(process) = process
                && tokio::time::timeout(Duration::from_secs(15), process.wait())
                    .await
                    .is_err()
            {
                process.kill();
            }
            this.finalize(&active, "completed", None).await;
        }))
    }

    /// Fichiers d'un enregistrement : principal, log, parties des relances.
    pub fn files_for(file_path: &str) -> Vec<String> {
        let mut paths = vec![
            file_path.to_string(),
            Path::new(file_path)
                .with_extension("log")
                .to_string_lossy()
                .into_owned(),
        ];
        for attempt in 1.. {
            let part = part_path(file_path, attempt);
            if !Path::new(&part).exists() {
                break;
            }
            paths.push(part);
        }
        // Annexes Plex/Jellyfin des matchs NBA (vignettes, .nfo, remux en cours).
        for extra in crate::services::nba_artwork::sidecar_paths(Path::new(file_path)) {
            if extra.exists() {
                paths.push(extra.to_string_lossy().into_owned());
            }
        }
        let remux = Path::new(file_path).with_extension("cover.mkv");
        if remux.exists() {
            paths.push(remux.to_string_lossy().into_owned());
        }
        paths
    }

    /// Supprime les fichiers d'un enregistrement (API et rotation disque).
    pub fn delete_recording_files(file_path: &str) {
        for path in Self::files_for(file_path) {
            delete_quietly(&path);
        }
    }

    /// Rotation par quota d'octets (RECORDINGS_QUOTA_GB, 0 = désactivée).
    ///
    /// Ne supprime que des enregistrements TERMINÉS connus de la base, du plus
    /// ancien au plus récent, fichiers et ligne ensemble, jamais un actif.
    async fn check_disk_space_and_rotate(&self, dir: &Path) {
        if self.recordings_quota_gb <= 0 {
            return;
        }
        let quota = self.recordings_quota_gb as u64 * 1024 * 1024 * 1024;
        let mut total: u64 = std::fs::read_dir(dir)
            .map(|entries| {
                entries
                    .flatten()
                    .filter_map(|e| e.metadata().ok())
                    .filter(|m| m.is_file())
                    .map(|m| m.len())
                    .sum()
            })
            .unwrap_or(0);
        if total <= quota {
            return;
        }
        println!(
            "[RecordingScheduler] Quota disque dépassé ({} Mo > {} Go) : rotation des enregistrements terminés les plus anciens",
            total / (1024 * 1024),
            self.recordings_quota_gb
        );
        for old in self.db.get_finished_recordings_oldest_first() {
            if total <= quota {
                break;
            }
            let Some(path) = old.file_path.clone() else {
                continue;
            };
            // Jamais un enregistrement encore capturé (statut périmé en base).
            if self.is_capturing(&old.id) {
                continue;
            }
            let freed: u64 = Self::files_for(&path)
                .iter()
                .filter_map(|f| std::fs::metadata(f).ok())
                .map(|m| m.len())
                .sum();
            Self::delete_recording_files(&path);
            self.db.delete_recording(&old.id);
            total = total.saturating_sub(freed);
            println!(
                "[RecordingScheduler] Rotation : \"{}\" supprimé ({} Mo libérés)",
                old.title,
                freed / (1024 * 1024)
            );
        }
    }
}

/// Nom de fichier unique et sûr. Le fragment d'id garantit l'unicité : deux
/// utilisateurs enregistrant le même programme s'écrasaient (FFmpeg -y).
fn file_name_for(recording: &Recording) -> String {
    if recording.source_rule_id.is_some() {
        return readable_file_name(recording);
    }
    // Un caractère hors BMP comptait double (UTF-16) dans l'ancien serveur :
    // même nom de fichier, pour que la reprise retrouve ses parties.
    let mut safe_title = String::new();
    for c in recording.title.chars() {
        if UNSAFE_FILENAME_CHAR.is_match(c.encode_utf8(&mut [0; 4])) {
            safe_title.push_str(if (c as u32) > 0xFFFF { "__" } else { "_" });
        } else {
            safe_title.push(c);
        }
    }
    let date = recording.start_time.as_utc().to_iso().replace(':', "");
    let date = date.split('.').next().unwrap_or("");
    let fragment: String = recording.id.chars().take(8).collect();
    format!("{safe_title}_{date}_{fragment}.mkv")
}

/// Nom lisible pour Plex/Jellyfin (enregistrements automatiques) :
/// « NBA - Celtics @ Lakers (2026-10-22) 01234567.mkv ». Seuls les
/// caractères interdits sous Windows/Linux sont remplacés ; le fragment d'id
/// garde l'unicité.
fn readable_file_name(recording: &Recording) -> String {
    let title: String = recording
        .title
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '-',
            c if c.is_control() => ' ',
            c => c,
        })
        .collect();
    let date = DartDateTime::local_from_utc(recording.start_utc()).to_iso();
    let date = date.get(..10).unwrap_or("");
    let fragment: String = recording.id.chars().take(8).collect();
    format!("{} ({date}) {fragment}.mkv", title.trim())
}

/// Chemin de la n-ième partie (la partie 1 étant le fichier principal).
fn part_path(file_path: &str, attempt: u32) -> String {
    let without_ext = Path::new(file_path).with_extension("");
    format!("{}.part{}.mkv", without_ext.to_string_lossy(), attempt + 1)
}

/// Parties déjà écrites sur disque pour cet enregistrement, dans l'ordre.
fn existing_parts(file_path: &str) -> Vec<String> {
    let mut parts = Vec::new();
    for attempt in 1.. {
        let path = part_path(file_path, attempt);
        if !file_has_data(Some(&path)) {
            break;
        }
        parts.push(path);
    }
    parts
}

fn active_has_data(file_path: &str, extra_parts: &[String]) -> bool {
    file_has_data(Some(file_path)) || extra_parts.iter().any(|p| file_has_data(Some(p)))
}

fn file_has_data(path: Option<&str>) -> bool {
    path.and_then(|p| std::fs::metadata(p).ok())
        .is_some_and(|m| m.is_file() && m.len() > 0)
}

/// Vérifie qu'un fichier peut être créé dans [dir] (fichier sonde supprimé).
fn check_writable(dir: &Path) -> std::io::Result<()> {
    let probe = dir.join(format!(".xtremflow-write-test-{}", std::process::id()));
    std::fs::File::create(&probe)?;
    let _ = std::fs::remove_file(&probe);
    Ok(())
}

fn delete_quietly(path: &str) {
    let _ = std::fs::remove_file(path);
}

/// Espace libre (octets) sur le volume qui porte [path].
#[cfg(unix)]
fn free_disk_bytes(path: &Path) -> Option<u64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let c_path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::statvfs(c_path.as_ptr(), &mut stat) };
    (rc == 0).then(|| stat.f_bavail as u64 * stat.f_frsize as u64)
}

#[cfg(not(unix))]
fn free_disk_bytes(_path: &Path) -> Option<u64> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn recording(title: &str) -> Recording {
        let start = DartDateTime::parse("2026-08-11T18:00:00Z").unwrap();
        Recording {
            id: "0123456789abcdef".into(),
            user_id: "u".into(),
            channel_id: "1".into(),
            stream_url: "/api/live/1.ts".into(),
            title: title.into(),
            start_time: start,
            end_time: start,
            status: "scheduled".into(),
            file_path: None,
            error_reason: None,
            source_rule_id: None,
            playlist_id: None,
            created_at: start,
            updated_at: start,
        }
    }

    #[test]
    fn nom_lisible_pour_les_enregistrements_automatiques() {
        let mut r = recording("NBA - Celtics @ Lakers");
        r.source_rule_id = Some("rule".into());
        let name = file_name_for(&r);
        assert!(name.starts_with("NBA - Celtics @ Lakers ("), "{name}");
        assert!(name.ends_with(") 01234567.mkv"), "{name}");
        r.title = "A/B: C?".into();
        assert!(file_name_for(&r).starts_with("A-B- C- ("));
    }

    #[test]
    fn nom_de_fichier_identique_a_l_ancien_serveur() {
        assert_eq!(
            file_name_for(&recording("Le 20h: édition spéciale")),
            "Le_20h___dition_sp_ciale_2026-08-11T180000_01234567.mkv"
        );
        assert_eq!(
            file_name_for(&recording("Foot ⚽")),
            "Foot___2026-08-11T180000_01234567.mkv"
        );
        assert_eq!(
            file_name_for(&recording("Fun 🎉")),
            "Fun____2026-08-11T180000_01234567.mkv"
        );
    }

    #[test]
    fn chemins_des_parties() {
        assert_eq!(part_path("/rec/a_b.mkv", 1), "/rec/a_b.part2.mkv");
        assert_eq!(part_path("/rec/a_b.mkv", 3), "/rec/a_b.part4.mkv");
    }

    #[test]
    fn correspondance_des_titres() {
        assert!(RecordingScheduler::title_matches(
            "Journal  de 20h",
            "journal de 20h",
            "exact"
        ));
        assert!(!RecordingScheduler::title_matches(
            "Le Journal",
            "journal",
            "exact"
        ));
        assert!(RecordingScheduler::title_matches(
            "Le Journal",
            "journal",
            "contains"
        ));
        assert!(!RecordingScheduler::title_matches(
            "Le Journal",
            "  ",
            "contains"
        ));
    }
}
