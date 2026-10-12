//! Validation de chemins contre la traversée de répertoires.
//!
//! Travaille sur des chemins POSIX (le serveur tourne dans un conteneur
//! Linux), de façon purement lexicale comme `package:path`.

/// Normalise un chemin POSIX absolu : résout `.` et `..`, retire les `/`
/// redondants.
fn normalize(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for segment in path.split('/') {
        match segment {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    format!("/{}", parts.join("/"))
}

fn absolute(path: &str) -> String {
    if path.starts_with('/') {
        return path.to_string();
    }
    let cwd = std::env::current_dir()
        .map(|p| p.to_string_lossy().replace('\\', "/"))
        .unwrap_or_else(|_| "/".to_string());
    format!("{}/{}", cwd.trim_end_matches('/'), path)
}

/// Résout [candidate] et ne le renvoie que s'il reste dans [base_dir].
/// `None` quand le chemin s'en échappe (segments `..`, chemin absolu ailleurs).
pub fn resolve_within(base_dir: &str, candidate: &str) -> Option<String> {
    let base = normalize(&absolute(base_dir));
    let resolved = if candidate.starts_with('/') {
        normalize(candidate)
    } else {
        normalize(&format!("{base}/{candidate}"))
    };
    let within =
        resolved == base || resolved.starts_with(&format!("{}/", base.trim_end_matches('/')));
    within.then_some(resolved)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &str = "/app/recordings";

    #[test]
    fn accepte_les_fichiers_du_dossier() {
        assert!(resolve_within(BASE, "/app/recordings/show.log").is_some());
        assert!(resolve_within(BASE, "show.log").is_some());
        assert!(resolve_within(BASE, "/app/recordings/sub/dir/file.log").is_some());
    }

    #[test]
    fn rejette_la_traversee() {
        assert!(resolve_within(BASE, "/app/recordings/../data/xtremflow.db").is_none());
        assert!(resolve_within(BASE, "../../etc/passwd").is_none());
    }

    #[test]
    fn rejette_les_chemins_absolus_ailleurs() {
        assert!(resolve_within(BASE, "/etc/passwd").is_none());
        assert!(resolve_within(BASE, "/app/data/xtremflow.db").is_none());
    }

    #[test]
    fn rejette_un_voisin_au_prefixe_commun() {
        assert!(resolve_within(BASE, "/app/recordings-evil/file.log").is_none());
    }
}
