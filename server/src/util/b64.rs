//! Décodage base64 des titres/descriptions EPG du panneau Xtream.

use base64::Engine;
use base64::engine::general_purpose::{STANDARD, URL_SAFE};

/// Texte décodé si [raw] est du base64 valide contenant de l'UTF-8 valide,
/// sinon `None` (l'appelant garde alors la valeur brute, comme
/// `utf8.decode(base64Decode(x))` qui levait une exception).
pub fn decode_text(raw: &str) -> Option<String> {
    let bytes = STANDARD
        .decode(raw.as_bytes())
        .or_else(|_| URL_SAFE.decode(raw.as_bytes()))
        .ok()?;
    String::from_utf8(bytes).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_le_base64_du_panneau() {
        assert_eq!(
            decode_text("Sm91cm5hbCBkZSAyMGg=").as_deref(),
            Some("Journal de 20h")
        );
        assert_eq!(
            decode_text("TCdpbmZvIGR1IHNvaXI=").as_deref(),
            Some("L'info du soir")
        );
    }

    #[test]
    fn garde_un_titre_en_clair() {
        assert_eq!(decode_text("Journal"), None);
        assert_eq!(decode_text("Le 13h"), None);
    }
}
