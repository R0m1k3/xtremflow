//! Base SQLite (`/app/data/xtremflow.db`).
//!
//! Schéma, migrations et formats de dates identiques à l'ancien serveur
//! Dart : la base de production est reprise telle quelle au premier
//! démarrage du serveur Rust.

use crate::dart_time::{DartDateTime, now_local_iso, utc_iso};
use crate::models::{Playlist, Recording, Session, User};
use crate::util::password;
use chrono::{DateTime, Duration, Utc};
use regex::Regex;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OptionalExtension, Row, params};
use serde_json::{Map, Value};
use std::sync::{LazyLock, Mutex};

pub struct AppDatabase {
    conn: Mutex<Connection>,
}

type DbResult<T> = Result<T, rusqlite::Error>;

fn parse_date(raw: Option<String>) -> DartDateTime {
    raw.as_deref()
        .and_then(DartDateTime::parse)
        .unwrap_or_else(DartDateTime::now_local)
}

fn user_from_row(row: &Row) -> DbResult<User> {
    Ok(User {
        id: row.get("id")?,
        username: row.get("username")?,
        is_admin: row.get::<_, Option<i64>>("is_admin")?.unwrap_or(0) == 1,
        created_at: parse_date(row.get("created_at")?),
    })
}

fn playlist_from_row(row: &Row) -> DbResult<Playlist> {
    Ok(Playlist {
        id: row.get("id")?,
        user_id: row.get("user_id")?,
        name: row.get("name")?,
        server_url: row.get("server_url")?,
        username: row.get("username")?,
        password: row.get("password")?,
        dns: row.get("dns")?,
        created_at: parse_date(row.get("created_at")?),
        updated_at: parse_date(row.get("updated_at")?),
    })
}

fn recording_from_row(row: &Row) -> DbResult<Recording> {
    let text = |name: &str| -> DbResult<String> {
        Ok(row.get::<_, Option<String>>(name)?.unwrap_or_default())
    };
    Ok(Recording {
        id: text("id")?,
        user_id: text("user_id")?,
        channel_id: text("channel_id")?,
        stream_url: text("stream_url")?,
        title: text("title")?,
        start_time: parse_date(row.get("start_time")?),
        end_time: parse_date(row.get("end_time")?),
        status: row
            .get::<_, Option<String>>("status")?
            .unwrap_or_else(|| "scheduled".into()),
        file_path: row.get("file_path")?,
        error_reason: row.get("error_reason")?,
        created_at: parse_date(row.get("created_at")?),
        updated_at: parse_date(row.get("updated_at")?),
    })
}

/// Ligne brute → objet JSON (colonnes dans l'ordre de la table).
fn row_to_json(row: &Row) -> DbResult<Map<String, Value>> {
    let mut map = Map::new();
    let stmt = row.as_ref();
    for i in 0..stmt.column_count() {
        let name = stmt.column_name(i)?.to_string();
        let value = match row.get_ref(i)? {
            ValueRef::Null => Value::Null,
            ValueRef::Integer(v) => Value::from(v),
            ValueRef::Real(v) => Value::from(v),
            ValueRef::Text(v) => Value::from(String::from_utf8_lossy(v).into_owned()),
            ValueRef::Blob(v) => Value::from(String::from_utf8_lossy(v).into_owned()),
        };
        map.insert(name, value);
    }
    Ok(map)
}

/// Mot de passe initial sans caractères ambigus (0/O, 1/l/I) : il est
/// recopié depuis les logs du conteneur.
fn generate_password(length: usize) -> String {
    const CHARS: &[u8] = b"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut out = String::with_capacity(length);
    while out.len() < length {
        // Octets aléatoires du générateur système (via UUID v4), tirage par
        // rejet pour une distribution uniforme.
        for byte in uuid::Uuid::new_v4().into_bytes() {
            let limit = 256 - (256 % CHARS.len());
            if (byte as usize) < limit && out.len() < length {
                out.push(CHARS[byte as usize % CHARS.len()] as char);
            }
        }
    }
    out
}

static GPU_SETTING: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"(?i)"enable_nvidia_gpu"\s*:\s*true"#).unwrap());

