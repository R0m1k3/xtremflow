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
