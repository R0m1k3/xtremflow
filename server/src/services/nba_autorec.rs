//! Enregistrement automatique des matchs NBA diffusés en direct sur les
//! chaînes beIN Sports françaises.
//!
//! Deux sources, une réconciliation :
//! - le calendrier NBA (ESPN) annonce les matchs des semaines à l'avance,
//!   avec leur coup d'envoi exact ;
//! - l'EPG des chaînes beIN FR (≈ 48 h devant) dit quelle chaîne diffuse
//!   quel match, et quand.
//!
//! POURQUOI le coup d'envoi : un match n'a qu'une diffusion en direct, celle
//! qui commence avec lui. Toute autre occurrence du même match dans le guide
//! (le lendemain matin, l'après-midi…) est une rediffusion. Ce critère ne
//! dépend ni des titres, très variables, ni des drapeaux XMLTV, rarement
//! renseignés ; ceux-ci ne servent que de signaux d'appoint.

use crate::api::epg::EpgApi;
use crate::dart_time::{DartDateTime, utc_iso};
use crate::db::AppDatabase;
use crate::models::{AutoRule, NbaGame, PlaylistConfig, Recording};
use crate::services::nba_artwork;
use crate::services::nba_schedule;
use crate::services::nba_teams::{self, Team, normalize};
use crate::services::recording_scheduler::{RecordingScheduler, recordings_dir_path};
use chrono::{DateTime, Duration, Utc};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;

/// Fenêtre autour du coup d'envoi dans laquelle doit démarrer la diffusion
/// en direct (avant-match compris).
const WINDOW_BEFORE: i64 = 45;
const WINDOW_AFTER: i64 = 20;
/// Durée minimale couverte après le coup d'envoi (match + prolongations
/// usuelles), même si l'EPG annonce un créneau plus court.
const MIN_GAME_MINUTES: i64 = 150;
/// Score minimal pour considérer un programme comme la diffusion en direct.
const MIN_CONFIDENCE: i64 = 40;
/// Jours de calendrier chargés devant.
const SCHEDULE_DAYS: i64 = 21;

/// Programme EPG d'une chaîne surveillée.
#[derive(Clone, Debug, PartialEq)]
pub struct EpgProgramme {
    pub channel_id: String,
    pub channel_label: String,
    pub title: String,
    pub description: String,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    pub is_live: bool,
    pub previously_shown: bool,
}

impl EpgProgramme {
    /// Depuis le JSON de `EpgApi::programmes`. Les drapeaux sont optionnels.
    pub fn from_json(channel_id: &str, channel_label: &str, v: &Value) -> Option<Self> {
        let date = |k: &str| {
            v.get(k)
                .and_then(Value::as_str)
                .and_then(DartDateTime::parse)
                .map(DartDateTime::to_utc)
        };
        let text = |k: &str| {
            v.get(k)
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string()
        };
        let flag = |k: &str| v.get(k).and_then(Value::as_bool).unwrap_or(false);
        let sub = text("sub_title");
        let mut description = text("description");
        if !sub.is_empty() {
            description = format!("{sub} {description}");
        }
        Some(Self {
            channel_id: channel_id.to_string(),
            channel_label: channel_label.to_string(),
            title: text("title"),
            description,
            start: date("start")?,
            end: date("end")?,
            is_live: flag("is_live"),
            previously_shown: flag("previously_shown"),
        })
    }

    fn text(&self) -> String {
        format!("{} {}", self.title, self.description)
    }
}

/// Mots qui signalent une rediffusion ou un programme autour du match.
const RERUN_WORDS: &[&str] = &[
    "rediffusion",
    "rediff",
    "redif",
    "differe",
    "en differe",
    "replay",
    "best of",
    "resume",
    "resumes",
    "highlights",
    "temps forts",
    "magazine",
    "le mag",
    "extra",
    "inside the nba",
    "previously",
];
const LIVE_WORDS: &[&str] = &["direct", "en direct", "live"];

fn contains_words(hay: &str, words: &[&str]) -> bool {
    let padded = format!(" {hay} ");
    words.iter().any(|w| padded.contains(&format!(" {w} ")))
}

/// Diffusion retenue pour un match.
#[derive(Clone, Debug, PartialEq)]
pub struct LiveBroadcast {
    pub programme: EpgProgramme,
    pub confidence: i64,
}

