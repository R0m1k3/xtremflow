//! `/api/recordings` : liste, programmation, arrêt, suppression, logs.
//! `/api/season-passes` : enregistrements répétés par titre d'émission.

use crate::dart_time::DartDateTime;
use crate::http::{self, Req, Resp, json, segments};
use crate::models::{Recording, User, stream_url_for_playlist};
use crate::services::recording_scheduler::{RecordingScheduler, recordings_dir_path};
use crate::state::SharedState;
use crate::util::ssrf;
use crate::util::{media_probe, safe_path};
use chrono::{DateTime, Utc};
use regex::Regex;
use serde_json::{Map, Value, json};
use std::path::Path;
use std::sync::LazyLock;

/// L'utilisateur peut-il agir sur cet enregistrement ?
fn can_access(user: Option<&User>, recording: &Recording) -> bool {
    user.is_some_and(|u| u.is_admin || recording.user_id == u.id)
}

pub async fn recordings(state: &SharedState, req: &Req, rest: &str) -> Resp {
    match (req.method.as_str(), segments(rest).as_slice()) {
        ("GET" | "HEAD", []) => list(state, req).await,
        ("POST", []) => create(state, req).await,
        ("DELETE", [id]) => delete(state, req, id),
        ("POST", ["stop", id]) => stop(state, req, id),
        ("GET" | "HEAD", ["logs", id]) => logs(state, req, id).await,
        _ => http::not_found(),
    }
}

async fn logs(state: &SharedState, req: &Req, id: &str) -> Resp {
    let Some(recording) = state.db.get_recording_by_id(id) else {
        return json(404, &json!({"error": "Enregistrement non trouvé"}));
    };
    if !can_access(req.user.as_ref(), &recording) {
        return json(403, &json!({"error": "Accès refusé"}));
    }
    let Some(file_path) = &recording.file_path else {
        return json(
            404,
            &json!({"error": "Aucun fichier ni log associé pour le moment."}),
        );
    };
    // Enregistrements en .mkv, log .log à côté.
    let log_path = Path::new(file_path).with_extension("log");
    // Anti traversée : le log doit rester dans le dossier des enregistrements.
    let Some(safe) = safe_path::resolve_within(&recordings_dir_path(), &log_path.to_string_lossy())
    else {
        return json(403, &json!({"error": "Chemin de log invalide"}));
    };
    match tokio::fs::read(&safe).await {
        Ok(bytes) => json(200, &json!({"logs": String::from_utf8_lossy(&bytes)})),
        Err(_) => json(404, &json!({"error": "Le fichier de log est introuvable."})),
    }
}

/// Liste les enregistrements de l'utilisateur (tous pour un admin),
/// enrichis du suivi : taille, progression, relances, durée réelle.
async fn list(state: &SharedState, req: &Req) -> Resp {
    let mut recordings = match &req.user {
        Some(user) if !user.is_admin => state.db.get_user_recordings(&user.id),
        _ => state.db.get_all_recordings(),
    };
    // Chaque IPTV n'affiche que ses propres enregistrements. Une ligne sans
    // playlist n'appartient à aucune : la rattacher au démarrage est le
    // travail de `attach_legacy_rows_to_playlists`, pas l'afficher partout.
    if let Some(pid) = state.scoped_playlist_id(req) {
        recordings.retain(|r| r.playlist_id.as_deref() == Some(pid.as_str()));
    }
    let now = Utc::now();
    let mut enriched = Vec::with_capacity(recordings.len());
    for r in &recordings {
        let mut map = enrich(&state.scheduler, r, now);
        // Durée réelle du média : `end_time - start_time` n'est que la durée
        // programmée, fausse pour un enregistrement arrêté ou tronqué.
        if let Some(duration) = probe_duration(r).await {
            map.insert("duration_seconds".into(), json!(duration));
        }
        enriched.push(Value::Object(map));
    }
    json(200, &Value::Array(enriched))
}

