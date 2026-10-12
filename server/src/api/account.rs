//! Comptes : authentification, utilisateurs (admin), playlists, réglages.

use crate::http::{self, Req, Resp, extract_token, json, json_as_text, segments, text};
use crate::state::SharedState;
use crate::util::password;
use serde_json::{Value, json};

fn error_json(status: u16, error: impl Into<String>) -> Resp {
    json(status, &json!({"success": false, "error": error.into()}))
}

fn str_field(payload: &Value, key: &str) -> Option<String> {
    payload.get(key).and_then(Value::as_str).map(str::to_string)
}

/// Corps JSON objet, ou réponse 500 (comportement de l'ancien serveur sur
/// un corps illisible).
fn parse_object(req: &Req) -> Result<Value, Resp> {
    match serde_json::from_slice::<Value>(&req.body) {
        Ok(v) if v.is_object() => Ok(v),
        Ok(_) => Err(error_json(
            500,
            "type is not a subtype of type 'Map<String, dynamic>'",
        )),
        Err(e) => Err(error_json(500, format!("FormatException: {e}"))),
    }
}

/// Longueur à la manière de Dart (unités UTF-16).
fn dart_len(s: &str) -> usize {
    s.encode_utf16().count()
}

// ==================== /api/auth ====================

pub async fn auth(state: &SharedState, req: &Req, rest: &str) -> Resp {
    match (req.method.as_str(), segments(rest).as_slice()) {
        ("POST", ["login"]) => login(state, req).await,
        ("POST", ["logout"]) => logout(state, req),
        ("GET" | "HEAD", ["me"]) => me(state, req),
        _ => http::not_found(),
    }
}

async fn login(state: &SharedState, req: &Req) -> Resp {
    println!("[Auth] Login attempt received");
    let payload = match parse_object(req) {
        Ok(p) => p,
        Err(resp) => {
            println!("[Auth] ERROR during login: invalid body");
            return resp;
        }
    };
    let (Some(username), Some(pass)) = (
        str_field(&payload, "username"),
        str_field(&payload, "password"),
    ) else {
        println!("[Auth] Missing username or password");
        return error_json(400, "Username and password are required");
    };

    println!("[Auth] Verifying credentials for user: {username}");
    // bcrypt est coûteux : hors du runtime asynchrone.
    let db = state.db.clone();
    let user_name = username.clone();
    let user = tokio::task::spawn_blocking(move || db.verify_credentials(&user_name, &pass))
        .await
        .ok()
        .flatten();
    let Some(user) = user else {
        println!("[Auth] Invalid credentials for user: {username}");
        return error_json(401, "Invalid credentials");
    };

    println!(
        "[Auth] User verified, creating session for userId: {}",
        user.id
    );
    let session = match state.db.create_session(&user.id) {
        Ok(s) => s,
        Err(e) => return error_json(500, e.to_string()),
    };

    // Cookie de session HttpOnly : les requêtes média de même origine
    // (hls.js dans l'iframe du lecteur ne peut pas envoyer d'en-tête
    // Authorization) sont ainsi authentifiées.
    let max_age = (session.expires_at.to_utc() - chrono::Utc::now()).num_seconds();
    let mut resp = json(
        200,
        &json!({"success": true, "user": user.to_json(), "token": session.token}),
    );
    http::set_header(
        &mut resp,
        "set-cookie",
        &format!(
            "session={}; HttpOnly; SameSite=Lax; Path=/; Max-Age={max_age}",
            session.token
        ),
    );
    resp
}

fn logout(state: &SharedState, req: &Req) -> Resp {
    let Some(token) = extract_token(req) else {
        return error_json(401, "Unauthorized");
    };
    state.db.delete_session(&token);
    let mut resp = json(200, &json!({"success": true}));
    http::set_header(
        &mut resp,
        "set-cookie",
        "session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0",
    );
    resp
}

fn me(state: &SharedState, req: &Req) -> Resp {
    let Some(token) = extract_token(req) else {
        return error_json(401, "Unauthorized");
    };
    let Some(session) = state.db.find_session_by_token(&token) else {
        return error_json(401, "Invalid or expired session");
    };
    match state.db.find_user_by_id(&session.user_id) {
        Some(user) => json(200, &json!({"user": user.to_json()})),
        None => error_json(404, "User not found"),
    }
}