/// Cherche la diffusion en direct du match `home`/`away` (abréviations ESPN)
/// prévu à `tipoff`. `other_games_nearby` : d'autres matchs commencent à
/// moins d'une heure — un programme « NBA » sans équipes lisibles est alors
/// ambigu et refusé.
pub fn find_live_broadcast(
    home: &str,
    away: &str,
    tipoff: DateTime<Utc>,
    other_games_nearby: bool,
    programmes: &[EpgProgramme],
) -> Option<LiveBroadcast> {
    let wanted: Vec<&str> = [home, away]
        .iter()
        .filter_map(|a| nba_teams::by_abbr(a).map(|t| t.abbr))
        .collect();
    let lo = tipoff - Duration::minutes(WINDOW_BEFORE);
    let hi = tipoff + Duration::minutes(WINDOW_AFTER);
    programmes
        .iter()
        .filter(|p| p.start >= lo && p.start <= hi && p.end > p.start)
        .filter_map(|p| {
            let text = p.text();
            let norm = normalize(&text);
            if p.previously_shown || contains_words(&norm, RERUN_WORDS) {
                return None;
            }
            let teams: Vec<&'static Team> = nba_teams::extract_teams(&text);
            // Une équipe citée qui n'est pas de ce match : c'est un autre match.
            if teams.iter().any(|t| !wanted.contains(&t.abbr)) {
                return None;
            }
            let mut score = match teams.len() {
                2.. => 60,
                1 => 30,
                _ if nba_teams::mentions_nba(&text) && !other_games_nearby => 10,
                _ => return None,
            };
            let gap = (p.start - tipoff).num_minutes().abs();
            score += if gap <= 20 { 30 } else { 15 };
            if p.is_live || contains_words(&norm, LIVE_WORDS) {
                score += 10;
            }
            (score >= MIN_CONFIDENCE).then(|| LiveBroadcast {
                programme: p.clone(),
                confidence: score,
            })
        })
        .max_by_key(|b| {
            (
                b.confidence,
                -(b.programme.start - tipoff).num_minutes().abs(),
            )
        })
}

/// Le match passe-t-il le filtre d'équipes de la règle (vide = tous) ?
pub fn passes_team_filter(rule: &AutoRule, home: &str, away: &str) -> bool {
    if rule.team_filter.is_empty() {
        return true;
    }
    let keys = |abbr: &str| -> Vec<String> {
        match nba_teams::by_abbr(abbr) {
            Some(t) => vec![
                normalize(t.abbr),
                normalize(t.nickname),
                normalize(&t.full_name()),
                normalize(t.city),
            ],
            None => vec![normalize(abbr)],
        }
    };
    let game_keys: Vec<String> = keys(home).into_iter().chain(keys(away)).collect();
    rule.team_filter
        .iter()
        .map(|f| normalize(f))
        .any(|f| game_keys.contains(&f))
}

/// L'utilisateur veut-il ce match ?
pub fn wants(rule: &AutoRule, game: &NbaGame) -> bool {
    match game.decision.as_str() {
        "accepted" => true,
        "refused" => false,
        _ => {
            rule.default_decision == "auto"
                && passes_team_filter(rule, &game.home_tri, &game.away_tri)
        }
    }
}

/// Fenêtre d'enregistrement : marge avant, au moins `MIN_GAME_MINUTES`
/// après le coup d'envoi, marge après.
pub fn recording_window(
    rule: &AutoRule,
    tipoff: DateTime<Utc>,
    b: &EpgProgramme,
) -> (DateTime<Utc>, DateTime<Utc>) {
    let start = b.start.min(tipoff) - Duration::minutes(rule.pad_before_min.max(0));
    let end = b.end.max(tipoff + Duration::minutes(MIN_GAME_MINUTES))
        + Duration::minutes(rule.pad_after_min.max(0));
    (start, end)
}

/// Titre lisible dans Plex/Jellyfin : « NBA - Celtics @ Lakers ».
pub fn recording_title(game: &NbaGame) -> String {
    let nick = |abbr: &str, fallback: &str| {
        nba_teams::by_abbr(abbr)
            .map(|t| t.nickname.to_string())
            .unwrap_or_else(|| fallback.to_string())
    };
    format!(
        "NBA - {} @ {}",
        nick(&game.away_tri, &game.away),
        nick(&game.home_tri, &game.home)
    )
}

