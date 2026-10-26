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
use crate::services::bein_guide;
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

/// L'utilisateur a-t-il choisi ce match ? Rien n'est enregistré sans son
/// oui explicite : aucune programmation automatique, quels que soient les
/// anciens réglages de la règle (`default_decision`, `team_filter`).
pub fn wants(game: &NbaGame) -> bool {
    game.decision == "accepted"
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
    if !wants(game) {
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
    if live.programme.channel_id.is_empty() {
        // Diffusé sur une beIN absente de la playlist : rien à capturer.
        return match scheduled {
            Some(_) => Action::Status("scheduled"),
            None => Action::Status("confirmed"),
        };
    }
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

/// Enregistrement en attente ou en cours qui chevauche [start, end].
///
/// POURQUOI : l'abonnement IPTV n'autorise qu'un flux à la fois ; deux
/// captures simultanées échoueraient toutes les deux.
fn overlapping(
    recordings: &[Recording],
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> Option<&Recording> {
    recordings
        .iter()
        .filter(|r| matches!(r.status.as_str(), "scheduled" | "recording"))
        .find(|r| r.start_utc() < end && r.end_utc() > start)
}

fn parse_utc(raw: Option<&str>) -> Option<DateTime<Utc>> {
    raw.and_then(DartDateTime::parse).map(DartDateTime::to_utc)
}

/// Fenêtre d'enregistrement prévisible d'un match : créneau EPG s'il est
/// connu, sinon coup d'envoi + durée minimale ; marges de la règle autour.
pub fn expected_window(rule: &AutoRule, game: &NbaGame) -> Option<(DateTime<Utc>, DateTime<Utc>)> {
    let tipoff = parse_utc(Some(&game.tipoff_utc))?;
    let min_end = tipoff + Duration::minutes(MIN_GAME_MINUTES);
    let (start, end) = match (
        parse_utc(game.epg_start.as_deref()),
        parse_utc(game.epg_end.as_deref()),
    ) {
        (Some(s), Some(e)) => (s.min(tipoff), e.max(min_end)),
        _ => (tipoff, min_end),
    };
    Some((
        start - Duration::minutes(rule.pad_before_min.max(0)),
        end + Duration::minutes(rule.pad_after_min.max(0)),
    ))
}

/// Un seul flux IPTV à la fois : titre de ce qui occupe déjà le créneau du
/// match (autre match choisi, ou autre enregistrement en attente / en cours).
pub fn slot_taken_by(
    rule: &AutoRule,
    game: &NbaGame,
    games: &[NbaGame],
    recordings: &[Recording],
) -> Option<String> {
    let (start, end) = expected_window(rule, game)?;
    let chosen = games
        .iter()
        .filter(|o| o.game_id != game.game_id && wants(o))
        .find(|o| expected_window(rule, o).is_some_and(|(s, e)| s < end && e > start));
    if let Some(other) = chosen {
        return Some(recording_title(other));
    }
    let own = game.recording_id.as_deref();
    let others: Vec<Recording> = recordings
        .iter()
        .filter(|r| Some(r.id.as_str()) != own)
        .cloned()
        .collect();
    overlapping(&others, start, end).map(|r| r.title.clone())
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

/// Rattrapage des vignettes d'un enregistrement automatique terminé.
#[derive(Debug, PartialEq)]
pub enum ArtworkRepair {
    /// Jamais déposées (clôture après un redémarrage, écriture refusée…) :
    /// annexes et pochette intégrée au MKV.
    Full,
    /// Mise en page changée : redessiner les annexes seulement.
    Sidecars,
    None,
}

/// Délai après la fin prévue avant de toucher au fichier : la clôture
/// (fusion des parties, remux de la pochette) doit être finie, sans quoi
/// deux remux écriraient le même MKV.
const ARTWORK_REPAIR_DELAY_HOURS: i64 = 2;

pub fn plan_artwork_repair(
    rec: &Recording,
    file_ok: bool,
    has_sidecars: bool,
    layout_outdated: bool,
    now: DateTime<Utc>,
) -> ArtworkRepair {
    let eligible = rec.status == "completed"
        && rec.source_rule_id.is_some()
        && file_ok
        && rec.end_utc() + Duration::hours(ARTWORK_REPAIR_DELAY_HOURS) < now;
    match (eligible, has_sidecars, layout_outdated) {
        (false, _, _) => ArtworkRepair::None,
        (true, false, _) => ArtworkRepair::Full,
        (true, true, true) => ArtworkRepair::Sidecars,
        (true, true, false) => ArtworkRepair::None,
    }
}

/// Jours de guide beIN demandés (le site publie environ 8 jours).
const BEIN_GUIDE_DAYS: i64 = 10;

/// Diffusions du guide beIN → programmes des flux IPTV surveillés, par
/// libellé de chaîne (« beIN SPORTS MAX 4 » ↔ « FR| beIN SPORTS MAX 4 FHD »).
/// Second élément : chaînes beIN du guide sans flux correspondant.
pub fn map_bein_broadcasts(
    broadcasts: &[bein_guide::BeinBroadcast],
    labels: &[(String, String)],
) -> (Vec<EpgProgramme>, Vec<String>) {
    let mut mapped = Vec::new();
    let mut unmapped: Vec<String> = Vec::new();
    for b in broadcasts {
        let key = normalize(&b.channel);
        match labels.iter().find(|(_, label)| normalize(label) == key) {
            Some((stream_id, label)) => mapped.push(EpgProgramme {
                channel_id: stream_id.clone(),
                channel_label: label.clone(),
                title: b.title.clone(),
                description: String::new(),
                start: b.start,
                end: b.end,
                is_live: b.live,
                // beIN dit explicitement ce qui n'est pas du direct.
                previously_shown: !b.live,
            }),
            None => {
                // Affiché quand même : seul l'enregistrement exige un flux.
                mapped.push(EpgProgramme {
                    channel_id: String::new(),
                    channel_label: b.channel.clone(),
                    title: b.title.clone(),
                    description: String::new(),
                    start: b.start,
                    end: b.end,
                    is_live: b.live,
                    previously_shown: !b.live,
                });
                if b.live && !unmapped.contains(&b.channel) {
                    unmapped.push(b.channel.clone());
                }
            }
        }
    }
    (mapped, unmapped)
}

/// Flux IPTV à surveiller, avec leur libellé beIN : ceux choisis dans la
/// règle, complétés par les beIN FR détectées dans la playlist pour les
/// chaînes qu'aucun flux choisi ne couvre.
///
/// POURQUOI : une liste vide (détection ratée à la création) ou un flux
/// renommé par le revendeur faisait ignorer tout le guide beIN.
///
/// [names] : `(stream_id, nom, catégorie)` de la playlist. Un flux choisi
/// reconnu comme beIN étrangère (nom ou catégorie) est ignoré : le guide
/// beIN FR ne décrit pas ses programmes, et le panneau peut le refuser
/// (vu en prod : « BEIN SPORTS 1 FR ULTRA FHD » en « |AR| BEIN SPORTS 4K »,
/// HTTP 407 sur tout un match).
pub fn channel_labels(
    rule: &AutoRule,
    names: &[(String, String, String)],
) -> Vec<(String, String)> {
    let detected = crate::services::bein_channels::detect(names);
    let mut labels: Vec<(String, String)> = Vec::new();
    for id in &rule.channel_ids {
        let label = match detected.iter().find(|c| &c.stream_id == id) {
            Some(c) if !c.is_fr => {
                println!(
                    "[NBA] Flux {id} ignoré : « {} » n'est pas une beIN française ({})",
                    c.name, c.category
                );
                None
            }
            Some(c) => Some(c.label.clone()),
            None => names
                .iter()
                .find(|(sid, _, _)| sid == id)
                .map(|(_, n, _)| n.clone()),
        };
        if let Some(label) = label {
            labels.push((id.clone(), label));
        }
    }
    for c in crate::services::bein_channels::preferred_fr(&detected) {
        let covered = labels
            .iter()
            .any(|(_, l)| normalize(l) == normalize(&c.label));
        if !covered {
            labels.push((c.stream_id, c.label));
        }
    }
    labels
}

/// Service : calendrier quotidien + réconciliation toutes les 30 minutes.
pub struct NbaAutoRecorder {
    db: Arc<AppDatabase>,
    http: reqwest::Client,
    epg: EpgApi,
    timers: Mutex<Vec<JoinHandle<()>>>,
    /// Une réconciliation à la fois (timer et API peuvent se croiser).
    running: tokio::sync::Mutex<()>,
    /// Dernier diagnostic par règle (affiché dans l'onglet).
    diagnostics: Mutex<HashMap<String, Value>>,
}

impl NbaAutoRecorder {
    pub fn new(db: Arc<AppDatabase>, http: reqwest::Client, epg: EpgApi) -> Self {
        Self {
            db,
            http,
            epg,
            timers: Mutex::new(Vec::new()),
            running: tokio::sync::Mutex::new(()),
            diagnostics: Mutex::new(HashMap::new()),
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
                this.repair_artwork().await;
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

    /// Vignettes manquantes ou d'une ancienne mise en page : la clôture
    /// normale n'est pas le seul chemin vers « completed » (reprise après
    /// redémarrage, arrêt manuel d'un orphelin), et une écriture refusée ne
    /// doit pas priver définitivement le match de sa vignette.
    async fn repair_artwork(&self) {
        let dir = std::path::PathBuf::from(recordings_dir_path());
        let layout_file = nba_artwork::artwork_dir(&dir).join("layout");
        let layout_outdated = std::fs::read_to_string(&layout_file)
            .ok()
            .and_then(|v| v.trim().parse::<u32>().ok())
            != Some(nba_artwork::LAYOUT_VERSION);
        let now = Utc::now();
        let mut all_ok = true;
        for rec in self.db.get_finished_recordings_oldest_first() {
            let Some(path) = rec.file_path.as_deref().map(std::path::Path::new) else {
                continue;
            };
            let file_ok = std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.len() > 0);
            let action = plan_artwork_repair(
                &rec,
                file_ok,
                nba_artwork::has_sidecars(path),
                layout_outdated,
                now,
            );
            if action == ArtworkRepair::None {
                continue;
            }
            let Some(game) = self.db.get_nba_game_by_recording(&rec.id) else {
                continue;
            };
            let done = if action == ArtworkRepair::Full {
                println!("[NBA] Vignettes rattrapées : {}", rec.title);
                nba_artwork::finish_recording(
                    &self.http,
                    &dir,
                    &game,
                    path,
                    &rec.title,
                    &crate::services::recording_scheduler::resolve_ffmpeg_path(),
                )
                .await;
                nba_artwork::has_sidecars(path)
            } else {
                nba_artwork::write_sidecars(&self.http, &dir, &game, path, &rec.title)
                    .await
                    .is_some()
            };
            all_ok &= done;
        }
        if layout_outdated && all_ok {
            let _ = std::fs::create_dir_all(nba_artwork::artwork_dir(&dir));
            if let Err(e) = std::fs::write(&layout_file, nba_artwork::LAYOUT_VERSION.to_string()) {
                println!("[NBA] Version des vignettes non enregistrée : {e}");
            }
        }
    }

    /// IPTV de la règle ; à défaut (règle ancienne), la plus récente.
    fn playlist_for(&self, rule: &AutoRule) -> Option<PlaylistConfig> {
        rule.playlist_id
            .as_deref()
            .and_then(|id| self.db.get_playlist_by_id(id))
            .filter(|p| p.user_id == rule.user_id)
            .or_else(|| self.db.get_playlists(&rule.user_id).into_iter().next())
            .map(PlaylistConfig::from)
    }

    /// Dernier diagnostic de la règle : source, diffusions trouvées,
    /// chaînes reliées ou absentes de la playlist.
    pub fn diagnostic(&self, rule_id: &str) -> Option<Value> {
        self.diagnostics.lock().unwrap().get(rule_id).cloned()
    }

    /// Diffusions à rapprocher des matchs : guide beIN d'abord (toutes les
    /// beIN FR, reliées ou non à un flux), EPG IPTV en repli.
    async fn collect_programmes(
        &self,
        rule: &AutoRule,
        playlist: Option<&PlaylistConfig>,
    ) -> (Vec<EpgProgramme>, Value) {
        let names = match playlist {
            Some(p) => self.epg.channel_table(p).await,
            None => Vec::new(),
        };
        let labels = channel_labels(rule, &names);
        let linked: Vec<&str> = labels.iter().map(|(_, l)| l.as_str()).collect();

        if let Some(broadcasts) = bein_guide::fetch_nba(&self.http, BEIN_GUIDE_DAYS).await {
            let (progs, missing) = map_bein_broadcasts(&broadcasts, &labels);
            if !missing.is_empty() {
                println!(
                    "[NBA] beIN absentes de la playlist : {}",
                    missing.join(", ")
                );
            }
            let diag = serde_json::json!({
                "source": "bein",
                "broadcasts": broadcasts.len(),
                "live_broadcasts": broadcasts.iter().filter(|b| b.live).count(),
                "linked_channels": linked,
                "missing_channels": missing,
                "playlist_channels": names.len(),
            });
            return (progs, diag);
        }

        let mut out = Vec::new();
        if let Some(p) = playlist {
            for (channel_id, label) in &labels {
                for v in self.epg.programmes(p, channel_id).await {
                    if let Some(prog) = EpgProgramme::from_json(channel_id, label, &v) {
                        out.push(prog);
                    }
                }
            }
        }
        let diag = serde_json::json!({
            "source": "iptv",
            "broadcasts": out.len(),
            "linked_channels": linked,
            "missing_channels": [],
            "playlist_channels": names.len(),
        });
        (out, diag)
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
        let playlist = self.playlist_for(rule);
        if games.is_empty() {
            self.diagnostics.lock().unwrap().insert(
                rule.id.clone(),
                serde_json::json!({"games_in_calendar": 0, "at": utc_iso(now)}),
            );
            return;
        }
        // L'EPG ne couvre que quelques jours : inutile de le charger pour
        // des matchs lointains seulement.
        let needs_epg = games.iter().any(|g| {
            DartDateTime::parse(&g.tipoff_utc)
                .is_some_and(|t| t.to_utc() < now + Duration::days(BEIN_GUIDE_DAYS))
        });
        let (programmes, mut diag) = if needs_epg {
            self.collect_programmes(rule, playlist.as_ref()).await
        } else {
            (Vec::new(), serde_json::json!({"source": "none"}))
        };
        let tipoffs: HashMap<String, DateTime<Utc>> = games
            .iter()
            .filter_map(|g| {
                DartDateTime::parse(&g.tipoff_utc).map(|t| (g.game_id.clone(), t.to_utc()))
            })
            .collect();

        let mut created = 0;
        let mut matched = 0;
        let in_calendar = games.len();
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
                matched += 1;
                next.channel_id =
                    (!l.programme.channel_id.is_empty()).then(|| l.programme.channel_id.clone());
                next.channel_name = Some(l.programme.channel_label.clone());
                next.epg_title = Some(l.programme.title.clone());
                next.epg_start = Some(utc_iso(l.programme.start));
                next.epg_end = Some(utc_iso(l.programme.end));
                next.confidence = Some(l.confidence);
            } else if !programmes.is_empty()
                && tipoff < now + Duration::days(BEIN_GUIDE_DAYS)
                && recording.is_none()
            {
                // Le guide couvre ce match et ne l'annonce plus en direct :
                // oublier la chaîne d'un passage précédent.
                next.channel_id = None;
                next.channel_name = None;
                next.epg_title = None;
                next.epg_start = None;
                next.epg_end = None;
                next.confidence = None;
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
                    // Un seul flux IPTV : tout chevauchement bloque.
                    let pending = self.db.get_pending_recordings();
                    if overlapping(&pending, start, end).is_some() {
                        next.status = "confirmed".into();
                        next.conflict = true;
                    } else if let Some(l) = &live {
                        let channel = &l.programme.channel_id;
                        let playlist_id =
                            playlist.as_ref().map(|p| p.id.clone()).unwrap_or_default();
                        match self.db.create_recording(
                            &rule.user_id,
                            channel,
                            &crate::models::stream_url_for_playlist(
                                &format!("/api/live/{channel}.ts"),
                                &playlist_id,
                            ),
                            &recording_title(&game),
                            start,
                            end,
                        ) {
                            Ok(rec) => {
                                self.db.set_recording_source(&rec.id, &rule.id);
                                if !playlist_id.is_empty() {
                                    self.db.set_recording_playlist(&rec.id, &playlist_id);
                                }
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
        if let Value::Object(m) = &mut diag {
            m.insert("games_in_calendar".into(), in_calendar.into());
            m.insert("matched_games".into(), matched.into());
            m.insert("has_playlist".into(), playlist.is_some().into());
            m.insert("at".into(), utc_iso(now).into());
        }
        self.diagnostics
            .lock()
            .unwrap()
            .insert(rule.id.clone(), diag);
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
            playlist_id: None,
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
            playlist_id: None,
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
        let action = plan_action(&rule(), &game("accepted"), t(TIP), Some(&b), None, now);
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

    /// Rapprochement réel (réseau) : `cargo test croisement_reel -- --ignored --nocapture`.
    #[tokio::test]
    #[ignore]
    async fn croisement_reel_guide_bein_calendrier_nba() {
        let http = reqwest::Client::new();
        let guide = bein_guide::fetch_nba(&http, BEIN_GUIDE_DAYS).await.unwrap();
        let labels: Vec<(String, String)> = guide
            .iter()
            .map(|b| (b.channel.clone(), b.channel.clone()))
            .collect();
        let (progs, _) = map_bein_broadcasts(&guide, &labels);
        let first = (Utc::now() - Duration::days(1)).date_naive();
        let games = nba_schedule::fetch_days(&http, first, 10).await;
        let mut found = 0;
        for g in &games {
            let nearby = games.iter().any(|o| {
                o.game_id != g.game_id && (o.tipoff_utc - g.tipoff_utc).num_minutes().abs() < 60
            });
            if let Some(l) =
                find_live_broadcast(&g.home_tri, &g.away_tri, g.tipoff_utc, nearby, &progs)
            {
                found += 1;
                println!(
                    "{} {} @ {} → {} {} ({})",
                    g.tipoff_utc,
                    g.away,
                    g.home,
                    l.programme.channel_label,
                    l.programme.start,
                    l.confidence
                );
            }
        }
        println!(
            "{found} match(s) en direct sur beIN / {} au calendrier",
            games.len()
        );
        assert!(found > 0);
    }

    #[test]
    fn guide_bein_vers_flux_iptv_et_direct_seulement() {
        let b =
            |ch: &str, title: &str, start: &str, end: &str, live: bool| bein_guide::BeinBroadcast {
                channel: ch.into(),
                title: title.into(),
                start: t(start),
                end: t(end),
                live,
            };
        let guide = vec![
            b(
                "beIN SPORTS 1",
                "Basket-ball : NBA - Los Angeles Lakers / Boston Celtics",
                "2026-10-22T02:30:00Z",
                "2026-10-22T05:00:00Z",
                true,
            ),
            b(
                "beIN SPORTS 1",
                "Basket-ball : NBA - Los Angeles Lakers / Boston Celtics",
                "2026-10-22T09:00:00Z",
                "2026-10-22T10:45:00Z",
                false,
            ),
            b(
                "beIN SPORTS MAX 9",
                "Basket-ball : NBA - Miami Heat / Utah Jazz",
                "2026-10-22T02:30:00Z",
                "2026-10-22T05:00:00Z",
                true,
            ),
        ];
        let labels = vec![("101".to_string(), "beIN SPORTS 1".to_string())];
        let (progs, unmapped) = map_bein_broadcasts(&guide, &labels);
        // Tout est gardé pour l'affichage ; le flux manque pour MAX 9.
        assert_eq!(progs.len(), 3);
        assert!(progs[..2].iter().all(|p| p.channel_id == "101"));
        assert_eq!(progs[2].channel_id, "");
        assert_eq!(progs[2].channel_label, "beIN SPORTS MAX 9");
        assert_eq!(unmapped, vec!["beIN SPORTS MAX 9".to_string()]);
        // Le direct est retenu ; la rediffusion du matin ne l'est pas.
        let live = find_live_broadcast("LAL", "BOS", t(TIP), false, &progs[..2]).unwrap();
        assert_eq!(live.programme.start, t("2026-10-22T02:30:00Z"));
        assert!(find_live_broadcast("LAL", "BOS", t(TIP), false, &progs[1..2]).is_none());
        // Diffusion sur une beIN absente de la playlist : affichée, pas programmée.
        let miami = find_live_broadcast("MIA", "UTAH", t(TIP), false, &progs).unwrap();
        assert_eq!(miami.programme.channel_label, "beIN SPORTS MAX 9");
        let mut g = game("accepted");
        g.home_tri = "MIA".into();
        g.away_tri = "UTAH".into();
        assert_eq!(
            plan_action(
                &rule(),
                &g,
                t(TIP),
                Some(&miami),
                None,
                t("2026-10-21T10:00:00Z")
            ),
            Action::Status("confirmed")
        );
    }

    #[test]
    fn chaines_bein_detectees_dans_la_playlist() {
        let names: Vec<(String, String, String)> = [
            ("10", "FR - BEIN SPORTS 1 HD"),
            ("11", "FR - BEIN SPORTS 1 FHD"),
            ("20", "FR| beIN SPORTS 2"),
            ("30", "AR - BEIN SPORTS 3"),
            ("40", "FR - TF1"),
        ]
        .iter()
        .map(|(a, b)| (a.to_string(), b.to_string(), String::new()))
        .collect();
        // Règle sans chaîne (détection ratée à la création) : tout est relié.
        let mut r = rule();
        r.channel_ids = vec![];
        let labels = channel_labels(&r, &names);
        assert_eq!(
            labels,
            vec![
                ("11".to_string(), "beIN SPORTS 1".to_string()),
                ("20".to_string(), "beIN SPORTS 2".to_string()),
            ]
        );
        // Le flux choisi pour beIN 1 est gardé, beIN 2 complété.
        r.channel_ids = vec!["10".into()];
        let labels = channel_labels(&r, &names);
        assert_eq!(labels[0], ("10".to_string(), "beIN SPORTS 1".to_string()));
        assert_eq!(labels.len(), 2);
    }

    #[test]
    fn un_flux_choisi_d_une_categorie_etrangere_est_remplace() {
        // Vu en prod : la règle visait 550403, « FR » dans le nom mais rangée
        // en « |AR| BEIN SPORTS 4K », hors abonnement (HTTP 407 à chaque
        // tentative). Le guide beIN FR ne décrit pas cette chaîne.
        let names: Vec<(String, String, String)> = [
            (
                "550403",
                "BEIN SPORTS 1 FR ULTRA FHD",
                "|AR| BEIN SPORTS 4K",
            ),
            ("554021", "FR - BEIN SPORTS 1 FHD", "FR| SPORTS"),
        ]
        .iter()
        .map(|(a, b, c)| (a.to_string(), b.to_string(), c.to_string()))
        .collect();
        let mut r = rule();
        r.channel_ids = vec!["550403".into()];
        assert_eq!(
            channel_labels(&r, &names),
            vec![("554021".to_string(), "beIN SPORTS 1".to_string())]
        );
    }

    #[test]
    fn un_seul_enregistrement_par_creneau() {
        let r = rule();
        let mut chosen = game("accepted");
        chosen.game_id = "a".into();
        // Coup d'envoi 1 h plus tard : chevauche (fenêtre de 2 h 30 + marges).
        let mut later = game("auto");
        later.game_id = "b".into();
        later.home_tri = "GS".into();
        later.away_tri = "PHX".into();
        later.tipoff_utc = "2026-10-22T03:30:00.000Z".into();
        let games = vec![chosen.clone(), later.clone()];
        assert_eq!(
            slot_taken_by(&r, &later, &games, &[]).as_deref(),
            Some("NBA - Celtics @ Lakers")
        );
        // Le lendemain soir : libre.
        later.tipoff_utc = "2026-10-23T02:30:00.000Z".into();
        let games = vec![chosen.clone(), later.clone()];
        assert_eq!(slot_taken_by(&r, &later, &games, &[]), None);
        // Un autre enregistrement (manuel) sur le créneau bloque aussi.
        let manual = rec(
            "9",
            "scheduled",
            "2026-10-23T03:00:00Z",
            "2026-10-23T04:00:00Z",
        );
        assert!(slot_taken_by(&r, &later, &[later.clone()], &[manual]).is_some());
        // Son propre enregistrement ne compte pas.
        let mut own = rec(
            "1",
            "scheduled",
            "2026-10-23T02:25:00Z",
            "2026-10-23T05:45:00Z",
        );
        own.id = "own".into();
        later.recording_id = Some("own".into());
        assert_eq!(slot_taken_by(&r, &later, &[later.clone()], &[own]), None);
    }

    #[test]
    fn rien_n_est_enregistre_sans_un_oui() {
        let b = LiveBroadcast {
            programme: prog("1", "NBA", "2026-10-22T02:30:00Z", "2026-10-22T05:00:00Z"),
            confidence: 90,
        };
        let now = t("2026-10-21T10:00:00Z");
        // Même une ancienne règle en mode 'auto' ne programme rien seule.
        let mut legacy = rule();
        legacy.default_decision = "auto".into();
        assert_eq!(
            plan_action(&legacy, &game("auto"), t(TIP), Some(&b), None, now),
            Action::Status("confirmed")
        );
        assert!(matches!(
            plan_action(&legacy, &game("accepted"), t(TIP), Some(&b), None, now),
            Action::Create { .. }
        ));
        // Un enregistrement programmé sans choix explicite est annulé.
        let r = rec(
            "1",
            "scheduled",
            "2026-10-22T02:10:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert_eq!(
            plan_action(&legacy, &game("auto"), t(TIP), Some(&b), Some(&r), now),
            Action::Cancel
        );
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
            plan_action(
                &rule(),
                &game("accepted"),
                t(TIP),
                Some(&b),
                Some(&same),
                now
            ),
            Action::Status("scheduled")
        );
        let moved = rec(
            "1",
            "scheduled",
            "2026-10-22T01:00:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert!(matches!(
            plan_action(
                &rule(),
                &game("accepted"),
                t(TIP),
                Some(&b),
                Some(&moved),
                now
            ),
            Action::Realign { .. }
        ));
        let other = rec(
            "2",
            "scheduled",
            "2026-10-22T02:10:00Z",
            "2026-10-22T05:45:00Z",
        );
        assert!(matches!(
            plan_action(
                &rule(),
                &game("accepted"),
                t(TIP),
                Some(&b),
                Some(&other),
                now
            ),
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
    fn rattrapage_des_vignettes() {
        let now = t("2026-10-26T20:00:00Z");
        let mut r = rec(
            "1",
            "completed",
            "2026-10-24T00:00:00Z",
            "2026-10-24T03:30:00Z",
        );
        r.source_rule_id = Some("rule".into());
        assert_eq!(
            plan_artwork_repair(&r, true, false, false, now),
            ArtworkRepair::Full
        );
        assert_eq!(
            plan_artwork_repair(&r, true, true, true, now),
            ArtworkRepair::Sidecars
        );
        assert_eq!(
            plan_artwork_repair(&r, true, true, false, now),
            ArtworkRepair::None
        );
        // Fichier absent, enregistrement manuel, clôture peut-être en cours.
        assert_eq!(
            plan_artwork_repair(&r, false, false, true, now),
            ArtworkRepair::None
        );
        let just_ended = t("2026-10-24T04:00:00Z");
        assert_eq!(
            plan_artwork_repair(&r, true, false, true, just_ended),
            ArtworkRepair::None
        );
        r.source_rule_id = None;
        assert_eq!(
            plan_artwork_repair(&r, true, false, true, now),
            ArtworkRepair::None
        );
        r.source_rule_id = Some("rule".into());
        r.status = "failed".into();
        assert_eq!(
            plan_artwork_repair(&r, true, false, true, now),
            ArtworkRepair::None
        );
    }

    #[test]
    fn titre_d_enregistrement() {
        assert_eq!(recording_title(&game("auto")), "NBA - Celtics @ Lakers");
    }
}
