//! Journal des incidents de lecture remontés par le lecteur web.
//!
//! POURQUOI : les freezes se produisent chez l'utilisateur, dans son
//! navigateur ; le serveur n'en voit rien. Le lecteur envoie ici chaque
//! coupure, erreur, recréation et saut, et le serveur les écrit dans
//! `docker logs` (`[Player] …`).
//!
//! Entrée non fiable : seuls des champs connus, courts et typés passent.

use crate::http::{self, Req, Resp};
use regex::Regex;
use serde_json::Value;
use std::sync::LazyLock;

const EVENTS: [&str; 11] = [
    "start",
    "first_frame",
    "stall",
    "seek",
    "mpegts_error",
    "recreate",
    "fallback_hls",
    "hls_error",
    "profile",
    "error_shown",
    "heartbeat",
];

const NUMERIC_FIELDS: [&str; 11] = [
    "t", "ms", "buffer", "pos", "from", "to", "stalls", "stallMs", "seeks", "errors", "rate",
];

const TEXT_FIELDS: [&str; 5] = ["session", "ch", "mode", "profile", "detail"];

static URL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"https?://\S+").unwrap());
static UNSAFE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[^A-Za-z0-9_.\-:/<>]").unwrap());

/// Ligne de journal pour l'événement [raw], ou `None` s'il est invalide.
pub fn format_player_event(raw: &Value) -> Option<String> {
    let map = raw.as_object()?;
    let event = map.get("event")?.as_str()?;
    if !EVENTS.contains(&event) {
        return None;
    }
    let mut parts = vec![event.to_string()];
    for key in TEXT_FIELDS {
        if let Some(value) = map.get(key).and_then(Value::as_str) {
            if value.is_empty() {
                continue;
            }
            // Ni espace, ni retour ligne, ni URL : jamais d'injection de faux
            // journaux, jamais d'identifiants recopiés depuis une URL.
            let safe = URL.replace_all(value, "<url>");
            let safe = UNSAFE.replace_all(&safe, "_");
            let safe: String = safe.chars().take(60).collect();
            parts.push(format!("{key}={safe}"));
        }
    }
    for key in NUMERIC_FIELDS {
        let Some(Value::Number(n)) = map.get(key) else {
            continue;
        };
        if let Some(i) = n.as_i64() {
            parts.push(format!("{key}={i}"));
        } else if let Some(f) = n.as_f64().filter(|f| f.is_finite()) {
            parts.push(format!("{key}={f:.1}"));
        }
    }
    Some(format!("[Player] {}", parts.join(" ")))
}

pub fn handle(req: &Req) -> Resp {
    let body = req.body_str();
    if body.encode_utf16().count() > 4096 {
        return http::empty(413);
    }
    let Ok(decoded) = serde_json::from_str::<Value>(&body) else {
        return http::text(400, "Bad Request");
    };
    let events: Vec<&Value> = match &decoded {
        Value::Array(list) => list.iter().take(20).collect(),
        other => vec![other],
    };
    for event in events {
        if let Some(line) = format_player_event(event) {
            println!("{line}");
        }
    }
    http::empty(204)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn ecrit_une_coupure_avec_sa_duree_et_le_buffer() {
        assert_eq!(
            format_player_event(&json!({
                "event": "stall", "session": "ab12", "ch": "554034", "ms": 5230, "buffer": 0.04
            }))
            .unwrap(),
            "[Player] stall session=ab12 ch=554034 ms=5230 buffer=0.0"
        );
    }

    #[test]
    fn refuse_un_evenement_inconnu() {
        assert!(format_player_event(&json!({"event": "rm -rf"})).is_none());
        assert!(format_player_event(&json!("stall")).is_none());
        assert!(format_player_event(&Value::Null).is_none());
    }

    #[test]
    fn pas_d_injection_ni_d_url() {
        let line = format_player_event(&json!({
            "event": "mpegts_error",
            "detail": "NetworkError http://panel/live/user/pass/1.ts\n[Player] faux"
        }))
        .unwrap();
        assert!(!line.contains('\n'));
        assert!(!line.contains("user/pass"));
        assert!(line.contains("<url>"));
    }

    #[test]
    fn ignore_les_champs_inattendus() {
        let line =
            format_player_event(&json!({"event": "seek", "from": 10, "cookie": "secret"})).unwrap();
        assert!(line.contains("from=10"));
        assert!(!line.contains("to="));
        assert!(!line.contains("secret"));
    }
}
