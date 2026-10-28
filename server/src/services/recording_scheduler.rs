//! Planificateur des enregistrements TV : démarrage à l'heure, capture
//! FFmpeg (`-c copy`), relances après coupure amont, reprise après
//! redémarrage du serveur, fusion des parties, season passes et rotation
//! disque.

use crate::dart_time::{DartDateTime, display_local, now_display};
use crate::db::AppDatabase;
use crate::models::Recording;
use crate::services::recording_decision::{
    MissCause, OrphanAction, RecordingAction, decide_miss_cause, decide_orphan_action,
    decide_recording_action, ffmpeg_retry_delay,
};
use crate::services::stream_capture;
use crate::util::b64;
use crate::util::log_redactor::redact_url;
use chrono::Utc;
use futures::FutureExt;
use regex::Regex;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::Write;
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};
use tokio::io::AsyncWriteExt;
use tokio::sync::Notify;
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
    /// Coupures consécutives, remises à zéro quand une connexion tient.
    consecutive_failures: u32,
    /// Dernière cause de coupure, pour le motif d'un échec sans données.
    last_cut: Option<String>,
}

/// Pourquoi une capture s'arrête.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum StopReason {
    /// Fin de la fenêtre programmée.
    Window,
    /// Arrêt demandé depuis l'API.
    User,
    /// Arrêt du serveur : la capture sera reprise au redémarrage.
    Shutdown,
    /// Enregistrement supprimé : rien à clôturer ni à convertir.
    Discard,
}

