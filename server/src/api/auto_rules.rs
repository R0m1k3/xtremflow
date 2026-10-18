//! `/api/auto-rules` : enregistrement automatique des matchs NBA en direct
//! sur beIN Sports FR.
//!
//! - `GET    /api/auto-rules`                              règles de l'utilisateur
//! - `POST   /api/auto-rules`                              crée la règle NBA
//! - `PATCH  /api/auto-rules/{id}`                         réglages (PUT accepté)
//! - `DELETE /api/auto-rules/{id}`                         supprime la règle
//! - `GET    /api/auto-rules/{id}/games?days=21`           matchs à venir
//! - `POST   /api/auto-rules/{id}/games/{game}/decision`   oui / non / auto
//! - `GET    /api/auto-rules/{id}/games/{game}/artwork`    vignette (`?kind=poster`)
//! - `GET    /api/auto-rules/{id}/channels`                beIN détectées
//! - `POST   /api/auto-rules/{id}/refresh`                 recharge maintenant

use crate::http::{self, Req, Resp, json, segments};
use crate::models::{AutoRule, NbaGame, User};
use crate::services::recording_scheduler::recordings_dir_path;
use crate::services::{bein_channels, nba_artwork, nba_autorec};
use crate::state::SharedState;
use chrono::{Duration, Utc};
use serde_json::{Map, Value, json};
use std::path::PathBuf;

fn can_access(user: Option<&User>, rule: &AutoRule) -> bool {
    user.is_some_and(|u| u.is_admin || rule.user_id == u.id)
}

pub async fn auto_rules(state: &SharedState, req: &Req, rest: &str) -> Resp {
    let Some(user) = req.user.clone() else {
        return json(401, &json!({"error": "Authentification requise"}));
    };
    let parts = segments(rest);
    if let ("GET" | "HEAD", []) = (req.method.as_str(), parts.as_slice()) {
        // Une règle NBA par IPTV : celle de la playlist choisie.
        let rules = match state.selected_playlist_id(req) {
            Some(pid) => state.db.get_auto_rules_for_playlist(&user.id, &pid),
            None => state.db.get_auto_rules_for_user(&user.id),
        };
        return json(200, &json!(rules));
    }
    if let ("POST", []) = (req.method.as_str(), parts.as_slice()) {
        return create(state, req, &user).await;
    }
    let Some(id) = parts.first() else {
        return http::not_found();
    };
    let Some(rule) = state.db.get_auto_rule(id) else {
        return json(404, &json!({"error": "Règle non trouvée"}));
    };
    if !can_access(Some(&user), &rule) {
        return json(403, &json!({"error": "Accès refusé"}));
    }
    match (req.method.as_str(), &parts[1..]) {
        ("PATCH" | "PUT", []) => update(state, req, rule).await,
        ("DELETE", []) => {
            state.db.delete_auto_rule(&rule.id);
            json(200, &json!({"message": "Règle supprimée"}))
        }
        ("GET" | "HEAD", ["games"]) => games(state, req, &rule),
        ("POST", ["games", game_id, "decision"]) => decision(state, req, &rule, game_id).await,
        ("GET" | "HEAD", ["games", game_id, "artwork"]) => {
            artwork(state, req, &rule, game_id).await
        }
        ("GET" | "HEAD", ["channels"]) => channels(state, req, &rule).await,
        ("POST", ["refresh"]) => {
            state.nba.refresh_rule(&rule).await;
            state.nba.reconcile(&rule).await;
            games(state, req, &rule)
        }
        _ => http::not_found(),
    }
}

fn body_map(req: &Req) -> Result<Map<String, Value>, Resp> {
    if req.body.is_empty() {
        return Ok(Map::new());
    }
    match serde_json::from_slice::<Value>(&req.body) {
        Ok(Value::Object(map)) => Ok(map),
        _ => Err(json(400, &json!({"error": "Corps JSON invalide"}))),
    }
}

fn string_list(v: &Value) -> Option<Vec<String>> {
    v.as_array().map(|a| {
        a.iter()
            .filter_map(|x| match x {
                Value::String(s) => Some(s.trim().to_string()),
                Value::Number(n) => Some(n.to_string()),
                _ => None,
            })
            .filter(|s| !s.is_empty())
            .collect()
    })
}