// ==================== /api/users ====================

fn is_admin(state: &SharedState, req: &Req) -> bool {
    req.user_id
        .as_deref()
        .and_then(|id| state.db.find_user_by_id(id))
        .is_some_and(|u| u.is_admin)
}

fn admin_required() -> Resp {
    json_as_text(403, &json!({"success": false, "error": "Admin required"}))
}

pub async fn users(state: &SharedState, req: &Req, rest: &str) -> Resp {
    match (req.method.as_str(), segments(rest).as_slice()) {
        ("GET" | "HEAD", []) => list_users(state, req),
        ("POST", []) => create_user(state, req).await,
        ("PUT", [id, "password"]) => update_password(state, req, id).await,
        ("PUT", [id]) => update_user(state, req, id),
        ("DELETE", [id]) => delete_user(state, req, id),
        _ => http::not_found(),
    }
}

fn list_users(state: &SharedState, req: &Req) -> Resp {
    if !is_admin(state, req) {
        return admin_required();
    }
    let users: Vec<Value> = state
        .db
        .get_all_users()
        .iter()
        .map(|u| u.to_json())
        .collect();
    json(200, &json!({"success": true, "users": users}))
}

async fn create_user(state: &SharedState, req: &Req) -> Resp {
    if !is_admin(state, req) {
        return admin_required();
    }
    let payload = match parse_object(req) {
        Ok(p) => p,
        Err(resp) => return resp,
    };
    let (Some(username), Some(pass)) = (
        str_field(&payload, "username"),
        str_field(&payload, "password"),
    ) else {
        return error_json(400, "Missing required fields");
    };
    let admin = payload
        .get("isAdmin")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if dart_len(&pass) < 8 {
        return error_json(400, "Le mot de passe doit faire au moins 8 caractères");
    }
    if state.db.find_user_by_username(&username).is_some() {
        return error_json(400, "Username already exists");
    }
    let hash = match tokio::task::spawn_blocking(move || password::hash(&pass)).await {
        Ok(Ok(h)) => h,
        Ok(Err(e)) => return error_json(500, e),
        Err(e) => return error_json(500, e.to_string()),
    };
    match state.db.create_user(&username, &hash, admin) {
        Ok(user) => json(200, &json!({"success": true, "user": user.to_json()})),
        Err(e) => error_json(500, e.to_string()),
    }
}

async fn update_password(state: &SharedState, req: &Req, id: &str) -> Resp {
    if !is_admin(state, req) {
        return admin_required();
    }
    let payload = match parse_object(req) {
        Ok(p) => p,
        Err(resp) => return resp,
    };
    let Some(pass) = str_field(&payload, "password") else {
        return error_json(400, "Missing password");
    };
    if dart_len(&pass) < 8 {
        return error_json(400, "Le mot de passe doit faire au moins 8 caractères");
    }
    let hash = match tokio::task::spawn_blocking(move || password::hash(&pass)).await {
        Ok(Ok(h)) => h,
        Ok(Err(e)) => return error_json(500, e),
        Err(e) => return error_json(500, e.to_string()),
    };
    state.db.update_password_hash(id, &hash);
    json(200, &json!({"success": true}))
}

fn update_user(state: &SharedState, req: &Req, id: &str) -> Resp {
    if !is_admin(state, req) {
        return admin_required();
    }
    let payload = match parse_object(req) {
        Ok(p) => p,
        Err(resp) => return resp,
    };
    if let Some(admin) = payload.get("isAdmin").and_then(Value::as_bool)
        && let Err(e) = state.db.update_user_admin_status(id, admin)
    {
        return error_json(500, e.to_string());
    }
    json(200, &json!({"success": true}))
}

fn delete_user(state: &SharedState, req: &Req, id: &str) -> Resp {
    if !is_admin(state, req) {
        return admin_required();
    }
    // Interdit de se supprimer soi-même.
    if req.user_id.as_deref() == Some(id) {
        return error_json(400, "Cannot delete yourself");
    }
    match state.db.delete_user(id) {
        Ok(()) => json(200, &json!({"success": true})),
        Err(e) => error_json(500, e.to_string()),
    }
}

// ==================== /api/playlists ====================