/// Une capture en cours grossit en permanence : le cache de ffprobe serait
/// invalidé à chaque appel. Seuls les enregistrements terminés sont mesurés.
async fn probe_duration(r: &Recording) -> Option<f64> {
    let path = r.file_path.as_deref()?;
    if r.status != "completed" {
        return None;
    }
    let safe = safe_path::resolve_within(&recordings_dir_path(), path)?;
    media_probe::duration(&safe).await
}

fn enrich(scheduler: &RecordingScheduler, r: &Recording, now: DateTime<Utc>) -> Map<String, Value> {
    let mut map = r.to_map();
    if r.status == "recording" {
        let start = r.start_utc();
        let total = (r.end_utc() - start).num_seconds();
        if total > 0 {
            let elapsed = (now - start).num_seconds();
            let pct = (elapsed as f64 * 100.0 / total as f64)
                .clamp(0.0, 100.0)
                .round() as i64;
            map.insert("progress_pct".into(), json!(pct));
        }
        map.insert("is_active".into(), json!(scheduler.is_capturing(&r.id)));
        if let Some(retries) = scheduler.retry_count_of(&r.id) {
            map.insert("retry_count".into(), json!(retries));
        }
    }
    if let Some(path) = &r.file_path
        && let Ok(meta) = std::fs::metadata(path)
        && meta.is_file()
    {
        map.insert("file_size_bytes".into(), json!(meta.len()));
    }
    map
}

static ZONE_SUFFIX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[+-]\d{2}:?\d{2}$").unwrap());

/// Date ISO-8601 AVEC fuseau, normalisée en UTC. Une date naïve est
/// ambiguë : l'interpréter dans le fuseau du serveur décalait
/// l'enregistrement de plusieurs heures selon le TZ du conteneur.
fn parse_zoned_date(raw: Option<&Value>) -> Option<DateTime<Utc>> {
    let s = match raw? {
        Value::String(s) => s.clone(),
        Value::Null => return None,
        other => other.to_string(),
    };
    if s.is_empty() || !(s.ends_with('Z') || ZONE_SUFFIX.is_match(&s)) {
        return None;
    }
    DartDateTime::parse(&s).map(|d| d.to_utc())
}

fn to_text(v: Option<&Value>) -> Option<String> {
    match v? {
        Value::Null => None,
        Value::String(s) => Some(s.clone()),
        other => Some(other.to_string()),
    }
}