/// Applique les champs présents du corps à la règle. Erreur 400 si invalide.
fn apply_fields(rule: &mut AutoRule, body: &Map<String, Value>) -> Result<(), Resp> {
    let bad = |msg: &str| Err(json(400, &json!({"error": msg})));
    if let Some(v) = body.get("enabled") {
        let Some(b) = v.as_bool() else {
            return bad("enabled doit être un booléen");
        };
        rule.enabled = b;
    }
    if let Some(v) = body.get("default_decision") {
        match v.as_str() {
            Some(d @ ("auto" | "ask")) => rule.default_decision = d.into(),
            _ => return bad("default_decision : 'auto' ou 'ask'"),
        }
    }
    if let Some(v) = body.get("channel_ids") {
        let Some(list) = string_list(v) else {
            return bad("channel_ids doit être une liste");
        };
        rule.channel_ids = list;
    }
    if let Some(v) = body.get("team_filter") {
        let Some(list) = string_list(v) else {
            return bad("team_filter doit être une liste");
        };
        rule.team_filter = list;
    }
    for (key, slot) in [
        ("pad_before_min", &mut rule.pad_before_min),
        ("pad_after_min", &mut rule.pad_after_min),
    ] {
        if let Some(v) = body.get(key) {
            match v.as_i64() {
                Some(n) if (0..=180).contains(&n) => *slot = n,
                _ => return bad("marges : entier entre 0 et 180 minutes"),
            }
        }
    }
    if let Some(v) = body.get("keep_days") {
        rule.keep_days = match v {
            Value::Null => None,
            other => match other.as_i64() {
                Some(n) if n > 0 => Some(n),
                _ => return bad("keep_days : entier positif ou null"),
            },
        };
    }
    Ok(())
}

async fn create(state: &SharedState, req: &Req, user: &User) -> Resp {
    let body = match body_map(req) {
        Ok(b) => b,
        Err(r) => return r,
    };
    let playlist_id = state
        .get_playlist(req)
        .map(|p| p.id)
        .filter(|id| !id.is_empty());
    let existing = match &playlist_id {
        Some(pid) => state.db.get_auto_rules_for_playlist(&user.id, pid),
        None => state.db.get_auto_rules_for_user(&user.id),
    };
    if existing.iter().any(|r| r.kind == "nba") {
        return json(409, &json!({"error": "La règle NBA existe déjà"}));
    }
    let mut rule = AutoRule {
        id: String::new(),
        user_id: user.id.clone(),
        kind: "nba".into(),
        enabled: true,
        // Plus de programmation automatique : seul un oui enregistre.
        default_decision: "ask".into(),
        channel_ids: Vec::new(),
        pad_before_min: 5,
        pad_after_min: 45,
        team_filter: Vec::new(),
        keep_days: None,
        playlist_id: playlist_id.clone(),
        created_at: String::new(),
        updated_at: String::new(),
    };
    if let Err(r) = apply_fields(&mut rule, &body) {
        return r;
    }
    // Sans liste explicite : les beIN Sports FR détectées, meilleure qualité.
    if !body.contains_key("channel_ids")
        && let Some(playlist) = state.get_playlist(req)
    {
        let table = bein_channels::fetch_live_table(&state.http, &playlist).await;
        rule.channel_ids = bein_channels::preferred_fr(&bein_channels::detect(&table))
            .into_iter()
            .map(|c| c.stream_id)
            .collect();
    }
    let rule = match state.db.create_auto_rule(&rule) {
        Ok(r) => r,
        // Activation concurrente (deux onglets, relance) : l'index unique
        // (user_id, kind) a tranché.
        Err(e) if crate::db::is_unique_violation(&e) => {
            return json(409, &json!({"error": "La règle NBA existe déjà"}));
        }
        Err(e) => return json(500, &json!({"error": format!("Création impossible : {e}")})),
    };
    // Calendrier et première réconciliation en tâche de fond (≈ 20 requêtes).
    let nba = state.nba.clone();
    let spawned = rule.clone();
    tokio::spawn(async move {
        nba.refresh_rule(&spawned).await;
        nba.reconcile(&spawned).await;
    });
    json(201, &json!(rule))
}

async fn update(state: &SharedState, req: &Req, mut rule: AutoRule) -> Resp {
    let body = match body_map(req) {
        Ok(b) => b,
        Err(r) => return r,
    };
    let was_enabled = rule.enabled;
    if let Err(r) = apply_fields(&mut rule, &body) {
        return r;
    }
    if let Err(e) = state.db.update_auto_rule(&rule) {
        return json(
            500,
            &json!({"error": format!("Mise à jour impossible : {e}")}),
        );
    }
    let nba = state.nba.clone();
    let spawned = rule.clone();
    tokio::spawn(async move {
        if spawned.enabled && !was_enabled {
            nba.refresh_rule(&spawned).await;
        }
        nba.reconcile(&spawned).await;
    });
    json(200, &json!(rule))
}

fn game_json(rule: &AutoRule, g: &NbaGame, slot_taken_by: Option<String>) -> Value {
    let rule_id = &rule.id;
    let mut v = json!(g);
    if let Value::Object(map) = &mut v {
        map.insert(
            "artwork_url".into(),
            json!(format!(
                "/api/auto-rules/{rule_id}/games/{}/artwork",
                g.game_id
            )),
        );
        // Choisi par l'utilisateur : seul un oui explicite enregistre.
        map.insert("wanted".into(), json!(nba_autorec::wants(g)));
        // Un seul flux IPTV : ce qui occupe déjà le créneau, s'il est pris.
        map.insert("slot_taken_by".into(), json!(slot_taken_by));
        map.insert("title".into(), json!(nba_autorec::recording_title(g)));
    }
    v
}

