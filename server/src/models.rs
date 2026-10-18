//! Modèles de données, sérialisés exactement comme l'ancien serveur Dart
//! (noms de champs, formats de dates) : le front Flutter n'a pas changé.

use crate::dart_time::DartDateTime;
use serde_json::{Map, Value, json};

#[derive(Clone, Debug)]
pub struct User {
    pub id: String,
    pub username: String,
    pub is_admin: bool,
    pub created_at: DartDateTime,
}

impl User {
    pub fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "username": self.username,
            "isAdmin": self.is_admin,
            "createdAt": self.created_at.to_iso(),
        })
    }
}

#[derive(Clone, Debug)]
pub struct Playlist {
    pub id: String,
    pub user_id: String,
    pub name: String,
    pub server_url: String,
    pub username: String,
    pub password: String,
    pub dns: Option<String>,
    pub created_at: DartDateTime,
    pub updated_at: DartDateTime,
}

impl Playlist {
    pub fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "userId": self.user_id,
            "name": self.name,
            "serverUrl": self.server_url,
            "username": self.username,
            // Le mot de passe Xtream n'est jamais exposé aux clients : le
            // serveur injecte les identifiants lui-même (voir xtream_api).
            "password": "",
            "dns": self.dns,
            "createdAt": self.created_at.to_iso(),
            "updatedAt": self.updated_at.to_iso(),
        })
    }
}

#[derive(Clone, Debug)]
pub struct Session {
    pub user_id: String,
    pub token: String,
    pub expires_at: DartDateTime,
}

impl Session {
    pub fn is_expired(&self) -> bool {
        chrono::Utc::now() > self.expires_at.to_utc()
    }
}

/// Configuration Xtream utilisée par les proxys et le streaming.
#[derive(Clone, Debug)]
pub struct PlaylistConfig {
    /// URL du serveur Xtream (sans `/` final).
    pub dns: String,
    pub username: String,
    pub password: String,
}

#[derive(Clone, Debug)]
pub struct Recording {
    pub id: String,
    pub user_id: String,
    pub channel_id: String,
    pub stream_url: String,
    pub title: String,
    pub start_time: DartDateTime,
    pub end_time: DartDateTime,
    /// 'scheduled', 'recording', 'completed', 'failed', 'cancelled'
    pub status: String,
    pub file_path: Option<String>,
    pub error_reason: Option<String>,
    /// Règle automatique à l'origine de l'enregistrement (None = manuel/season pass).
    pub source_rule_id: Option<String>,
    pub created_at: DartDateTime,
    pub updated_at: DartDateTime,
}

impl Recording {
    pub fn to_map(&self) -> Map<String, Value> {
        let mut map = Map::new();
        map.insert("id".into(), json!(self.id));
        map.insert("user_id".into(), json!(self.user_id));
        map.insert("channel_id".into(), json!(self.channel_id));
        map.insert("stream_url".into(), json!(self.stream_url));
        map.insert("title".into(), json!(self.title));
        map.insert("start_time".into(), json!(self.start_time.to_iso()));
        map.insert("end_time".into(), json!(self.end_time.to_iso()));
        map.insert("status".into(), json!(self.status));
        map.insert("file_path".into(), json!(self.file_path));
        map.insert("error_reason".into(), json!(self.error_reason));
        map.insert("source_rule_id".into(), json!(self.source_rule_id));
        map.insert("created_at".into(), json!(self.created_at.to_iso()));
        map.insert("updated_at".into(), json!(self.updated_at.to_iso()));
        map
    }

    pub fn start_utc(&self) -> chrono::DateTime<chrono::Utc> {
        self.start_time.to_utc()
    }

    pub fn end_utc(&self) -> chrono::DateTime<chrono::Utc> {
        self.end_time.to_utc()
    }
}

/// Règle d'enregistrement automatique (aujourd'hui : NBA sur beIN Sports FR).
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct AutoRule {
    pub id: String,
    pub user_id: String,
    /// Type de règle ; seul 'nba' existe pour l'instant.
    pub kind: String,
    pub enabled: bool,
    /// 'auto' : programmé sans validation (veto possible) ; 'ask' : attend un oui.
    pub default_decision: String,
    /// stream_ids des chaînes surveillées (beIN Sports FR retenus).
    pub channel_ids: Vec<String>,
    pub pad_before_min: i64,
    pub pad_after_min: i64,
    /// Noms d'équipes à suivre ; vide = toutes.
    pub team_filter: Vec<String>,
    /// Rétention en jours des fichiers créés par la règle ; None = illimitée.
    pub keep_days: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
}

/// Un match NBA connu d'une règle, de l'annonce au calendrier jusqu'au fichier.
#[derive(Clone, Debug, serde::Serialize, PartialEq)]
pub struct NbaGame {
    pub game_id: String,
    pub rule_id: String,
    pub home: String,
    pub away: String,
    pub home_id: String,
    pub away_id: String,
    pub home_tri: String,
    pub away_tri: String,
    /// Coup d'envoi officiel, ISO UTC.
    pub tipoff_utc: String,
    /// provisional | confirmed | scheduled | recorded | missed | not_on_bein
    pub status: String,
    /// auto | accepted | refused
    pub decision: String,
    pub channel_id: Option<String>,
    pub channel_name: Option<String>,
    pub epg_title: Option<String>,
    pub epg_start: Option<String>,
    pub epg_end: Option<String>,
    pub recording_id: Option<String>,
    pub confidence: Option<i64>,
    /// Pas de créneau d'enregistrement libre (MAX_CONCURRENT_RECORDINGS).
    pub conflict: bool,
    pub updated_at: String,
}

/// Match tel que publié par le calendrier officiel (avant toute décision).
#[derive(Clone, Debug, PartialEq)]
pub struct ScheduledGame {
    pub game_id: String,
    pub home: String,
    pub away: String,
    pub home_id: String,
    pub away_id: String,
    pub home_tri: String,
    pub away_tri: String,
    pub tipoff_utc: chrono::DateTime<chrono::Utc>,
}
