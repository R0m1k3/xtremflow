//! Adressage des sessions de lecture d'un enregistrement.
//!
//! Un enregistrement est transcodé à la volée, séquentiellement. Reprendre à
//! 45 min sans le dire à FFmpeg imposerait d'attendre que l'encodeur y
//! arrive : le lecteur demande donc une playlist qui *commence* à cette
//! position (`?start=2700`), servie par une session FFmpeg dédiée.

use regex::Regex;
use std::sync::LazyLock;

/// Position de départ demandée (`?start=<secondes>`), bornée au positif.
pub fn parse_recording_start(raw: Option<&str>) -> u64 {
    let Some(value) = raw.and_then(|r| r.trim().parse::<f64>().ok()) else {
        return 0;
    };
    if !value.is_finite() || value <= 0.0 {
        return 0;
    }
    value.floor() as u64
}

/// Segment de chemin qui rattache un `.ts` à SA session : la query string ne
/// survit pas aux URL relatives de la playlist, et les playlists démarrées à
/// 0 s et à 45 min demanderaient sinon toutes deux `segment_000.ts`.
pub fn recording_offset_key(start: u64) -> String {
    format!("t{start}")
}

/// Inverse de [recording_offset_key] ; `None` si la clé est mal formée.
pub fn parse_recording_offset_key(key: &str) -> Option<u64> {
    let digits = key.strip_prefix('t')?;
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit() || b == b'+') {
        return None;
    }
    digits.parse::<u64>().ok()
}

static SEGMENT_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^(segment_\d+\.ts)\s*$").unwrap());

/// Préfixe les lignes de segment de [playlist] par [offset_key] ; balises
/// `#EXT-X-…` et lignes vides passent telles quelles.
pub fn rewrite_recording_playlist(playlist: &str, offset_key: &str) -> String {
    SEGMENT_LINE
        .replace_all(playlist, |caps: &regex::Captures| {
            format!("{offset_key}/{}", &caps[1])
        })
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lit_la_position() {
        assert_eq!(parse_recording_start(Some("2700")), 2700);
        assert_eq!(parse_recording_start(Some("2700.9")), 2700);
        for bad in [
            None,
            Some(""),
            Some("abc"),
            Some("-30"),
            Some("NaN"),
            Some("Infinity"),
        ] {
            assert_eq!(parse_recording_start(bad), 0);
        }
    }

    #[test]
    fn cle_d_offset_aller_retour() {
        for start in [0, 1, 2700, 86400] {
            assert_eq!(
                parse_recording_offset_key(&recording_offset_key(start)),
                Some(start)
            );
        }
        for bad in ["t", "segment_000.ts", "..", "t-30", "tabc"] {
            assert_eq!(parse_recording_offset_key(bad), None, "{bad}");
        }
    }

    const PLAYLIST: &str = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:4\n#EXT-X-PLAYLIST-TYPE:EVENT\n#EXTINF:4.000000,\nsegment_000.ts\n#EXTINF:4.000000,\nsegment_001.ts\n";

    #[test]
    fn rattache_chaque_segment_a_sa_session() {
        let out = rewrite_recording_playlist(PLAYLIST, "t2700");
        assert!(out.contains("t2700/segment_000.ts"));
        assert!(out.contains("t2700/segment_001.ts"));
        assert!(!out.contains("\nsegment_"));
    }

    #[test]
    fn laisse_les_balises() {
        let out = rewrite_recording_playlist(PLAYLIST, "t0");
        assert!(out.starts_with("#EXTM3U\n#EXT-X-VERSION:3\n"));
        assert!(out.contains("#EXT-X-PLAYLIST-TYPE:EVENT"));
        assert_eq!(out.matches("#EXTINF:4.000000,").count(), 2);
    }

    #[test]
    fn idempotent() {
        let once = rewrite_recording_playlist(PLAYLIST, "t60");
        assert_eq!(rewrite_recording_playlist(&once, "t60"), once);
    }
}