pub fn playlists(state: &SharedState, req: &Req, rest: &str) -> Resp {
    let Some(user_id) = req.user_id.clone() else {
        return error_json(401, "Unauthorized");
    };
    match (req.method.as_str(), segments(rest).as_slice()) {
        ("GET" | "HEAD", []) => {
            let list: Vec<Value> = state
                .db
                .get_playlists(&user_id)
                .iter()
                .map(|p| p.to_json())
                .collect();
            json(200, &json!({"playlists": list}))
        }
        ("POST", []) => create_playlist(state, req, &user_id),
        ("PUT", [id]) => update_playlist(state, req, &user_id, id),
        ("DELETE", [id]) => delete_playlist(state, &user_id, id),
        _ => http::not_found(),
    }
}

fn create_playlist(state: &SharedState, req: &Req, user_id: &str) -> Resp {
    let payload = match parse_object(req) {
        Ok(p) => p,
        Err(resp) => return resp,
    };
    let field = |k| str_field(&payload, k);
    let (Some(name), Some(server_url), Some(username), Some(pass)) = (
        field("name"),
        field("serverUrl"),
        field("username"),
        field("password"),
    ) else {
        return error_json(400, "Missing required fields");
    };
    let dns = field("dns").unwrap_or_else(|| server_url.clone());
    match state
        .db
        .create_playlist(user_id, &name, &server_url, &username, &pass, Some(&dns))
    {
        Ok(p) => json(200, &json!({"success": true, "playlist": p.to_json()})),
        Err(e) => error_json(500, e.to_string()),
    }
}

fn update_playlist(state: &SharedState, req: &Req, user_id: &str, id: &str) -> Resp {
    let Some(existing) = state.db.get_playlist_by_id(id) else {
        return error_json(404, "Playlist not found");
    };
    if existing.user_id != user_id {
        return error_json(403, "Forbidden");
    }
    let payload = match parse_object(req) {
        Ok(p) => p,
        Err(resp) => return resp,
    };
    let field = |k| str_field(&payload, k);
    let name = field("name").unwrap_or(existing.name.clone());
    let server_url = field("serverUrl").unwrap_or(existing.server_url.clone());
    let username = field("username").unwrap_or(existing.username.clone());
    // Mot de passe vide = « inchangé » : les clients ne reçoivent jamais le
    // vrai mot de passe, les formulaires d'édition le renvoient vide.
    let pass = field("password")
        .filter(|p| !p.is_empty())
        .unwrap_or(existing.password.clone());
    let dns = field("dns").or(existing.dns.clone());
    match state
        .db
        .update_playlist(id, &name, &server_url, &username, &pass, dns.as_deref())
    {
        Ok(Some(p)) => json(200, &json!({"success": true, "playlist": p.to_json()})),
        Ok(None) => error_json(404, "Playlist not found"),
        Err(e) => error_json(500, e.to_string()),
    }
}

fn delete_playlist(state: &SharedState, user_id: &str, id: &str) -> Resp {
    let Some(existing) = state.db.get_playlist_by_id(id) else {
        return error_json(404, "Playlist not found");
    };
    if existing.user_id != user_id {
        return error_json(403, "Forbidden");
    }
    match state.db.delete_playlist(id) {
        Ok(()) => json(200, &json!({"success": true})),
        Err(e) => error_json(500, e.to_string()),
    }
}

// ==================== /api/settings ====================

pub fn settings(state: &SharedState, req: &Req, rest: &str) -> Resp {
    let Some(user_id) = req.user_id.clone() else {
        return json_as_text(403, &json!({"error": "Authentication required"}));
    };
    if !segments(rest).is_empty() {
        return http::not_found();
    }
    match req.method.as_str() {
        "GET" | "HEAD" => {
            let settings = state
                .db
                .get_user_settings(&user_id)
                .unwrap_or_else(|| "{}".to_string());
            http::with_headers(
                http::response(200, settings),
                &[("content-type", "application/json")],
            )
        }
        "POST" => {
            let body = req.body_str();
            if serde_json::from_str::<Value>(&body).is_err() {
                return json_as_text(400, &json!({"error": "Invalid JSON"}));
            }
            if let Err(e) = state.db.update_user_settings(&user_id, &body) {
                return text(
                    500,
                    json!({"error": format!("Failed to save settings: {e}")}).to_string(),
                );
            }
            http::with_headers(
                http::response(200, body),
                &[("content-type", "application/json")],
            )
        }
        _ => http::not_found(),
    }
}
