//! Masque les identifiants IPTV des URL avant qu'elles n'atteignent les logs.
//!
//! Xtream Codes embarque les identifiants à la fois dans la query string
//! (`?username=u&password=p`) et dans le chemin
//! (`/live/<user>/<pass>/<id>.ts`, `/movie/...`, `/series/...`).

use regex::Regex;
use std::sync::LazyLock;

static QUERY_CREDS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)(username|password)=[^&\s]*").unwrap());

static PATH_CREDS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)/(live|movie|series)/[^/\s]+/[^/\s]+/").unwrap());

/// Renvoie [url] avec les identifiants remplacés par `***`.
pub fn redact_url(url: &str) -> String {
    let redacted = QUERY_CREDS.replace_all(url, "$1=***");
    PATH_CREDS
        .replace_all(&redacted, "/$1/***/***/")
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn masque_la_query_string() {
        let out = redact_url(
            "http://srv:8080/player_api.php?username=john&password=hunter2&action=get_live_streams",
        );
        assert!(!out.contains("john"));
        assert!(!out.contains("hunter2"));
        assert!(out.contains("username=***"));
        assert!(out.contains("password=***"));
        assert!(out.contains("action=get_live_streams"));
    }

    #[test]
    fn masque_les_segments_de_chemin() {
        for kind in ["live", "movie", "series"] {
            let out = redact_url(&format!("http://srv:8080/{kind}/john/hunter2/12345.ts"));
            assert!(!out.contains("john"), "{kind}");
            assert!(!out.contains("hunter2"), "{kind}");
            assert!(out.contains(&format!("/{kind}/***/***/12345.ts")), "{kind}");
        }
    }

    #[test]
    fn laisse_les_url_sans_identifiants() {
        let url = "http://srv:8080/images/logo.png";
        assert_eq!(redact_url(url), url);
    }
}