fn games(state: &SharedState, req: &Req, rule: &AutoRule) -> Resp {
    let days = req
        .query_param("days")
        .and_then(|d| d.parse::<i64>().ok())
        .unwrap_or(21)
        .clamp(1, 60);
    let now = Utc::now();
    let all = state.db.get_nba_games(
        &rule.id,
        now - Duration::hours(6),
        now + Duration::days(days),
    );
    let pending = state.db.get_pending_recordings();
    let list: Vec<Value> = all
        .iter()
        .map(|g| {
            let taken = (!nba_autorec::wants(g))
                .then(|| nba_autorec::slot_taken_by(rule, g, &all, &pending))
                .flatten();
            game_json(rule, g, taken)
        })
        .collect();
    json(
        200,
        &json!({"rule": rule, "games": list, "diagnostic": state.nba.diagnostic(&rule.id)}),
    )
}

async fn decision(state: &SharedState, req: &Req, rule: &AutoRule, game_id: &str) -> Resp {
    let body = match body_map(req) {
        Ok(b) => b,
        Err(r) => return r,
    };
    let decision = match body.get("decision").and_then(Value::as_str) {
        Some(d @ ("accepted" | "refused" | "auto")) => d,
        _ => {
            return json(
                400,
                &json!({"error": "decision : 'accepted', 'refused' ou 'auto'"}),
            );
        }
    };
    // Un seul flux IPTV à la fois : refuser un oui sur un créneau occupé.
    if decision == "accepted" {
        let Some(game) = state.db.get_nba_game(&rule.id, game_id) else {
            return json(404, &json!({"error": "Match non trouvé"}));
        };
        let now = Utc::now();
        let all =
            state
                .db
                .get_nba_games(&rule.id, now - Duration::hours(6), now + Duration::days(60));
        let pending = state.db.get_pending_recordings();
        if let Some(taken) = nba_autorec::slot_taken_by(rule, &game, &all, &pending) {
            return json(
                409,
                &json!({
                    "error": format!(
                        "Créneau déjà pris par « {taken} » : un seul enregistrement à la fois"
                    ),
                    "slot_taken_by": taken,
                }),
            );
        }
    }
    if !state.db.set_nba_decision(&rule.id, game_id, decision) {
        return json(404, &json!({"error": "Match non trouvé"}));
    }
    // Appliquer tout de suite (programmer ou supprimer l'enregistrement),
    // dans la limite de 20 s : l'EPG est normalement en cache.
    let _ = tokio::time::timeout(
        std::time::Duration::from_secs(20),
        state.nba.reconcile(rule),
    )
    .await;
    match state.db.get_nba_game(&rule.id, game_id) {
        Some(g) => json(200, &game_json(rule, &g, None)),
        None => json(404, &json!({"error": "Match non trouvé"})),
    }
}

async fn artwork(state: &SharedState, req: &Req, rule: &AutoRule, game_id: &str) -> Resp {
    let Some(game) = state.db.get_nba_game(&rule.id, game_id) else {
        return json(404, &json!({"error": "Match non trouvé"}));
    };
    let poster = req.query_param("kind").as_deref() == Some("poster");
    let dir = PathBuf::from(recordings_dir_path());
    let safe_id: String = game_id
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    let cached = nba_artwork::artwork_dir(&dir).join(format!(
        "{safe_id}-{}.jpg",
        if poster { "poster" } else { "thumb" }
    ));
    let path = if cached.exists() {
        Some(cached)
    } else {
        nba_artwork::ensure_artwork(&state.http, &dir, &game)
            .await
            .map(|(t, p)| if poster { p } else { t })
    };
    match path.map(std::fs::read) {
        Some(Ok(bytes)) => http::with_headers(
            http::response(200, bytes),
            &[
                ("content-type", "image/jpeg"),
                ("cache-control", "private, max-age=3600"),
            ],
        ),
        _ => json(404, &json!({"error": "Vignette indisponible"})),
    }
}

async fn channels(state: &SharedState, req: &Req, rule: &AutoRule) -> Resp {
    let Some(playlist) = state.get_playlist(req) else {
        return json(403, &json!({"error": "Playlist non trouvée"}));
    };
    let table = bein_channels::fetch_live_table(&state.http, &playlist).await;
    let detected = bein_channels::detect(&table);
    let list: Vec<Value> = detected
        .iter()
        .map(|c| {
            let mut v = json!(c);
            if let Value::Object(m) = &mut v {
                m.insert(
                    "selected".into(),
                    json!(rule.channel_ids.contains(&c.stream_id)),
                );
            }
            v
        })
        .collect();
    json(200, &json!({"channels": list}))
}