/// Ce que la réconciliation doit faire pour un match.
#[derive(Debug, PartialEq)]
pub enum Action {
    /// Rien à changer à l'enregistrement ; seulement l'état affiché.
    Status(&'static str),
    Create {
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    },
    Realign {
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    },
    /// Changement de chaîne : supprimer l'enregistrement planifié et recréer.
    Recreate {
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    },
    /// Refus de l'utilisateur : supprimer l'enregistrement encore planifié.
    Cancel,
}

/// Décision pure, testable sans base ni réseau.
pub fn plan_action(
    rule: &AutoRule,
    game: &NbaGame,
    tipoff: DateTime<Utc>,
    live: Option<&LiveBroadcast>,
    recording: Option<&Recording>,
    now: DateTime<Utc>,
) -> Action {
    // Un enregistrement lancé ou terminé n'est plus remis en cause.
    if let Some(rec) = recording {
        match rec.status.as_str() {
            "recording" => return Action::Status("scheduled"),
            "completed" => return Action::Status("recorded"),
            "failed" => return Action::Status("missed"),
            _ => {}
        }
    }
    let scheduled = recording.filter(|r| r.status == "scheduled");
    if !wants(rule, game) {
        return match scheduled {
            Some(_) => Action::Cancel,
            None if live.is_some() => Action::Status("confirmed"),
            None => Action::Status(past_or(game, tipoff, now, "provisional")),
        };
    }
    let Some(live) = live else {
        // EPG muet (pas encore publié, ou programme disparu) : on garde un
        // enregistrement déjà planifié plutôt que de rater le match.
        return match scheduled {
            Some(_) => Action::Status("scheduled"),
            None => Action::Status(past_or(game, tipoff, now, "provisional")),
        };
    };
    let (start, end) = recording_window(rule, tipoff, &live.programme);
    if end <= now {
        return Action::Status("missed");
    }
    match scheduled {
        None => Action::Create { start, end },
        Some(rec) if rec.channel_id != live.programme.channel_id => Action::Recreate { start, end },
        Some(rec) => {
            let moved = (rec.start_utc() - start).num_seconds().abs() > 60
                || (rec.end_utc() - end).num_seconds().abs() > 60;
            if moved {
                Action::Realign { start, end }
            } else {
                Action::Status("scheduled")
            }
        }
    }
}

/// Match passé sans diffusion trouvée : pas sur beIN FR.
fn past_or(
    game: &NbaGame,
    tipoff: DateTime<Utc>,
    now: DateTime<Utc>,
    otherwise: &'static str,
) -> &'static str {
    if now > tipoff + Duration::hours(3) {
        if game.status == "confirmed" {
            "missed"
        } else {
            "not_on_bein"
        }
    } else {
        otherwise
    }
}

/// Créneaux simultanés déjà pris sur [start, end].
fn overlapping(recordings: &[Recording], start: DateTime<Utc>, end: DateTime<Utc>) -> usize {
    recordings
        .iter()
        .filter(|r| matches!(r.status.as_str(), "scheduled" | "recording"))
        .filter(|r| r.start_utc() < end && r.end_utc() > start)
        .count()
}

/// Règle en pause : supprime ses enregistrements encore planifiés (le
/// planificateur les capturerait sinon) et remet les matchs à l'état
/// « confirmé » ou « prévu ». Un enregistrement déjà en cours n'est pas coupé.
pub fn suspend_rule(db: &AppDatabase, rule: &AutoRule) {
    let now = Utc::now();
    let games = db.get_nba_games(
        &rule.id,
        now - Duration::hours(6),
        now + Duration::days(SCHEDULE_DAYS * 3),
    );
    for game in games {
        let Some(rec_id) = game.recording_id.as_deref() else {
            continue;
        };
        let scheduled = db
            .get_recording_by_id(rec_id)
            .is_none_or(|r| r.status == "scheduled");
        if !scheduled {
            continue;
        }
        db.delete_recording(rec_id);
        let mut next = game.clone();
        next.recording_id = None;
        next.conflict = false;
        next.status = if game.channel_id.is_some() {
            "confirmed"
        } else {
            "provisional"
        }
        .into();
        if let Err(e) = db.update_nba_game_state(&next) {
            println!("[NBA] Match {} non remis en attente : {e}", game.game_id);
        }
    }
}