impl AppDatabase {
    /// Ouvre (ou crée) la base et applique schéma et migrations.
    pub fn open(path: &str) -> DbResult<Self> {
        if let Some(dir) = std::path::Path::new(path).parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let conn = Connection::open(path)?;
        // Sans foreign_keys, les ON DELETE CASCADE déclarés dans le schéma sont
        // ignorés par SQLite : supprimer un utilisateur laissait ses sessions
        // (donc des jetons valides), playlists et enregistrements orphelins.
        conn.execute_batch(
            "PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;",
        )?;
        let db = Self {
            conn: Mutex::new(conn),
        };
        db.create_tables()?;
        db.run_migrations()?;
        println!("Database initialized: {path}");
        Ok(db)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn create_tables(&self) -> DbResult<()> {
        self.lock().execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              username TEXT UNIQUE NOT NULL,
              password_hash TEXT NOT NULL,
              is_admin INTEGER DEFAULT 0,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS playlists (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              name TEXT NOT NULL,
              server_url TEXT NOT NULL,
              username TEXT NOT NULL,
              password TEXT NOT NULL,
              dns TEXT,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              token TEXT UNIQUE NOT NULL,
              expires_at TEXT NOT NULL,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS user_settings (
              user_id TEXT PRIMARY KEY,
              settings_json TEXT NOT NULL,
              updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS tv_recordings (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              channel_id TEXT NOT NULL,
              stream_url TEXT NOT NULL,
              title TEXT NOT NULL,
              start_time TEXT NOT NULL,
              end_time TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'scheduled',
              file_path TEXT,
              error_reason TEXT,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS season_passes (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              show_title TEXT NOT NULL,
              channel_id TEXT NOT NULL,
              stream_url TEXT NOT NULL,
              enabled INTEGER DEFAULT 1,
              match_mode TEXT NOT NULL DEFAULT 'exact',
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token);
            CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);
            CREATE INDEX IF NOT EXISTS idx_playlists_user ON playlists(user_id);
            CREATE INDEX IF NOT EXISTS idx_recordings_status ON tv_recordings(status);
            CREATE INDEX IF NOT EXISTS idx_recordings_user ON tv_recordings(user_id);
            CREATE INDEX IF NOT EXISTS idx_recordings_start ON tv_recordings(start_time);
            CREATE INDEX IF NOT EXISTS idx_season_passes_user ON season_passes(user_id);
            "#,
        )
    }

    /// Migrations de schéma pour les bases créées par une version antérieure.
    ///
    /// `CREATE TABLE IF NOT EXISTS` n'ajoute jamais de colonne à une table
    /// existante : chaque colonne introduite après coup a sa migration,
    /// numérotée et rejouée uniquement si nécessaire.
    fn run_migrations(&self) -> DbResult<()> {
        let conn = self.lock();
        conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)",
            [],
        )?;
        let mut current: i64 = conn.query_row(
            "SELECT COALESCE(MAX(version), 0) AS v FROM schema_version",
            [],
            |r| r.get(0),
        )?;

        let migrations: [(i64, &str, &str, &str); 2] = [
            // v1 : colonne error_reason absente des bases d'avant son introduction.
            (1, "tv_recordings", "error_reason", "TEXT"),
            // v2 : mode de correspondance des season passes. 'contains' pour les
            // lignes existantes (comportement historique) ; les nouvelles
            // créations passent par l'API qui choisit 'exact' par défaut.
            (
                2,
                "season_passes",
                "match_mode",
                "TEXT NOT NULL DEFAULT 'contains'",
            ),
        ];
        for (version, table, column, definition) in migrations {
            if version <= current {
                continue;
            }
            let exists = {
                let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
                let names = stmt.query_map([], |r| r.get::<_, String>("name"))?;
                let mut found = false;
                for name in names {
                    if name? == column {
                        found = true;
                    }
                }
                found
            };
            if !exists {
                conn.execute(
                    &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
                    [],
                )?;
            }
            conn.execute("INSERT INTO schema_version (version) VALUES (?)", [version])?;
            current = version;
            println!("[DB] Migration v{version} appliquée");
        }
        Ok(())
    }

