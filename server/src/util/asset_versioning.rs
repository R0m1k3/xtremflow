//! Versionnage des assets non hachés de la build web.
//!
//! POURQUOI : `main.dart.js`, `flutter_bootstrap.js` et `xf-player-core.js`
//! gardent le même nom d'une build à l'autre. Un reverse proxy qui met les
//! `.js` en cache (option « Cache Assets » de Nginx Proxy Manager, constatée
//! en prod : cache jusqu'à 12 h, même sur un rechargement forcé) servait donc
//! l'ANCIEN lecteur et l'ANCIENNE app avec le NOUVEAU serveur après chaque
//! déploiement. En ajoutant `?v=<empreinte du contenu>` aux références,
//! chaque version a sa propre URL : aucun cache intermédiaire ne peut la
//! confondre avec la précédente.

use md5::{Digest, Md5};
use std::collections::HashMap;
use std::path::Path;

/// Empreinte courte et stable de [bytes].
pub fn content_version(bytes: &[u8]) -> String {
    let digest = Md5::digest(bytes);
    let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
    hex[..12].to_string()
}

/// Ajoute `?v=<version>` à chaque référence entre guillemets à un asset de
/// [versions] (`"main.dart.js"` → `"main.dart.js?v=…"`).
///
/// Seules les références exactes sont réécrites : `vendor/x.js` ou une
/// référence déjà versionnée restent intactes.
pub fn version_asset_refs(content: &str, versions: &[(&str, String)]) -> String {
    let mut out = content.to_string();
    for (asset, version) in versions {
        for quote in ['"', '\''] {
            let from = format!("{quote}{asset}{quote}");
            let to = format!("{quote}{asset}?v={version}{quote}");
            out = out.replace(&from, &to);
        }
    }
    out
}

/// Contenus réécrits, indexés par chemin relatif (`index.html`…), prêts à
/// être servis à la place des fichiers d'origine.
///
/// Calculé une fois au démarrage : la build web est figée dans l'image.
pub fn build_versioned_entry_points(web_path: &str) -> HashMap<String, String> {
    let base = Path::new(web_path);
    let read = |name: &str| std::fs::read_to_string(base.join(name)).ok();
    let version_of = |name: &str| {
        std::fs::read(base.join(name))
            .ok()
            .map(|b| content_version(&b))
    };

    let mut rewritten = HashMap::new();

    // Le bootstrap référence main.dart.js : sa version dépend donc de celle
    // de main.dart.js, d'où une version calculée APRÈS réécriture.
    if let (Some(bootstrap), Some(main_version)) =
        (read("flutter_bootstrap.js"), version_of("main.dart.js"))
    {
        let versioned = version_asset_refs(&bootstrap, &[("main.dart.js", main_version)]);
        let bootstrap_version = content_version(versioned.as_bytes());
        rewritten.insert("flutter_bootstrap.js".to_string(), versioned);
        if let Some(index) = read("index.html") {
            rewritten.insert(
                "index.html".to_string(),
                version_asset_refs(&index, &[("flutter_bootstrap.js", bootstrap_version)]),
            );
        }
    }

    let player_assets: Vec<(&str, String)> = ["xf-player-core.js", "xf-player.css"]
        .into_iter()
        .filter_map(|name| version_of(name).map(|v| (name, v)))
        .collect();
    for page in ["player.html", "player_lite.html", "player_mobile.html"] {
        if let Some(html) = read(page) {
            rewritten.insert(page.to_string(), version_asset_refs(&html, &player_assets));
        }
    }
    rewritten
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versionne_la_balise_script_du_lecteur() {
        assert_eq!(
            version_asset_refs(
                r#"<script src="xf-player-core.js"></script>"#,
                &[("xf-player-core.js", "abc123".into())]
            ),
            r#"<script src="xf-player-core.js?v=abc123"></script>"#
        );
    }

    #[test]
    fn versionne_main_js_path_dans_la_config_flutter() {
        assert_eq!(
            version_asset_refs(
                r#"{"compileTarget":"dart2js","mainJsPath":"main.dart.js"}"#,
                &[("main.dart.js", "f00".into())]
            ),
            r#"{"compileTarget":"dart2js","mainJsPath":"main.dart.js?v=f00"}"#
        );
    }

    #[test]
    fn ne_touche_ni_un_nom_contenant_l_asset_ni_une_ref_versionnee() {
        let html = r#"<script src="vendor/xf-player-core.js"></script><script src="xf-player-core.js?v=old"></script>"#;
        assert_eq!(
            version_asset_refs(html, &[("xf-player-core.js", "new".into())]),
            html
        );
    }

    #[test]
    fn guillemets_simples_acceptes() {
        assert_eq!(
            version_asset_refs(
                "<link href='xf-player.css'>",
                &[("xf-player.css", "1".into())]
            ),
            "<link href='xf-player.css?v=1'>"
        );
    }

    #[test]
    fn empreinte_stable() {
        assert_eq!(content_version(&[1, 2, 3]), content_version(&[1, 2, 3]));
        assert_ne!(content_version(&[1, 2, 3]), content_version(&[1, 2, 4]));
        assert_eq!(content_version(&[1, 2, 3]).len(), 12);
    }
}