/// Service : calendrier quotidien + réconciliation toutes les 30 minutes.
pub struct NbaAutoRecorder {
    db: Arc<AppDatabase>,
    http: reqwest::Client,
    epg: EpgApi,
    scheduler: Arc<RecordingScheduler>,
    timers: Mutex<Vec<JoinHandle<()>>>,
    /// Une réconciliation à la fois (timer et API peuvent se croiser).
    running: tokio::sync::Mutex<()>,
}

impl NbaAutoRecorder {
    pub fn new(
        db: Arc<AppDatabase>,
        http: reqwest::Client,
        epg: EpgApi,
        scheduler: Arc<RecordingScheduler>,
    ) -> Self {
        Self {
            db,
            http,
            epg,
            scheduler,
            timers: Mutex::new(Vec::new()),
            running: tokio::sync::Mutex::new(()),
        }
    }

    pub fn start(self: &Arc<Self>) {
        let mut timers = self.timers.lock().unwrap();
        let this = self.clone();
        timers.push(tokio::spawn(async move {
            // Laisser démarrer le serveur et les index EPG.
            tokio::time::sleep(std::time::Duration::from_secs(45)).await;
            let mut tick = 0u64;
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(30 * 60));
            loop {
                interval.tick().await;
                // Calendrier au démarrage puis toutes les 12 h (24 × 30 min).
                if tick.is_multiple_of(24) {
                    this.refresh_schedules().await;
                }
                this.reconcile_all().await;
                tick += 1;
            }
        }));
    }

    /// Recharge le calendrier pour toutes les règles actives.
    pub async fn refresh_schedules(&self) {
        let rules = self.db.get_enabled_auto_rules();
        if rules.is_empty() {
            return;
        }
        // Journées ESPN en heure US : commencer la veille couvre les matchs
        // de la nuit européenne.
        let first = (Utc::now() - Duration::days(1)).date_naive();
        let games = nba_schedule::fetch_days(&self.http, first, SCHEDULE_DAYS + 1).await;
        println!(
            "[NBA] Calendrier : {} match(s) sur {SCHEDULE_DAYS} jours",
            games.len()
        );
        for rule in rules {
            self.refresh_rule_with(&rule, &games);
        }
    }

    /// Calendrier d'une seule règle (création, réactivation).
    pub async fn refresh_rule(&self, rule: &AutoRule) {
        let first = (Utc::now() - Duration::days(1)).date_naive();
        let games = nba_schedule::fetch_days(&self.http, first, SCHEDULE_DAYS + 1).await;
        self.refresh_rule_with(rule, &games);
    }

    fn refresh_rule_with(&self, rule: &AutoRule, games: &[crate::models::ScheduledGame]) {
        for g in games {
            if let Err(e) = self.db.upsert_scheduled_game(&rule.id, g) {
                println!("[NBA] Match {} non enregistré : {e}", g.game_id);
            }
        }
    }

    pub async fn reconcile_all(&self) {
        for rule in self.db.get_enabled_auto_rules() {
            self.reconcile(&rule).await;
            self.apply_retention(&rule);
        }
    }

    /// Supprime les matchs enregistrés par la règle depuis plus de
    /// `keep_days` jours (fichiers, annexes et ligne).
    fn apply_retention(&self, rule: &AutoRule) {
        let Some(days) = rule.keep_days.filter(|d| *d > 0) else {
            return;
        };
        let limit = Utc::now() - Duration::days(days);
        for rec in self.db.get_user_recordings(&rule.user_id) {
            let expired = rec.source_rule_id.as_deref() == Some(rule.id.as_str())
                && matches!(rec.status.as_str(), "completed" | "failed" | "cancelled")
                && rec.end_utc() < limit;
            if !expired {
                continue;
            }
            if let Some(path) = &rec.file_path {
                RecordingScheduler::delete_recording_files(path);
            }
            self.db.delete_recording(&rec.id);
            println!("[NBA] Rétention : « {} » supprimé", rec.title);
        }
    }

    fn playlist_for(&self, user_id: &str) -> Option<PlaylistConfig> {
        self.db
            .get_playlists(user_id)
            .into_iter()
            .next()
            .map(|p| PlaylistConfig {
                dns: p.server_url,
                username: p.username,
                password: p.password,
            })
    }

    /// Programmes EPG de toutes les chaînes surveillées par la règle.
    async fn watched_programmes(
        &self,
        rule: &AutoRule,
        playlist: &PlaylistConfig,
    ) -> Vec<EpgProgramme> {
        let mut out = Vec::new();
        for channel_id in &rule.channel_ids {
            let label = self
                .epg
                .channel_name(playlist, channel_id)
                .await
                .map(|n| {
                    crate::services::bein_channels::classify(channel_id, &n, "")
                        .map(|c| c.label)
                        .unwrap_or(n)
                })
                .unwrap_or_else(|| format!("Chaîne {channel_id}"));
            for v in self.epg.programmes(playlist, channel_id).await {
                if let Some(p) = EpgProgramme::from_json(channel_id, &label, &v) {
                    out.push(p);
                }
            }
        }
        out
    }

    /// Réconcilie calendrier, EPG et enregistrements d'une règle.
    pub async fn reconcile(&self, rule: &AutoRule) {
        let _guard = self.running.lock().await;
        // État relu en base : l'appelant peut tenir une copie antérieure à
        // une mise en pause.
        let Some(rule) = self.db.get_auto_rule(&rule.id) else {
            return;
        };
        let rule = &rule;
        if !rule.enabled {
            suspend_rule(&self.db, rule);
            return;
        }
        let now = Utc::now();
        let games = self.db.get_nba_games(
            &rule.id,
            now - Duration::hours(6),
            now + Duration::days(SCHEDULE_DAYS),
        );
        if games.is_empty() {
            return;
        }
        let Some(playlist) = self.playlist_for(&rule.user_id) else {
            println!("[NBA] Règle {} : aucune playlist", rule.id);
            return;
        };
        // L'EPG ne couvre que quelques jours : inutile de le charger pour
        // des matchs lointains seulement.
        let needs_epg = games.iter().any(|g| {
            DartDateTime::parse(&g.tipoff_utc).is_some_and(|t| t.to_utc() < now + Duration::days(4))
        });
        let programmes = if needs_epg && !rule.channel_ids.is_empty() {
            self.watched_programmes(rule, &playlist).await
        } else {
            Vec::new()
        };
        let tipoffs: HashMap<String, DateTime<Utc>> = games
            .iter()
            .filter_map(|g| {
                DartDateTime::parse(&g.tipoff_utc).map(|t| (g.game_id.clone(), t.to_utc()))
            })
            .collect();

        let mut created = 0;
        for game in games {
            let Some(&tipoff) = tipoffs.get(&game.game_id) else {
                continue;
            };
            let nearby = tipoffs
                .iter()
                .any(|(id, t)| *id != game.game_id && (*t - tipoff).num_minutes().abs() < 60);
            let live =
                find_live_broadcast(&game.home_tri, &game.away_tri, tipoff, nearby, &programmes);
            let recording = game
                .recording_id
                .as_deref()
                .and_then(|id| self.db.get_recording_by_id(id));
            let action = plan_action(rule, &game, tipoff, live.as_ref(), recording.as_ref(), now);
            let mut next = game.clone();
            if let Some(l) = &live {
                next.channel_id = Some(l.programme.channel_id.clone());
                next.channel_name = Some(l.programme.channel_label.clone());
                next.epg_title = Some(l.programme.title.clone());
                next.epg_start = Some(utc_iso(l.programme.start));
                next.epg_end = Some(utc_iso(l.programme.end));
                next.confidence = Some(l.confidence);
            }
            next.conflict = false;
            match action {
                Action::Status(s) => next.status = s.to_string(),
                Action::Cancel => {
                    if let Some(rec) = &recording {
                        self.db.delete_recording(&rec.id);
                    }
                    next.recording_id = None;
                    next.status = if live.is_some() {
                        "confirmed"
                    } else {
                        "provisional"
                    }
                    .into();
                }
                Action::Realign { start, end } => {
                    if let Some(rec) = &recording {
                        self.db.update_recording_window(&rec.id, start, end);
                    }
                    next.status = "scheduled".into();
                }
                Action::Create { start, end } | Action::Recreate { start, end } => {
                    if let Some(rec) = &recording {
                        self.db.delete_recording(&rec.id);
                        next.recording_id = None;
                    }
                    let busy = overlapping(&self.db.get_pending_recordings(), start, end);
                    if self.scheduler.max_concurrent > 0 && busy >= self.scheduler.max_concurrent {
                        next.status = "confirmed".into();
                        next.conflict = true;
                    } else if let Some(l) = &live {
                        let channel = &l.programme.channel_id;
                        match self.db.create_recording(
                            &rule.user_id,
                            channel,
                            &format!("/api/live/{channel}.ts"),
                            &recording_title(&game),
                            start,
                            end,
                        ) {
                            Ok(rec) => {
                                self.db.set_recording_source(&rec.id, &rule.id);
                                next.recording_id = Some(rec.id);
                                next.status = "scheduled".into();
                                created += 1;
                                // Vignette prête pour la liste « À venir ».
                                let (http, art_game) = (self.http.clone(), next.clone());
                                tokio::spawn(async move {
                                    let dir = std::path::PathBuf::from(recordings_dir_path());
                                    nba_artwork::ensure_artwork(&http, &dir, &art_game).await;
                                });
                            }
                            Err(e) => println!("[NBA] Programmation impossible : {e}"),
                        }
                    }
                }
            }
            if next != game
                && let Err(e) = self.db.update_nba_game_state(&next)
            {
                println!("[NBA] État du match {} non sauvegardé : {e}", game.game_id);
            }
        }
        if created > 0 {
            println!("[NBA] Règle {} : {created} match(s) programmé(s)", rule.id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mise_en_pause_supprime_les_enregistrements_planifies() {
        let path = std::env::temp_dir().join(format!("xf-nba-{}.db", uuid::Uuid::new_v4()));
        let db = AppDatabase::open(path.to_str().unwrap()).unwrap();
        let user = db.create_user("u", "x", false).unwrap();
        let mut r = rule();
        r.user_id = user.id.clone();
        let r = db.create_auto_rule(&r).unwrap();
        let soon = Utc::now() + Duration::hours(10);
        for id in ["planned", "live"] {
            db.upsert_scheduled_game(
                &r.id,
                &crate::models::ScheduledGame {
                    game_id: id.into(),
                    home: "Los Angeles Lakers".into(),
                    away: "Boston Celtics".into(),
                    home_id: "13".into(),
                    away_id: "2".into(),
                    home_tri: "LAL".into(),
                    away_tri: "BOS".into(),
                    tipoff_utc: soon,
                },
            )
            .unwrap();
            let rec = db
                .create_recording(
                    &user.id,
                    "1",
                    "/api/live/1.ts",
                    id,
                    soon,
                    soon + Duration::hours(3),
                )
                .unwrap();
            if id == "live" {
                db.update_recording_status(&rec.id, "recording", None, None, false);
            }
            let mut g = db.get_nba_game(&r.id, id).unwrap();
            g.recording_id = Some(rec.id);
            g.channel_id = Some("1".into());
            g.status = "scheduled".into();
            db.update_nba_game_state(&g).unwrap();
        }

        suspend_rule(&db, &r);

        let planned = db.get_nba_game(&r.id, "planned").unwrap();
        assert_eq!(planned.recording_id, None);
        assert_eq!(planned.status, "confirmed");
        // L'enregistrement en cours reste, lié à son match.
        let live = db.get_nba_game(&r.id, "live").unwrap();
        let live_rec = db
            .get_recording_by_id(live.recording_id.as_deref().unwrap())
            .unwrap();
        assert_eq!(live_rec.status, "recording");
        assert_eq!(db.get_pending_recordings().len(), 1);
        let _ = std::fs::remove_file(path);
    }

    fn t(s: &str) -> DateTime<Utc> {
        DartDateTime::parse(s).unwrap().to_utc()
    }

    fn prog(channel: &str, title: &str, start: &str, end: &str) -> EpgProgramme {
        EpgProgramme {
            channel_id: channel.into(),
            channel_label: format!("beIN SPORTS {channel}"),
            title: title.into(),
            description: String::new(),
            start: t(start),
            end: t(end),
            is_live: false,
            previously_shown: false,
        }
    }

    fn rule() -> AutoRule {
        AutoRule {
            id: "r".into(),
            user_id: "u".into(),
            kind: "nba".into(),
            enabled: true,
            default_decision: "auto".into(),
            channel_ids: vec!["1".into(), "2".into()],
            pad_before_min: 5,
            pad_after_min: 45,
            team_filter: vec![],
            keep_days: None,
            created_at: String::new(),
            updated_at: String::new(),
        }
    }

    fn game(decision: &str) -> NbaGame {
        NbaGame {
            game_id: "g".into(),
            rule_id: "r".into(),
            home: "Los Angeles Lakers".into(),
            away: "Boston Celtics".into(),
            home_id: "13".into(),
            away_id: "2".into(),
            home_tri: "LAL".into(),
            away_tri: "BOS".into(),
            tipoff_utc: "2026-10-22T02:30:00.000Z".into(),
            status: "provisional".into(),
            decision: decision.into(),
            channel_id: None,
            channel_name: None,
            epg_title: None,
            epg_start: None,
            epg_end: None,
            recording_id: None,
            confidence: None,
            conflict: false,
            updated_at: String::new(),
        }
    }

    fn rec(channel: &str, status: &str, start: &str, end: &str) -> Recording {
        Recording {
            id: "rec".into(),
            user_id: "u".into(),
            channel_id: channel.into(),
            stream_url: String::new(),
            title: "NBA".into(),
            start_time: DartDateTime::parse(start).unwrap(),
            end_time: DartDateTime::parse(end).unwrap(),
            status: status.into(),
            file_path: None,
            error_reason: None,
            source_rule_id: Some("r".into()),
            created_at: DartDateTime::parse(start).unwrap(),
            updated_at: DartDateTime::parse(start).unwrap(),
        }
    }

    const TIP: &str = "2026-10-22T02:30:00Z";

    #[test]
    fn le_direct_est_retenu_la_rediffusion_ignoree() {
        let progs = vec![
            prog(
                "1",
                "NBA : Boston / LA Lakers",
                "2026-10-22T02:15:00Z",
                "2026-10-22T05:00:00Z",
            ),
            // Même match le lendemain midi : rediffusion, hors fenêtre.
            prog(
                "2",
                "NBA : Boston / LA Lakers",
                "2026-10-22T12:00:00Z",
                "2026-10-22T14:30:00Z",
            ),
        ];
        let live = find_live_broadcast("LAL", "BOS", t(TIP), false, &progs).unwrap();
        assert_eq!(live.programme.channel_id, "1");
        assert!(live.confidence >= 90);
        // Seule la rediffusion au guide : rien.
        assert!(find_live_broadcast("LAL", "BOS", t(TIP), false, &progs[1..]).is_none());
    }

    #[test]
    fn mots_de_rediffusion_et_drapeau_previously_shown() {
        let mut p = prog(
            "1",
            "NBA : Celtics - Lakers (rediffusion)",
            "2026-10-22T02:30:00Z",
            "2026-10-22T05:00:00Z",
        );
        assert!(find_live_broadcast("LAL", "BOS", t(TIP), false, &[p.clone()]).is_none());
        p.title = "NBA : Celtics - Lakers".into();
        p.previously_shown = true;
        assert!(find_live_broadcast("LAL", "BOS", t(TIP), false, &[p]).is_none());
    }

    #[test]
    fn autre_match_au_meme_moment_sur_une_autre_chaine() {
        let progs = vec![
            prog(
                "1",
                "NBA : Warriors / Suns",
                "2026-10-22T02:30:00Z",
                "2026-10-22T05:00:00Z",
            ),
            prog(
                "2",
                "Basket-ball NBA : Celtics @ Lakers en direct",
                "2026-10-22T02:25:00Z",
                "2026-10-22T05:00:00Z",
            ),
        ];
        let live = find_live_broadcast("LAL", "BOS", t(TIP), true, &progs).unwrap();
        assert_eq!(live.programme.channel_id, "2");
    }

    #[test]
    fn titre_generique_seulement_si_pas_d_ambiguite() {
        let progs = vec![prog(
            "1",
            "Basket-ball : NBA",
            "2026-10-22T02:30:00Z",
            "2026-10-22T05:00:00Z",
        )];
        assert!(find_live_broadcast("LAL", "BOS", t(TIP), false, &progs).is_some());
        assert!(find_live_broadcast("LAL", "BOS", t(TIP), true, &progs).is_none());
    }

    #[test]
    fn creation_avec_marges_et_duree_minimale() {
        let b = LiveBroadcast {
            programme: prog("1", "NBA", "2026-10-22T02:15:00Z", "2026-10-22T04:00:00Z"),
            confidence: 90,
        };
        let now = t("2026-10-21T10:00:00Z");
        let action = plan_action(&rule(), &game("auto"), t(TIP), Some(&b), None, now);
        // Début : 02:15 - 5 min ; fin : max(04:00, 02:30 + 2h30) + 45 min.
        assert_eq!(
            action,
            Action::Create {
                start: t("2026-10-22T02:10:00Z"),
                end: t("2026-10-22T05:45:00Z")
            }
        );
    }

    #[test]
    fn refus_supprime_l_enregistrement_planifie() {
        let r = rec(
            "1",
            "scheduled",
            "2026-10-22T02:10:00Z",
            "2026-10-22T05:45:00Z",
        );
        let now = t("2026-10-21T10:00:00Z");
        assert_eq!(
            plan_action(&rule(), &game("refused"), t(TIP), None, Some(&r), now),
            Action::Cancel
        );
        // Mais un enregistrement en cours n'est pas coupé par la réconciliation.
        let r = rec(
            "1",
            "recording",
            "2026-10-22T02:10:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert_eq!(
            plan_action(&rule(), &game("refused"), t(TIP), None, Some(&r), now),
            Action::Status("scheduled")
        );
    }

    #[test]
    fn mode_validation_et_filtre_d_equipes() {
        let b = LiveBroadcast {
            programme: prog("1", "NBA", "2026-10-22T02:30:00Z", "2026-10-22T05:00:00Z"),
            confidence: 90,
        };
        let now = t("2026-10-21T10:00:00Z");
        let mut ask = rule();
        ask.default_decision = "ask".into();
        assert_eq!(
            plan_action(&ask, &game("auto"), t(TIP), Some(&b), None, now),
            Action::Status("confirmed")
        );
        assert!(matches!(
            plan_action(&ask, &game("accepted"), t(TIP), Some(&b), None, now),
            Action::Create { .. }
        ));
        let mut only_knicks = rule();
        only_knicks.team_filter = vec!["Knicks".into()];
        assert!(!wants(&only_knicks, &game("auto")));
        only_knicks.team_filter = vec!["celtics".into()];
        assert!(wants(&only_knicks, &game("auto")));
    }

    #[test]
    fn realignement_et_changement_de_chaine() {
        let now = t("2026-10-21T10:00:00Z");
        let b = LiveBroadcast {
            programme: prog("1", "NBA", "2026-10-22T02:15:00Z", "2026-10-22T05:00:00Z"),
            confidence: 90,
        };
        let same = rec(
            "1",
            "scheduled",
            "2026-10-22T02:10:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert_eq!(
            plan_action(&rule(), &game("auto"), t(TIP), Some(&b), Some(&same), now),
            Action::Status("scheduled")
        );
        let moved = rec(
            "1",
            "scheduled",
            "2026-10-22T01:00:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert!(matches!(
            plan_action(&rule(), &game("auto"), t(TIP), Some(&b), Some(&moved), now),
            Action::Realign { .. }
        ));
        let other = rec(
            "2",
            "scheduled",
            "2026-10-22T02:10:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert!(matches!(
            plan_action(&rule(), &game("auto"), t(TIP), Some(&b), Some(&other), now),
            Action::Recreate { .. }
        ));
    }

    #[test]
    fn match_passe_sans_diffusion() {
        let now = t("2026-10-22T08:00:00Z");
        assert_eq!(
            plan_action(&rule(), &game("auto"), t(TIP), None, None, now),
            Action::Status("not_on_bein")
        );
    }

    #[test]
    fn titre_d_enregistrement() {
        assert_eq!(recording_title(&game("auto")), "NBA - Celtics @ Lakers");
    }
}