    /// Crée le compte admin s'il n'existe aucun utilisateur.
    ///
    /// Le mot de passe initial vient de ADMIN_INITIAL_PASSWORD, ou est généré
    /// aléatoirement et affiché UNE FOIS dans les logs de démarrage.
    pub fn seed_admin(&self) -> DbResult<()> {
        let count: i64 = self
            .lock()
            .query_row("SELECT COUNT(*) as count FROM users", [], |r| r.get(0))?;
        if count != 0 {
            return Ok(());
        }
        let env_password = std::env::var("ADMIN_INITIAL_PASSWORD").unwrap_or_default();
        let generated = env_password.is_empty();
        let password = if generated {
            generate_password(16)
        } else {
            env_password
        };
        let hash = password::hash(&password).expect("bcrypt");
        self.lock().execute(
            "INSERT INTO users (id, username, password_hash, is_admin) VALUES (?, ?, ?, 1)",
            params![uuid::Uuid::new_v4().to_string(), "admin", hash],
        )?;
        if generated {
            println!("╔══════════════════════════════════════════════════════════╗");
            println!("  Compte admin créé — mot de passe initial (affiché une");
            println!("  seule fois, changez-le après la première connexion) :");
            println!("  utilisateur: admin");
            println!("  mot de passe: {password}");
            println!("╚══════════════════════════════════════════════════════════╝");
        } else {
            println!(
                "Default admin user created (username: admin, password: ADMIN_INITIAL_PASSWORD)"
            );
        }
        Ok(())
    }

    // ==================== Users ====================

    pub fn find_user_by_username(&self, username: &str) -> Option<User> {
        self.lock()
            .query_row(
                "SELECT * FROM users WHERE username = ?",
                [username],
                user_from_row,
            )
            .optional()
            .ok()
            .flatten()
    }

    pub fn find_user_by_id(&self, user_id: &str) -> Option<User> {
        self.lock()
            .query_row("SELECT * FROM users WHERE id = ?", [user_id], user_from_row)
            .optional()
            .ok()
            .flatten()
    }

    /// Vérifie les identifiants. Le hachage bcrypt (coûteux) est fait hors
    /// du verrou de la base : à appeler depuis `spawn_blocking`.
    pub fn verify_credentials(&self, username: &str, password: &str) -> Option<User> {
        let (user, stored) = self
            .lock()
            .query_row(
                "SELECT * FROM users WHERE username = ?",
                [username],
                |row| Ok((user_from_row(row)?, row.get::<_, String>("password_hash")?)),
            )
            .optional()
            .ok()
            .flatten()?;

        if !password::verify(password, &stored) {
            return None;
        }

        // Migration paresseuse : les anciens hachages SHA-256 sont refaits en
        // bcrypt à la connexion (seul moment où le mot de passe est connu).
        if password::is_legacy(&stored)
            && let Ok(hash) = password::hash(password)
        {
            self.update_password_hash(&user.id, &hash);
            println!("[Auth] Migrated legacy password hash for user: {username}");
        }
        Some(user)
    }

    pub fn update_password_hash(&self, user_id: &str, hash: &str) {
        let _ = self.lock().execute(
            "UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            params![hash, user_id],
        );
    }

    /// Crée un utilisateur ; [password_hash] est déjà calculé par l'appelant.
    pub fn create_user(
        &self,
        username: &str,
        password_hash: &str,
        is_admin: bool,
    ) -> DbResult<User> {
        let id = uuid::Uuid::new_v4().to_string();
        self.lock().execute(
            "INSERT INTO users (id, username, password_hash, is_admin) VALUES (?, ?, ?, ?)",
            params![id, username, password_hash, is_admin as i64],
        )?;
        Ok(User {
            id,
            username: username.to_string(),
            is_admin,
            created_at: DartDateTime::now_local(),
        })
    }

    pub fn get_all_users(&self) -> Vec<User> {
        let conn = self.lock();
        let Ok(mut stmt) = conn.prepare("SELECT * FROM users ORDER BY username ASC") else {
            return Vec::new();
        };
        stmt.query_map([], user_from_row)
            .map(|rows| rows.filter_map(Result::ok).collect())
            .unwrap_or_default()
    }

    pub fn update_user_admin_status(&self, user_id: &str, is_admin: bool) -> DbResult<()> {
        self.lock().execute(
            "UPDATE users SET is_admin = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            params![is_admin as i64, user_id],
        )?;
        Ok(())
    }

    pub fn delete_user(&self, user_id: &str) -> DbResult<()> {
        self.lock()
            .execute("DELETE FROM users WHERE id = ?", [user_id])?;
        Ok(())
    }

