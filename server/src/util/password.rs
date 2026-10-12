//! Hachage des mots de passe : bcrypt, avec lecture des anciens hachages
//! SHA-256 non salés (migrés paresseusement à la connexion suivante).

use regex::Regex;
use sha2::{Digest, Sha256};
use std::sync::LazyLock;

/// Coût 10 : identique à l'ancien serveur, les hachages existants restent
/// vérifiables et le temps de connexion ne change pas.
const BCRYPT_COST: u32 = 10;

/// Les hachages historiques sont des empreintes SHA-256 hexadécimales.
static LEGACY: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[0-9a-f]{64}$").unwrap());

pub fn hash(password: &str) -> Result<String, String> {
    bcrypt::hash(password, BCRYPT_COST).map_err(|e| e.to_string())
}

/// Vérifie [password] contre le hachage stocké (bcrypt ou SHA-256 historique).
pub fn verify(password: &str, stored: &str) -> bool {
    if is_legacy(stored) {
        let digest = Sha256::digest(password.as_bytes());
        let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
        return hex == stored;
    }
    // Hachage malformé (ni SHA-256 ni bcrypt valide) : jamais valide.
    bcrypt::verify(password, stored).unwrap_or(false)
}

pub fn is_legacy(stored: &str) -> bool {
    LEGACY.is_match(stored)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bcrypt_aller_retour() {
        let h = hash("s3cret!").unwrap();
        assert!(verify("s3cret!", &h));
        assert!(!verify("wrong", &h));
    }

    #[test]
    fn les_hachages_sha256_historiques_restent_valides() {
        // sha256("admin")
        let legacy = "8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918";
        assert!(verify("admin", legacy));
        assert!(!verify("other", legacy));
    }

    #[test]
    fn is_legacy_ne_reconnait_que_le_sha256_hex() {
        assert!(is_legacy(
            "8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918"
        ));
        assert!(!is_legacy("$2a$10$abcdefghijklmnopqrstuv"));
        assert!(!is_legacy(&hash("x").unwrap()));
    }

    #[test]
    fn lit_les_hachages_2a_de_l_ancien_serveur() {
        // Hachage produit par le paquet Dart `bcrypt` (préfixe $2a$).
        let dart = bcrypt::hash_with_salt("admin", 10, [7u8; 16])
            .unwrap()
            .format_for_version(bcrypt::Version::TwoA);
        assert!(dart.starts_with("$2a$10$"));
        assert!(verify("admin", &dart));
    }

    #[test]
    fn un_hachage_malforme_n_est_jamais_valide() {
        assert!(!verify("x", "not-a-hash"));
        assert!(!verify("", ""));
    }
}