struct ActiveRecording {
    recording: Recording,
    /// Capture en cours (`.ts`), complétée à chaque reconnexion.
    capture_path: String,
    log: Option<RecordingLog>,
    state: Mutex<ActiveState>,
    stop_reason: Mutex<Option<StopReason>>,
    /// Réveille la boucle de capture pour qu'elle s'arrête.
    stop: Notify,
    /// Boucle de capture, qui se charge aussi de la clôture.
    task: Mutex<Option<JoinHandle<()>>>,
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
    /// Instant du passage précédent (`None` avant le premier) : un trou
    /// révèle un serveur arrêté ou bloqué.
    last_tick: Mutex<Option<chrono::DateTime<Utc>>>,
    /// Enregistrements laissés en attente faute de créneau, avec les titres
    /// des captures qui les occupaient.
    waiting: Mutex<HashMap<String, Vec<String>>>,
    /// Captures en cours de clôture (conversion en MKV) : ni actives, ni
    /// orphelines.
    finalizing: Mutex<HashSet<String>>,
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
            last_tick: Mutex::new(None),
            waiting: Mutex::new(HashMap::new()),
            finalizing: Mutex::new(HashSet::new()),
        }
    }

    /// Un enregistrement est-il en cours de capture (ou de clôture) ?
    pub fn is_capturing(&self, id: &str) -> bool {
        self.active.lock().unwrap().contains_key(id) || self.finalizing.lock().unwrap().contains(id)
    }

    /// Coupures consécutives de l'enregistrement actif [id] (`None` si inactif).
    pub fn retry_count_of(&self, id: &str) -> Option<u32> {
        let active = self.active.lock().unwrap().get(id).cloned()?;
        let failures = active.state.lock().unwrap().consecutive_failures;
        Some(failures)
    }

    fn get_active(&self, id: &str) -> Option<Arc<ActiveRecording>> {
        self.active.lock().unwrap().get(id).cloned()
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

    /// Arrêt gracieux pour un `docker stop` : arrête les timers et les
    /// captures en vidant leur tampon sur disque. Les enregistrements restent
    /// « recording » : au redémarrage, la reprise d'orphelins complète le
    /// même `.ts` si la fenêtre est encore ouverte, ou le clôture sinon.
    pub async fn shutdown(self: &Arc<Self>) {
        for timer in self.timers.lock().unwrap().drain(..) {
            timer.abort();
        }
        let ids: Vec<String> = self.active.lock().unwrap().keys().cloned().collect();
        let closings: Vec<JoinHandle<()>> = ids
            .iter()
            .filter_map(|id| self.stop_active_recording(id, StopReason::Shutdown))
            .collect();
        if !closings.is_empty() {
            println!(
                "[RecordingScheduler] Arrêt de {} capture(s), reprise au redémarrage…",
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
        let previous_tick = self.last_tick.lock().unwrap().replace(now);
        if let Some(previous) = previous_tick
            && now - previous > chrono::Duration::minutes(2)
        {
            println!(
                "[RecordingScheduler] AVERTISSEMENT: aucun passage depuis {} ({} min) : serveur suspendu ou bloqué",
                display_local(previous),
                (now - previous).num_minutes()
            );
        }

        // Arrêter les enregistrements actifs dont l'heure de fin est passée.
        let actives: Vec<Arc<ActiveRecording>> =
            self.active.lock().unwrap().values().cloned().collect();
        for active in actives {
            if now > active.recording.end_utc() {
                println!(
                    "[RecordingScheduler] Fin de l'enregistrement : {}",
                    active.recording.title
                );
                self.stop_active_recording(&active.recording.id, StopReason::Window);
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
                    self.waiting.lock().unwrap().remove(&recording.id);
                    println!(
                        "[RecordingScheduler] *** DÉMARRAGE DE L'ENREGISTREMENT : {} ***",
                        recording.title
                    );
                    self.start_recording(recording, false).await;
                }
                RecordingAction::Wait => {
                    // Capacité atteinte, fenêtre encore ouverte : on garde le
                    // statut "scheduled" et on réessaiera au prochain tick.
                    let busy: Vec<String> = self
                        .active
                        .lock()
                        .unwrap()
                        .values()
                        .map(|a| a.recording.title.clone())
                        .collect();
                    self.waiting
                        .lock()
                        .unwrap()
                        .insert(recording.id.clone(), busy);
                    println!(
                        "[RecordingScheduler] Capacité max atteinte ({active_count}/{}), \"{}\" en attente.",
                        self.max_concurrent, recording.title
                    );
                }
                RecordingAction::Fail => {
                    let waited_for = self.waiting.lock().unwrap().remove(&recording.id);
                    let reason = missed_reason(
                        decide_miss_cause(recording.start_utc(), previous_tick, waited_for),
                        now,
                        self.max_concurrent,
                    );
                    println!(
                        "[RecordingScheduler] Enregistrement \"{}\" manqué : {reason}",
                        recording.title
                    );
                    self.db.update_recording_status(
                        &recording.id,
                        "failed",
                        None,
                        Some(&reason),
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
        if current.status != "recording" || self.is_capturing(&current.id) {
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
            OrphanAction::Finish if current.file_path.as_deref().is_some_and(is_capture) => {
                println!(
                    "[RecordingScheduler] Capture interrompue, fenêtre passée : clôture de {}",
                    current.title
                );
                // La conversion en MKV prend du temps : hors du passage.
                self.finalizing.lock().unwrap().insert(current.id.clone());
                let this = self.clone();
                tokio::spawn(async move {
                    let path = current.file_path.clone().unwrap_or_default();
                    let log = RecordingLog::open(&Path::new(&path).with_extension("log"), true);
                    if let Some(log) = &log {
                        log.writeln(&format!(
                            "\n[{}] Serveur redémarré trop tard pour reprendre (fenêtre finie ou presque) : clôture",
                            now_display()
                        ));
                    }
                    this.finalize_capture(&current, &path, log.as_ref(), None)
                        .await;
                    this.finalizing.lock().unwrap().remove(&current.id);
                });
            }
            OrphanAction::Finish => {
                // Ancien format (MKV écrit par FFmpeg) : conservé tel quel.
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
            println!(
                "[RecordingScheduler] ERREUR au démarrage: {}",
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
        // URL relative → serveur local ; absolue → contrôle anti-SSRF refait
        // ici (lignes anciennes, season passes), au plus près de la connexion.
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
        // échouer chaque reconnexion pendant toute la fenêtre : on le signale
        // tout de suite.
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

        let capture_path = capture_path_for(&dir, &recording, resume);
        if !resume {
            // Reste d'une capture précédente du même enregistrement.
            delete_quietly(&capture_path);
        }
        let log_path = Path::new(&capture_path).with_extension("log");
        // Une reprise complète le log existant au lieu de l'écraser.
        let log = RecordingLog::open(&log_path, resume);
        let active = Arc::new(ActiveRecording {
            capture_path: capture_path.clone(),
            log,
            state: Mutex::new(ActiveState {
                consecutive_failures: 0,
                last_cut: None,
            }),
            stop_reason: Mutex::new(None),
            stop: Notify::new(),
            task: Mutex::new(None),
            recording,
        });
        if resume {
            active.log(&format!(
                "\n[{}] Reprise après interruption du serveur : suite ajoutée au même fichier",
                now_display()
            ));
        } else {
            active.log(&format!(
                "[{}] Démarrage: {}",
                now_display(),
                active.recording.title
            ));
            active.log(&format!("Capture: {capture_path}"));
        }

        self.active
            .lock()
            .unwrap()
            .insert(active.recording.id.clone(), active.clone());
        // Chemin du fichier en base : la capture en cours est lisible.
        self.db.update_recording_status(
            &active.recording.id,
            "recording",
            Some(&capture_path),
            None,
            false,
        );
        let task = tokio::spawn(self.clone().run_capture(active.clone()));
        *active.task.lock().unwrap() = Some(task);
        Ok(())
    }

    /// Boucle de capture : recopie le flux dans le `.ts`, se reconnecte après
    /// chaque coupure tant que la fenêtre est ouverte, puis clôture.
    async fn run_capture(self: Arc<Self>, active: Arc<ActiveRecording>) {
        let end = active.recording.end_utc();
        let url = if active.recording.stream_url.starts_with('/') {
            // Le proxy local gère le quota de connexions du fournisseur.
            format!("http://127.0.0.1:8089{}", active.recording.stream_url)
        } else {
            active.recording.stream_url.clone()
        };
        active.log(&format!("URL: {}", redact_url(&url)));
        let sink: stream_capture::LogSink = {
            let active = active.clone();
            Arc::new(move |line: &str| active.log(line))
        };
        let ffmpeg = resolve_ffmpeg_path();

        let file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&active.capture_path)
            .await;
        let mut out = match file {
            Ok(f) => tokio::io::BufWriter::with_capacity(256 * 1024, f),
            Err(e) => {
                active.state.lock().unwrap().last_cut =
                    Some(format!("fichier de capture impossible à créer : {e}"));
                self.end_capture(&active).await;
                return;
            }
        };

        loop {
            if active.stop_reason.lock().unwrap().is_some() || Utc::now() >= end {
                break;
            }
            let stop = stop_signal(&active, end);
            tokio::pin!(stop);
            let launched = Instant::now();
            let mut bytes = 0u64;
            let opened = tokio::select! {
                biased;
                _ = stop.as_mut() => break,
                opened = stream_capture::open(&self.http, &url, &ffmpeg, sink.clone()) => opened,
            };
            let cut = match opened {
                Ok(stream) => {
                    if active.state.lock().unwrap().consecutive_failures > 0 {
                        active.log(&format!("[{}] Connexion au flux rétablie", now_display()));
                    }
                    match stream_capture::pump(
                        stream,
                        &mut out,
                        stream_capture::STALL_TIMEOUT,
                        &mut bytes,
                        &mut stop,
                    )
                    .await
                    {
                        stream_capture::PumpEnd::Stop => break,
                        stream_capture::PumpEnd::Cut(reason) => reason,
                    }
                }
                Err(reason) => reason,
            };
            let _ = out.flush().await;

            let lasted = launched.elapsed();
            let failures = {
                let mut state = active.state.lock().unwrap();
                // Une connexion restée saine repart du délai minimal.
                if lasted > Duration::from_secs(120) && bytes > 0 {
                    state.consecutive_failures = 0;
                }
                state.consecutive_failures += 1;
                state.last_cut = Some(cut.clone());
                state.consecutive_failures
            };
            let delay = ffmpeg_retry_delay(failures);
            let message = format!(
                "Flux coupé ({cut}) après {}s et {} Mo — reconnexion dans {}s (échec consécutif n°{failures})",
                lasted.as_secs(),
                bytes / (1024 * 1024),
                delay.as_secs(),
            );
            println!("[RecordingScheduler] {}: {message}", active.recording.title);
            active.log(&format!("[{}] {message}", now_display()));
            // Laisser la source respirer : sur les comptes limités en
            // connexions simultanées, rouvrir immédiatement se fait refuser.
            tokio::select! {
                biased;
                _ = stop.as_mut() => break,
                _ = tokio::time::sleep(delay) => {}
            }
        }
        let _ = out.flush().await;
        drop(out);
        self.end_capture(&active).await;
    }

    /// Fin de la boucle de capture : clôture, sauf à l'arrêt du serveur où
    /// l'enregistrement reste « recording » pour être repris au redémarrage.
    async fn end_capture(&self, active: &Arc<ActiveRecording>) {
        let id = active.recording.id.clone();
        // Marqué « en clôture » AVANT de quitter la liste des actifs : le
        // planificateur le prendrait sinon pour un orphelin.
        self.finalizing.lock().unwrap().insert(id.clone());
        {
            let mut map = self.active.lock().unwrap();
            if map.get(&id).is_some_and(|a| Arc::ptr_eq(a, active)) {
                map.remove(&id);
            }
        }
        let reason = *active.stop_reason.lock().unwrap();
        if reason == Some(StopReason::Shutdown) {
            active.log(&format!(
                "\n[{}] Arrêt du serveur : la capture reprendra au redémarrage si la fenêtre est encore ouverte",
                now_display()
            ));
            if let Some(log) = &active.log {
                log.close();
            }
            self.finalizing.lock().unwrap().remove(&id);
            return;
        }
        if reason == Some(StopReason::Discard) {
            if let Some(log) = &active.log {
                log.close();
            }
            delete_quietly(&active.capture_path);
            self.finalizing.lock().unwrap().remove(&id);
            return;
        }
        let last_cut = active.state.lock().unwrap().last_cut.clone();
        self.finalize_capture(
            &active.recording,
            &active.capture_path,
            active.log.as_ref(),
            last_cut,
        )
        .await;
        self.finalizing.lock().unwrap().remove(&id);
    }

    /// Clôture d'une capture `.ts` : conversion en MKV, statut, vignettes.
    async fn finalize_capture(
        &self,
        recording: &Recording,
        capture_path: &str,
        log: Option<&RecordingLog>,
        last_cut: Option<String>,
    ) {
        let write = |line: &str| {
            if let Some(log) = log {
                log.writeln(line);
            }
        };
        if !file_has_data(Some(capture_path)) {
            delete_quietly(capture_path);
            let reason = match last_cut {
                Some(cut) => format!("Aucune donnée reçue du flux ({cut}). Voir logs."),
                None => "Aucune donnée reçue du flux. Voir logs.".to_string(),
            };
            write(&format!("\n[{}] Échec : {reason}", now_display()));
            if let Some(log) = log {
                log.close();
            }
            self.db
                .update_recording_status(&recording.id, "failed", None, Some(&reason), false);
            return;
        }

        let mkv = Path::new(capture_path).with_extension("mkv");
        let (path, note) = if mkv.exists() {
            // Fichier d'une capture antérieure (ancien format) : ne jamais
            // l'écraser, la suite reste en `.ts`.
            write("Un fichier .mkv du même nom existe déjà : capture conservée en .ts.");
            (capture_path.to_string(), None)
        } else {
            write(&format!("\n[{}] Conversion en MKV…", now_display()));
            match remux_to_mkv(Path::new(capture_path), &mkv, &write).await {
                Ok(()) => {
                    write("Conversion terminée.");
                    (mkv.to_string_lossy().into_owned(), None)
                }
                Err(e) => {
                    write(&format!(
                        "Conversion impossible ({e}) : capture conservée en .ts."
                    ));
                    (
                        capture_path.to_string(),
                        Some(
                            "Conversion en MKV impossible : fichier conservé en .ts (lisible tel quel)",
                        ),
                    )
                }
            }
        };
        write(&format!(
            "\n[{}] Enregistrement clôturé avec le statut \"completed\"",
            now_display()
        ));
        if let Some(log) = log {
            log.close();
        }
        self.db
            .update_recording_status(&recording.id, "completed", Some(&path), note, false);
        // Matchs NBA automatiques : vignettes Plex/Jellyfin, .nfo et pochette
        // intégrée au MKV.
        if recording.source_rule_id.is_some()
            && let Some(game) = self
                .db
                .get_nba_game_by_recording(&recording.id)
                .or_else(|| crate::services::nba_artwork::game_from_recording(recording))
        {
            crate::services::nba_artwork::finish_recording(
                &self.http,
                Path::new(&recordings_dir_path()),
                &game,
                Path::new(&path),
                &recording.title,
                &resolve_ffmpeg_path(),
            )
            .await;
        }
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
        self.stop_active_recording(id, StopReason::User);
        true
    }

    /// Abandonne la capture de [id] sans la clôturer (suppression).
    pub fn discard_recording(&self, id: &str) {
        self.stop_active_recording(id, StopReason::Discard);
    }

    /// Demande l'arrêt de l'enregistrement actif [id] et renvoie sa tâche de
    /// capture (qui se charge de la clôture), ou `None` s'il n'est pas actif.
    fn stop_active_recording(&self, id: &str, reason: StopReason) -> Option<JoinHandle<()>> {
        let active = self.get_active(id)?;
        {
            let mut current = active.stop_reason.lock().unwrap();
            if current.is_none() {
                *current = Some(reason);
                active.log(&format!(
                    "\n[{}] Arrêt: {}",
                    now_display(),
                    match reason {
                        StopReason::Window => "fin de la fenêtre programmée",
                        StopReason::User => "demandé par l'utilisateur",
                        StopReason::Shutdown => "arrêt du serveur",
                        StopReason::Discard => "enregistrement supprimé",
                    }
                ));
            }
        }
        active.stop.notify_one();
        active.task.lock().unwrap().take()
    }

    /// Fichiers d'un enregistrement : principal, capture `.ts` ou MKV
    /// converti, log, parties de l'ancien format.
    pub fn files_for(file_path: &str) -> Vec<String> {
        let mut paths = vec![file_path.to_string()];
        for ext in ["log", "ts", "mkv", "remux.mkv"] {
            let other = Path::new(file_path).with_extension(ext);
            if other.exists() && other != Path::new(file_path) {
                paths.push(other.to_string_lossy().into_owned());
            }
        }
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

/// Motif affiché d'un enregistrement jamais démarré.
fn missed_reason(cause: MissCause, now: chrono::DateTime<Utc>, max_concurrent: usize) -> String {
    let at = |dt| {
        DartDateTime::local_from_utc(dt)
            .naive
            .format("%d/%m à %H:%M")
            .to_string()
    };
    match cause {
        MissCause::ServerDown => format!(
            "Serveur arrêté pendant toute la plage prévue (redémarré le {})",
            at(now)
        ),
        MissCause::Stalled(since) => format!(
            "Serveur suspendu ou bloqué pendant toute la plage prévue (aucune activité du {} au {})",
            at(since),
            at(now)
        ),
        MissCause::Capacity(busy) if busy.is_empty() => format!(
            "Aucun enregistrement simultané autorisé (MAX_CONCURRENT_RECORDINGS={max_concurrent})"
        ),
        MissCause::Capacity(busy) => format!(
            "Enregistrements simultanés déjà au maximum ({max_concurrent}) pendant toute la plage : {}",
            busy.iter()
                .map(|t| format!("« {t} »"))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        MissCause::Unknown => "Heure de fin dépassée avant le démarrage".into(),
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

/// Capture `.ts` du nouveau format (le MKV converti n'en est pas une).
fn is_capture(path: &str) -> bool {
    Path::new(path)
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("ts"))
}

/// Fichier de capture : celui d'une capture interrompue s'il faut la
/// reprendre, sinon le nom final avec l'extension `.ts`.
fn capture_path_for(dir: &Path, recording: &Recording, resume: bool) -> String {
    if resume
        && let Some(previous) = recording.file_path.as_deref()
        && is_capture(previous)
        && Path::new(previous).exists()
    {
        return previous.to_string();
    }
    dir.join(file_name_for(recording))
        .with_extension("ts")
        .to_string_lossy()
        .into_owned()
}

/// Réveil de la boucle de capture : arrêt demandé ou fin de la fenêtre.
async fn stop_signal(active: &ActiveRecording, end: chrono::DateTime<Utc>) {
    let wait = (end - Utc::now()).to_std().unwrap_or_default();
    tokio::select! {
        _ = active.stop.notified() => {}
        _ = tokio::time::sleep(wait) => {}
    }
}

/// Convertit la capture en MKV sans réencodage. FFmpeg recale les sauts
/// d'horloge du flux (« timestamp discontinuity ») sur tout le fichier.
///
/// Le `.ts` n'est supprimé que si le MKV paraît complet : un MKV nettement
/// plus petit que sa source trahirait une conversion tronquée.
async fn remux_to_mkv(ts: &Path, mkv: &Path, log: &(dyn Fn(&str) + Sync)) -> Result<(), String> {
    let tmp = mkv.with_extension("remux.mkv");
    let output = tokio::process::Command::new(resolve_ffmpeg_path())
        .args(["-hide_banner", "-nostats", "-loglevel", "warning"])
        .args(["-fflags", "+genpts+discardcorrupt", "-i"])
        .arg(ts)
        // Vidéo et audio seulement : télétexte et données (SCTE-35…) des
        // flux TV ne tiennent pas dans un MKV et feraient échouer la copie.
        .args(["-map", "0:v?", "-map", "0:a?", "-c", "copy", "-y"])
        .arg(&tmp)
        .stdin(Stdio::null())
        .output()
        .await
        .map_err(|e| format!("FFmpeg impossible à lancer : {e}"))?;
    let stderr = String::from_utf8_lossy(&output.stderr);
    let lines: Vec<&str> = stderr.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.len() > 20 {
        log(&format!(
            "({} avertissements FFmpeg, 20 derniers :)",
            lines.len()
        ));
    }
    for line in lines.iter().skip(lines.len().saturating_sub(20)) {
        log(line);
    }
    let size = |p: &Path| std::fs::metadata(p).map(|m| m.len()).unwrap_or(0);
    let (ts_size, mkv_size) = (size(ts), size(&tmp));
    let code = output.status.code().unwrap_or(-1);
    let problem = if code != 0 {
        Some(format!("code {code}"))
    } else if !conversion_complete(ts_size, mkv_size) {
        Some(format!(
            "MKV de {} Mo pour {} Mo capturés",
            mkv_size / (1024 * 1024),
            ts_size / (1024 * 1024)
        ))
    } else {
        None
    };
    if let Some(problem) = problem {
        delete_quietly(&tmp.to_string_lossy());
        return Err(problem);
    }
    std::fs::rename(&tmp, mkv).map_err(|e| e.to_string())?;
    delete_quietly(&ts.to_string_lossy());
    Ok(())
}

/// Le MKV garde l'essentiel du `.ts` : l'en-tête MPEG-TS et les flux
/// écartés (télétexte, données) pèsent quelques pour cent, pas plus.
fn conversion_complete(ts_size: u64, mkv_size: u64) -> bool {
    mkv_size > 0 && mkv_size as f64 >= ts_size as f64 * 0.85
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
    fn capture_ts_puis_mkv() {
        let dir = std::env::temp_dir().join(format!("xf-capture-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut rec = recording("NBA - Heat @ Hornets");
        rec.source_rule_id = Some("r".into());
        let fresh = capture_path_for(&dir, &rec, false);
        assert!(fresh.ends_with(".ts") && is_capture(&fresh));
        assert!(!is_capture("/rec/x.mkv"));

        // Reprise : la capture existante est complétée, pas recréée.
        let previous = dir.join("ancienne capture.ts");
        std::fs::write(&previous, b"x").unwrap();
        rec.file_path = Some(previous.to_string_lossy().into_owned());
        assert_eq!(
            capture_path_for(&dir, &rec, true),
            rec.file_path.clone().unwrap()
        );
        assert_eq!(capture_path_for(&dir, &rec, false), fresh);

        // Suppression : capture et MKV converti partent ensemble.
        let mkv = previous.with_extension("mkv");
        std::fs::write(&mkv, b"y").unwrap();
        let files = RecordingScheduler::files_for(&mkv.to_string_lossy());
        assert!(files.contains(&previous.to_string_lossy().into_owned()));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn conversion_complete_ou_tronquee() {
        assert!(conversion_complete(1000, 955));
        assert!(!conversion_complete(1000, 500));
        assert!(!conversion_complete(1000, 0));
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