    // ==================== Sessions ====================

    pub fn create_session(&self, user_id: &str) -> DbResult<Session> {
        let token = uuid::Uuid::new_v4().to_string();
        let expires_at = DartDateTime::now_local().add(Duration::days(7));
        self.lock().execute(
            "INSERT INTO sessions (id, user_id, token, expires_at) VALUES (?, ?, ?, ?)",
            params![
                uuid::Uuid::new_v4().to_string(),
                user_id,
                token,
                expires_at.to_iso()
            ],
        )?;
        Ok(Session {
            user_id: user_id.to_string(),
            token,
            expires_at,
        })
    }

    /// Session valide pour [token] ; une session expirée est supprimée.
    pub fn find_session_by_token(&self, token: &str) -> Option<Session> {
        let session = self
            .lock()
            .query_row("SELECT * FROM sessions WHERE token = ?", [token], |row| {
                Ok(Session {
                    user_id: row.get("user_id")?,
                    token: row.get("token")?,
                    expires_at: parse_date(row.get("expires_at")?),
                })
            })
            .optional()
            .ok()
            .flatten()?;
        if session.is_expired() {
            self.delete_session(token);
            return None;
        }
        Some(session)
    }

    pub fn delete_session(&self, token: &str) {
        let _ = self
            .lock()
            .execute("DELETE FROM sessions WHERE token = ?", [token]);
    }

    pub fn clean_expired_sessions(&self) {
        let _ = self.lock().execute(
            "DELETE FROM sessions WHERE expires_at < ?",
            [now_local_iso()],
        );
    }

    // ==================== Playlists ====================

    pub fn get_playlists(&self, user_id: &str) -> Vec<Playlist> {
        let conn = self.lock();
        let Ok(mut stmt) =
            conn.prepare("SELECT * FROM playlists WHERE user_id = ? ORDER BY created_at DESC")
        else {
            return Vec::new();
        };
        stmt.query_map([user_id], playlist_from_row)
            .map(|rows| rows.filter_map(Result::ok).collect())
            .unwrap_or_default()
    }

    pub fn get_playlist_by_id(&self, id: &str) -> Option<Playlist> {
        self.lock()
            .query_row(
                "SELECT * FROM playlists WHERE id = ?",
                [id],
                playlist_from_row,
            )
            .optional()
            .ok()
            .flatten()
    }