async fn create(state: &SharedState, req: &Req) -> Resp {
    let Some(user_id) = req
        .user
        .as_ref()
        .map(|u| u.id.clone())
        .or(req.user_id.clone())
    else {
        return json(401, &json!({"error": "Authentification requise"}));
    };
    let Ok(Value::Object(data)) = serde_json::from_slice::<Value>(&req.body) else {
        return json(400, &json!({"error": "Corps JSON invalide"}));
    };
    let channel_id = to_text(data.get("channel_id")).unwrap_or_default();
    let stream_url = to_text(data.get("stream_url")).unwrap_or_default();
    if channel_id.is_empty() {
        return json(400, &json!({"error": "channel_id est requis"}));
    }
    if stream_url.is_empty() {
        return json(400, &json!({"error": "stream_url est requis"}));
    }
    // Passée telle quelle à FFmpeg (-i) : http(s) public ou chemin local
    // /api/… seulement (anti-SSRF, pas de file:/concat:).
    if let Err(e) = ssrf::check_stream_url(&stream_url).await {
        return json(400, &json!({"error": e}));
    }
    let (Some(start), Some(end)) = (
        parse_zoned_date(data.get("start_time")),
        parse_zoned_date(data.get("end_time")),
    ) else {
        return json(
            400,
            &json!({"error": "start_time et end_time doivent être des dates ISO-8601 avec fuseau (ex: 2026-08-27T21:00:00Z)"}),
        );
    };
    if end <= start {
        return json(
            400,
            &json!({"error": "end_time doit être après start_time"}),
        );
    }
    let max_hours: i64 = std::env::var("MAX_RECORDING_HOURS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(12);
    if end - start > chrono::Duration::hours(max_hours) {
        return json(
            400,
            &json!({"error": format!("Durée maximale dépassée ({max_hours} h)")}),
        );
    }
    let title = to_text(data.get("title")).unwrap_or_else(|| "Sans Titre".into());
    // Capture sur l'IPTV choisie par le client (à défaut, la plus récente) —
    // la même que celle sous laquelle la liste s'affichera.
    let playlist_id = state.scoped_playlist_id(req);
    let stream_url = match &playlist_id {
        Some(pid) => stream_url_for_playlist(&stream_url, pid),
        None => stream_url,
    };
    match state
        .db
        .create_recording(&user_id, &channel_id, &stream_url, &title, start, end)
    {
        Ok(mut recording) => {
            if let Some(pid) = &playlist_id {
                state.db.set_recording_playlist(&recording.id, pid);
                recording.playlist_id = Some(pid.clone());
            }
            json(200, &Value::Object(recording.to_map()))
        }
        Err(e) => {
            println!("[RecordingsApi] Erreur à la création: {e}");
            json(500, &json!({"error": "Erreur lors de la programmation"}))
        }
    }
}

/// Annule ou supprime un enregistrement : capture abandonnée si elle
/// tourne, fichiers (.ts, .mkv, .log, annexes) supprimés avec la ligne.
fn delete(state: &SharedState, req: &Req, id: &str) -> Resp {
    let Some(recording) = state.db.get_recording_by_id(id) else {
        return json(404, &json!({"error": "Enregistrement non trouvé"}));
    };
    if !can_access(req.user.as_ref(), &recording) {
        return json(403, &json!({"error": "Accès refusé"}));
    }
    // Abandonner la capture AVANT de supprimer de la base.
    state.scheduler.discard_recording(id);
    if let Some(path) = &recording.file_path {
        // Confiné au dossier des enregistrements.
        if let Some(safe) = safe_path::resolve_within(&recordings_dir_path(), path) {
            RecordingScheduler::delete_recording_files(&safe);
        }
    }
    state.db.delete_recording(id);
    json(
        200,
        &json!({"message": "Enregistrement supprimé avec succès"}),
    )
}

fn stop(state: &SharedState, req: &Req, id: &str) -> Resp {
    let Some(recording) = state.db.get_recording_by_id(id) else {
        return json(404, &json!({"error": "Enregistrement non trouvé"}));
    };
    if !can_access(req.user.as_ref(), &recording) {
        return json(403, &json!({"error": "Accès refusé"}));
    }
    if state.scheduler.stop_recording(id) {
        return json(200, &json!({"message": "Enregistrement arrêté"}));
    }
    match recording.status.as_str() {
        // Rien capturé : annulé, pas « terminé » (la lecture échouerait).
        "scheduled" => {
            state
                .db
                .update_recording_status(id, "cancelled", None, None, false);
            json(200, &json!({"message": "Enregistrement annulé"}))
        }
        // « recording » sans processus (orphelin) : clôturer.
        "recording" => {
            state
                .db
                .update_recording_status(id, "completed", None, None, false);
            json(
                200,
                &json!({"message": "Enregistrement marqué comme terminé"}),
            )
        }
        // Déjà clôturé : ne pas écraser le statut final.
        _ => json(200, &json!({"message": "Enregistrement déjà clôturé"})),
    }
}

// ==================== /api/season-passes ====================

pub fn season_passes(state: &SharedState, req: &Req, rest: &str) -> Resp {
    match (req.method.as_str(), segments(rest).as_slice()) {
        ("GET" | "HEAD", []) => {
            let Some(user) = &req.user else {
                return json(401, &json!({"error": "Authentification requise"}));
            };
            let mut passes = if user.is_admin {
                state.db.get_all_season_passes()
            } else {
                state.db.get_season_passes_for_user(&user.id)
            };
            // Comme les enregistrements : un season pass appartient à une
            // seule IPTV, et une ligne sans playlist à aucune.
            if let Some(pid) = state.scoped_playlist_id(req) {
                passes
                    .retain(|p| p.get("playlist_id").and_then(Value::as_str) == Some(pid.as_str()));
            }
            json(
                200,
                &Value::Array(passes.into_iter().map(Value::Object).collect()),
            )
        }
        ("POST", []) => create_pass(state, req),
        ("DELETE", [id]) => {
            let Some(pass) = state.db.get_season_pass_by_id(id) else {
                return json(404, &json!({"error": "Season Pass non trouvé"}));
            };
            // Seul le propriétaire ou un admin supprime.
            let owner = pass.get("user_id").and_then(Value::as_str);
            let allowed = req
                .user
                .as_ref()
                .is_some_and(|u| u.is_admin || owner == Some(u.id.as_str()));
            if !allowed {
                return json(403, &json!({"error": "Accès refusé"}));
            }
            state.db.delete_season_pass(id);
            json(200, &json!({"message": "Season Pass supprimé"}))
        }
        _ => http::not_found(),
    }
}

fn create_pass(state: &SharedState, req: &Req) -> Resp {
    let data = match serde_json::from_slice::<Value>(&req.body) {
        Ok(Value::Object(map)) => map,
        Ok(_) => return json(500, &json!({"error": "Erreur: invalid body"})),
        Err(e) => {
            return json(
                500,
                &json!({"error": format!("Erreur: FormatException: {e}")}),
            );
        }
    };
    let field = |k: &str| {
        data.get(k)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    };
    let (show_title, channel_id, stream_url) = (
        field("show_title"),
        field("channel_id"),
        field("stream_url"),
    );
    if show_title.is_empty() {
        return json(400, &json!({"error": "show_title est requis"}));
    }
    if channel_id.is_empty() {
        return json(400, &json!({"error": "channel_id est requis"}));
    }
    if stream_url.is_empty() {
        return json(400, &json!({"error": "stream_url est requis"}));
    }
    // Même contrôle qu'à la création d'un enregistrement ; la résolution DNS
    // est refaite au lancement de chaque capture.
    if let Err(e) = ssrf::check_stream_url_syntax(&stream_url) {
        return json(400, &json!({"error": e}));
    }
    let Some(user) = &req.user else {
        return json(401, &json!({"error": "Authentification requise"}));
    };
    // 'exact' par défaut : « Journal » ne doit pas capturer tous les
    // programmes qui contiennent le mot.
    let match_mode = if data.get("match_mode").and_then(Value::as_str) == Some("contains") {
        "contains"
    } else {
        "exact"
    };
    let duplicate = state
        .db
        .get_season_passes_for_user(&user.id)
        .iter()
        .any(|p| {
            p.get("show_title")
                .and_then(Value::as_str)
                .is_some_and(|t| t.to_lowercase() == show_title.to_lowercase())
                && p.get("channel_id").and_then(Value::as_str) == Some(channel_id.as_str())
        });
    if duplicate {
        return json(
            409,
            &json!({"error": "Un Season Pass identique existe déjà"}),
        );
    }
    let playlist_id = state.scoped_playlist_id(req);
    let stream_url = match &playlist_id {
        Some(pid) => stream_url_for_playlist(&stream_url, pid),
        None => stream_url,
    };
    match state
        .db
        .create_season_pass(&user.id, &show_title, &channel_id, &stream_url, match_mode)
    {
        Ok(mut pass) => {
            if let Some(pid) = &playlist_id {
                let id = pass
                    .get("id")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string();
                state.db.set_season_pass_playlist(&id, pid);
                pass.insert("playlist_id".into(), Value::from(pid.clone()));
            }
            println!("[SeasonPass] Créé: \"{show_title}\" sur chaîne {channel_id}");
            json(201, &Value::Object(pass))
        }
        Err(e) => json(500, &json!({"error": format!("Erreur: {e}")})),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exige_un_fuseau() {
        assert!(parse_zoned_date(Some(&json!("2026-08-27T21:00:00Z"))).is_some());
        assert_eq!(
            parse_zoned_date(Some(&json!("2026-08-27T23:00:00+02:00"))).unwrap(),
            parse_zoned_date(Some(&json!("2026-08-27T21:00:00Z"))).unwrap()
        );
        assert!(parse_zoned_date(Some(&json!("2026-08-27T21:00:00"))).is_none());
        assert!(parse_zoned_date(Some(&json!(""))).is_none());
        assert!(parse_zoned_date(None).is_none());
    }
}