    #[allow(clippy::too_many_arguments)]
    pub fn create_playlist(
        &self,
        user_id: &str,
        name: &str,
        server_url: &str,
        username: &str,
        password: &str,
        dns: Option<&str>,
    ) -> DbResult<Playlist> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = DartDateTime::now_local();
        let now_iso = now.to_iso();
        self.lock().execute(
            "INSERT INTO playlists (id, user_id, name, server_url, username, password, dns, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![id, user_id, name, server_url, username, password, dns, now_iso, now_iso],
        )?;
        Ok(Playlist {
            id,
            user_id: user_id.into(),
            name: name.into(),
            server_url: server_url.into(),
            username: username.into(),
            password: password.into(),
            dns: dns.map(str::to_string),
            created_at: now,
            updated_at: now,
        })
    }

    pub fn update_playlist(
        &self,
        id: &str,
        name: &str,
        server_url: &str,
        username: &str,
        password: &str,
        dns: Option<&str>,
    ) -> DbResult<Option<Playlist>> {
        self.lock().execute(
            "UPDATE playlists SET name = ?, server_url = ?, username = ?, password = ?, dns = ?, updated_at = ? WHERE id = ?",
            params![name, server_url, username, password, dns, now_local_iso(), id],
        )?;
        Ok(self.get_playlist_by_id(id))
    }

    pub fn delete_playlist(&self, id: &str) -> DbResult<()> {
        self.lock()
            .execute("DELETE FROM playlists WHERE id = ?", [id])?;
        Ok(())
    }

    // ==================== User Settings ====================

    pub fn get_user_settings(&self, user_id: &str) -> Option<String> {
        self.lock()
            .query_row(
                "SELECT settings_json FROM user_settings WHERE user_id = ?",
                [user_id],
                |r| r.get(0),
            )
            .optional()
            .ok()
            .flatten()
    }

    pub fn update_user_settings(&self, user_id: &str, json: &str) -> DbResult<()> {
        self.lock().execute(
            "INSERT INTO user_settings (user_id, settings_json, updated_at) VALUES (?, ?, ?)
             ON CONFLICT(user_id) DO UPDATE SET settings_json = excluded.settings_json, updated_at = excluded.updated_at",
            params![user_id, json, now_local_iso()],
        )?;
        Ok(())
    }

    /// Réglage GPU NVIDIA, global au serveur : celui des derniers réglages
    /// enregistrés, tous utilisateurs confondus.
    pub fn is_nvidia_gpu_enabled(&self) -> bool {
        let settings: Option<String> = self
            .lock()
            .query_row(
                "SELECT settings_json FROM user_settings ORDER BY updated_at DESC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .optional()
            .ok()
            .flatten();
        settings.is_some_and(|json| GPU_SETTING.is_match(&json))
    }

    // ==================== TV Recordings ====================

    pub fn create_recording(
        &self,
        user_id: &str,
        channel_id: &str,
        stream_url: &str,
        title: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> DbResult<Recording> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = DartDateTime::now_local();
        // Toujours stocker en UTC avec suffixe 'Z' : les comparaisons du
        // scheduler et la déduplication des season passes reposent sur ce
        // format unique.
        let start = DartDateTime::from_utc(start);
        let end = DartDateTime::from_utc(end);
        self.lock().execute(
            "INSERT INTO tv_recordings (id, user_id, channel_id, stream_url, title, start_time, end_time, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![
                id,
                user_id,
                channel_id,
                stream_url,
                title,
                start.to_iso(),
                end.to_iso(),
                now.to_iso(),
                now.to_iso()
            ],
        )?;
        Ok(Recording {
            id,
            user_id: user_id.into(),
            channel_id: channel_id.into(),
            stream_url: stream_url.into(),
            title: title.into(),
            start_time: start,
            end_time: end,
            status: "scheduled".into(),
            file_path: None,
            error_reason: None,
            created_at: now,
            updated_at: now,
        })
    }

    fn query_recordings(&self, sql: &str, args: &[&str]) -> Vec<Recording> {
        let conn = self.lock();
        let Ok(mut stmt) = conn.prepare(sql) else {
            return Vec::new();
        };
        stmt.query_map(rusqlite::params_from_iter(args.iter()), recording_from_row)
            .map(|rows| rows.filter_map(Result::ok).collect())
            .unwrap_or_default()
    }

    pub fn get_all_recordings(&self) -> Vec<Recording> {
        self.query_recordings("SELECT * FROM tv_recordings ORDER BY start_time ASC", &[])
    }

    /// Enregistrements qui intéressent le scheduler : à lancer ou en cours.
    pub fn get_pending_recordings(&self) -> Vec<Recording> {
        self.query_recordings(
            "SELECT * FROM tv_recordings WHERE status IN ('scheduled', 'recording') ORDER BY start_time ASC",
            &[],
        )
    }

    /// Enregistrements terminés, du plus ancien au plus récent (rotation disque).
    pub fn get_finished_recordings_oldest_first(&self) -> Vec<Recording> {
        self.query_recordings(
            "SELECT * FROM tv_recordings WHERE status IN ('completed', 'failed', 'cancelled') ORDER BY start_time ASC",
            &[],
        )
    }

    pub fn get_user_recordings(&self, user_id: &str) -> Vec<Recording> {
        self.query_recordings(
            "SELECT * FROM tv_recordings WHERE user_id = ? ORDER BY start_time ASC",
            &[user_id],
        )
    }

    pub fn get_recording_by_id(&self, id: &str) -> Option<Recording> {
        self.query_recordings("SELECT * FROM tv_recordings WHERE id = ?", &[id])
            .into_iter()
            .next()
    }

    /// Met à jour le statut et éventuellement le chemin d'un enregistrement.
    ///
    /// [clear_error] efface le motif d'erreur au lieu de conserver l'ancien :
    /// utile quand un enregistrement précédemment en échec est relancé.
    pub fn update_recording_status(
        &self,
        id: &str,
        status: &str,
        file_path: Option<&str>,
        error_reason: Option<&str>,
        clear_error: bool,
    ) {
        let error_expr = if clear_error {
            "?"
        } else {
            "COALESCE(?, error_reason)"
        };
        let sql = format!(
            "UPDATE tv_recordings SET status = ?, file_path = COALESCE(?, file_path), error_reason = {error_expr}, updated_at = ? WHERE id = ?"
        );
        if let Err(e) = self.lock().execute(
            &sql,
            params![status, file_path, error_reason, now_local_iso(), id],
        ) {
            println!("[DB] Mise à jour du statut de {id} impossible: {e}");
        }
    }

    /// Réaligne la fenêtre d'un enregistrement planifié (programme déplacé
    /// dans l'EPG depuis sa création par un season pass).
    pub fn update_recording_window(&self, id: &str, start: DateTime<Utc>, end: DateTime<Utc>) {
        let _ = self.lock().execute(
            "UPDATE tv_recordings SET start_time = ?, end_time = ?, updated_at = ? WHERE id = ?",
            params![utc_iso(start), utc_iso(end), now_local_iso(), id],
        );
    }

    /// Supprime l'enregistrement de la base (pas le fichier).
    pub fn delete_recording(&self, id: &str) {
        let _ = self
            .lock()
            .execute("DELETE FROM tv_recordings WHERE id = ?", [id]);
    }

    // ==================== Season Passes ====================

    pub fn create_season_pass(
        &self,
        user_id: &str,
        show_title: &str,
        channel_id: &str,
        stream_url: &str,
        match_mode: &str,
    ) -> DbResult<Map<String, Value>> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = now_local_iso();
        self.lock().execute(
            "INSERT INTO season_passes (id, user_id, show_title, channel_id, stream_url, match_mode, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            params![id, user_id, show_title, channel_id, stream_url, match_mode, now],
        )?;
        let mut map = Map::new();
        map.insert("id".into(), Value::from(id));
        map.insert("user_id".into(), Value::from(user_id));
        map.insert("show_title".into(), Value::from(show_title));
        map.insert("channel_id".into(), Value::from(channel_id));
        map.insert("stream_url".into(), Value::from(stream_url));
        map.insert("match_mode".into(), Value::from(match_mode));
        map.insert("enabled".into(), Value::from(1));
        map.insert("created_at".into(), Value::from(now));
        Ok(map)
    }

    fn query_json(&self, sql: &str, args: &[&str]) -> Vec<Map<String, Value>> {
        let conn = self.lock();
        let Ok(mut stmt) = conn.prepare(sql) else {
            return Vec::new();
        };
        stmt.query_map(rusqlite::params_from_iter(args.iter()), row_to_json)
            .map(|rows| rows.filter_map(Result::ok).collect())
            .unwrap_or_default()
    }

    /// Season Passes actifs (pour le scheduler).
    pub fn get_all_season_passes(&self) -> Vec<Map<String, Value>> {
        self.query_json(
            "SELECT * FROM season_passes WHERE enabled = 1 ORDER BY created_at DESC",
            &[],
        )
    }

    pub fn get_season_passes_for_user(&self, user_id: &str) -> Vec<Map<String, Value>> {
        self.query_json(
            "SELECT * FROM season_passes WHERE user_id = ? ORDER BY created_at DESC",
            &[user_id],
        )
    }

    pub fn get_season_pass_by_id(&self, id: &str) -> Option<Map<String, Value>> {
        self.query_json("SELECT * FROM season_passes WHERE id = ?", &[id])
            .into_iter()
            .next()
    }

    pub fn delete_season_pass(&self, id: &str) {
        let _ = self
            .lock()
            .execute("DELETE FROM season_passes WHERE id = ?", [id]);
    }

    /// Enregistrement existant pour cet épisode (déduplication des season
    /// passes) : même titre, début à ±[tolerance] près.
    ///
    /// Les dates sont stockées en ISO-8601 UTC : l'ordre lexicographique
    /// correspond à l'ordre chronologique, un BETWEEN sur chaînes suffit.
    pub fn find_recording_for_episode(
        &self,
        title: &str,
        start: DateTime<Utc>,
        tolerance: Duration,
    ) -> Option<Recording> {
        let low = utc_iso(start - tolerance);
        let high = utc_iso(start + tolerance);
        self.query_recordings(
            "SELECT * FROM tv_recordings WHERE LOWER(title) = LOWER(?) AND start_time BETWEEN ? AND ? AND status NOT IN ('failed', 'cancelled') LIMIT 1",
            &[title, &low, &high],
        )
        .into_iter()
        .next()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db() -> (AppDatabase, std::path::PathBuf) {
        let path = std::env::temp_dir().join(format!("xf-test-{}.db", uuid::Uuid::new_v4()));
        let db = AppDatabase::open(path.to_str().unwrap()).unwrap();
        (db, path)
    }

    #[test]
    fn sessions_et_cascade() {
        let (db, _path) = temp_db();
        let hash = password::hash("password1").unwrap();
        let user = db.create_user("bob", &hash, false).unwrap();
        let session = db.create_session(&user.id).unwrap();
        assert!(db.find_session_by_token(&session.token).is_some());
        assert!(db.verify_credentials("bob", "password1").is_some());
        assert!(db.verify_credentials("bob", "nope").is_none());
        // ON DELETE CASCADE actif : la session disparaît avec l'utilisateur.
        db.delete_user(&user.id).unwrap();
        assert!(db.find_session_by_token(&session.token).is_none());
    }

    #[test]
    fn migration_paresseuse_du_sha256() {
        let (db, _path) = temp_db();
        let legacy = "8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918";
        let user = db.create_user("old", legacy, false).unwrap();
        assert!(db.verify_credentials("old", "admin").is_some());
        let stored: String = db
            .lock()
            .query_row(
                "SELECT password_hash FROM users WHERE id = ?",
                [&user.id],
                |r| r.get(0),
            )
            .unwrap();
        assert!(!password::is_legacy(&stored));
        assert!(db.verify_credentials("old", "admin").is_some());
    }

    #[test]
    fn deduplication_des_episodes_a_deux_minutes_pres() {
        let (db, _path) = temp_db();
        let user = db.create_user("u", "x", false).unwrap();
        let start = DartDateTime::parse("2026-08-11T18:00:00Z")
            .unwrap()
            .to_utc();
        let end = start + Duration::hours(1);
        db.create_recording(&user.id, "1", "/api/live/1.ts", "Journal", start, end)
            .unwrap();
        assert!(
            db.find_recording_for_episode(
                "JOURNAL",
                start + Duration::seconds(90),
                Duration::minutes(2)
            )
            .is_some()
        );
        assert!(
            db.find_recording_for_episode(
                "Journal",
                start + Duration::minutes(5),
                Duration::minutes(2)
            )
            .is_none()
        );
        let rec = db.get_all_recordings().pop().unwrap();
        assert_eq!(rec.start_time.to_iso(), "2026-08-11T18:00:00.000Z");
        assert_eq!(rec.status, "scheduled");
    }

    #[test]
    fn statut_et_motif_d_erreur() {
        let (db, _path) = temp_db();
        let user = db.create_user("u", "x", false).unwrap();
        let now = Utc::now();
        let rec = db
            .create_recording(&user.id, "1", "/x", "T", now, now + Duration::hours(1))
            .unwrap();
        db.update_recording_status(&rec.id, "failed", None, Some("boom"), false);
        db.update_recording_status(&rec.id, "failed", Some("/f.mkv"), None, false);
        let r = db.get_recording_by_id(&rec.id).unwrap();
        assert_eq!(r.error_reason.as_deref(), Some("boom"));
        assert_eq!(r.file_path.as_deref(), Some("/f.mkv"));
        db.update_recording_status(&rec.id, "recording", None, None, true);
        let r = db.get_recording_by_id(&rec.id).unwrap();
        assert_eq!(r.error_reason, None);
        assert_eq!(r.file_path.as_deref(), Some("/f.mkv"));
    }

    #[test]
    fn reglage_gpu() {
        let (db, _path) = temp_db();
        let user = db.create_user("u", "x", false).unwrap();
        assert!(!db.is_nvidia_gpu_enabled());
        db.update_user_settings(&user.id, r#"{"enable_nvidia_gpu": true}"#)
            .unwrap();
        assert!(db.is_nvidia_gpu_enabled());
    }

    #[test]
    fn mot_de_passe_genere() {
        let p = generate_password(16);
        assert_eq!(p.len(), 16);
        assert!(!p.contains(['0', 'O', '1', 'l', 'I']));
    }
}
