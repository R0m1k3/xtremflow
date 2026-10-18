//! Repérage des chaînes beIN Sports françaises dans la liste du panneau.
//!
//! POURQUOI : un panneau Xtream propose souvent des dizaines de « beIN » :
//! France, MENA, Turquie, Espagne, USA, Australie…, chacune en plusieurs
//! qualités (FHD, HD, backup). L'enregistrement automatique ne doit viser que
//! les chaînes françaises, une seule fois par chaîne logique (beIN SPORTS 1,
//! 2, 3, MAX 4…), dans la meilleure qualité disponible.

use crate::models::PlaylistConfig;
use crate::services::nba_teams::normalize;
use regex::Regex;
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::LazyLock;

/// Une chaîne beIN trouvée dans la liste du panneau.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct BeinChannel {
    pub stream_id: String,
    /// Nom brut du panneau (« FR - BEIN SPORTS 1 FHD »).
    pub name: String,
    pub category: String,
    /// Chaîne logique, identique pour toutes les qualités (« bein-sports-1 »).
    pub logical: String,
    /// Libellé d'affichage (« beIN SPORTS 1 »).
    pub label: String,
    /// Chaîne française ?
    pub is_fr: bool,
    /// Plus grand = meilleur flux pour enregistrer.
    pub quality_rank: i32,
}

/// « bein sports max 4 », « beinsports 2 », « bein sport 1 », « bein sports xtra ».
static BEIN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\bbein ?sports?\b(?: (max|xtra|premium|news))?(?: ?(\d{1,2}))?\b").unwrap()
});

/// Préfixe pays du nom brut : `FR - `, `FR| `, `|FR| `, `[FR] `, `AR: `…
static COUNTRY_PREFIX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*[\|\[\(]?\s*([A-Za-z]{2,4})\s*[\|\]\):\-]").unwrap());

/// Marqueurs d'une version étrangère (dans le nom ou la catégorie).
const FOREIGN: &[&str] = &[
    "ar",
    "arab",
    "arabic",
    "arabia",
    "mena",
    "me",
    "qa",
    "qatar",
    "tr",
    "turk",
    "turkey",
    "turkiye",
    "es",
    "esp",
    "espana",
    "spain",
    "us",
    "usa",
    "en",
    "eng",
    "english",
    "uk",
    "au",
    "aus",
    "australia",
    "nz",
    "asia",
    "ca",
    "canada",
    "my",
    "malaysia",
    "id",
    "indonesia",
    "th",
    "thailand",
    "hk",
    "ph",
    "sg",
    "afr",
    "africa",
    "de",
    "it",
    "pt",
    "ru",
];

/// Marqueurs d'une version française.
const FRENCH: &[&str] = &[
    "fr",
    "fra",
    "france",
    "french",
    "francais",
    "francaise",
    "vf",
];

fn words(text: &str) -> Vec<String> {
    normalize(text).split(' ').map(str::to_string).collect()
}

fn quality_rank(norm_name: &str) -> i32 {
    let w: Vec<&str> = norm_name.split(' ').collect();
    let has = |k: &str| w.contains(&k);
    let mut rank = if has("fhd") || has("1080") || has("1080p") {
        4
    } else if has("hd") || has("720") || has("720p") {
        3
    } else if has("4k") || has("uhd") {
        // Souvent instable chez les revendeurs : derrière le FHD.
        2
    } else if has("sd") || has("lq") {
        1
    } else {
        2
    };
    if has("backup") || has("bk") || has("raw") {
        rank -= 2;
    }
    rank
}

/// Analyse un nom de chaîne. `None` si ce n'est pas une beIN Sports.
pub fn classify(stream_id: &str, name: &str, category: &str) -> Option<BeinChannel> {
    let norm = normalize(name);
    let caps = BEIN.captures(&norm)?;
    let variant = caps.get(1).map(|m| m.as_str());
    let number = caps.get(2).map(|m| m.as_str());
    let (logical, label) = match (variant, number) {
        (Some(v), Some(n)) => (
            format!("bein-sports-{v}-{n}"),
            format!("beIN SPORTS {} {n}", v.to_uppercase()),
        ),
        (Some(v), None) => (
            format!("bein-sports-{v}"),
            format!("beIN SPORTS {}", v.to_uppercase()),
        ),
        (None, Some(n)) => (format!("bein-sports-{n}"), format!("beIN SPORTS {n}")),
        (None, None) => ("bein-sports".to_string(), "beIN SPORTS".to_string()),
    };

    let prefix = COUNTRY_PREFIX
        .captures(name)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_ascii_lowercase());
    // Le préfixe du nom fait foi ; sinon les mots du nom (hors « bein sports
    // N ») puis ceux de la catégorie.
    let rest_of_name = BEIN.replace(&norm, " ");
    let name_words = words(&rest_of_name);
    let cat_words = words(category);
    let is_marked = |list: &[&str], ws: &[String]| ws.iter().any(|w| list.contains(&w.as_str()));
    let is_fr = match prefix.as_deref() {
        Some(p) if FRENCH.contains(&p) => true,
        Some(p) if FOREIGN.contains(&p) => false,
        _ => {
            if is_marked(FOREIGN, &name_words) {
                false
            } else if is_marked(FRENCH, &name_words) {
                true
            } else {
                is_marked(FRENCH, &cat_words) && !is_marked(FOREIGN, &cat_words)
            }
        }
    };

    Some(BeinChannel {
        stream_id: stream_id.to_string(),
        name: name.to_string(),
        category: category.to_string(),
        logical,
        label,
        is_fr,
        quality_rank: quality_rank(&norm),
    })
}

/// Toutes les beIN de la liste, triées : françaises d'abord, puis par
/// chaîne logique, meilleure qualité en tête.
pub fn detect(items: &[(String, String, String)]) -> Vec<BeinChannel> {
    let mut found: Vec<BeinChannel> = items
        .iter()
        .filter_map(|(id, name, cat)| classify(id, name, cat))
        .collect();
    found.sort_by(|a, b| {
        b.is_fr
            .cmp(&a.is_fr)
            .then_with(|| natural_key(&a.logical).cmp(&natural_key(&b.logical)))
            .then_with(|| b.quality_rank.cmp(&a.quality_rank))
            .then_with(|| a.stream_id.cmp(&b.stream_id))
    });
    found
}

/// « bein-sports-10 » après « bein-sports-2 ».
fn natural_key(logical: &str) -> (String, u32) {
    let (head, tail) = logical.rsplit_once('-').unwrap_or((logical, ""));
    match tail.parse::<u32>() {
        Ok(n) => (head.to_string(), n),
        Err(_) => (logical.to_string(), 0),
    }
}

/// Le meilleur flux français par chaîne logique : sélection par défaut
/// d'une nouvelle règle.
pub fn preferred_fr(detected: &[BeinChannel]) -> Vec<BeinChannel> {
    let mut seen = std::collections::HashSet::new();
    detected
        .iter()
        .filter(|c| c.is_fr && seen.insert(c.logical.clone()))
        .cloned()
        .collect()
}

/// `(stream_id, nom, catégorie)` de toutes les chaînes live du panneau.
pub async fn fetch_live_table(
    client: &reqwest::Client,
    playlist: &PlaylistConfig,
) -> Vec<(String, String, String)> {
    let api = |action: &str| {
        format!(
            "{}/player_api.php?username={}&password={}&action={action}",
            playlist.dns, playlist.username, playlist.password
        )
    };
    let get = |url: String| async move {
        let r = client
            .get(&url)
            .timeout(std::time::Duration::from_secs(90))
            .send()
            .await
            .ok()?;
        let body = r.bytes().await.ok()?;
        tokio::task::spawn_blocking(move || serde_json::from_slice::<Value>(&body).ok())
            .await
            .ok()
            .flatten()
    };
    let as_text = |v: Option<&Value>| match v {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Null) | None => String::new(),
        Some(other) => other.to_string(),
    };
    let categories: HashMap<String, String> = get(api("get_live_categories"))
        .await
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default()
        .iter()
        .map(|c| {
            (
                as_text(c.get("category_id")),
                as_text(c.get("category_name")),
            )
        })
        .collect();
    get(api("get_live_streams"))
        .await
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default()
        .iter()
        .filter_map(|s| {
            let id = as_text(s.get("stream_id"));
            let name = as_text(s.get("name"));
            if id.is_empty() || name.is_empty() {
                return None;
            }
            let cat = categories
                .get(&as_text(s.get("category_id")))
                .cloned()
                .unwrap_or_default();
            Some((id, name, cat))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(name: &str, cat: &str) -> Option<BeinChannel> {
        classify("1", name, cat)
    }

    #[test]
    fn chaines_francaises() {
        let ch = c("FR - BEIN SPORTS 1 FHD", "FRANCE SPORTS").unwrap();
        assert!(ch.is_fr);
        assert_eq!(ch.logical, "bein-sports-1");
        assert_eq!(ch.label, "beIN SPORTS 1");
        assert!(c("FR| beIN SPORTS MAX 4", "").unwrap().is_fr);
        assert_eq!(
            c("FR| beIN SPORTS MAX 4", "").unwrap().logical,
            "bein-sports-max-4"
        );
        assert!(c("beIN SPORTS 2 FR HD", "Sport").unwrap().is_fr);
        assert!(c("BEIN SPORT 3", "FR | SPORTS").unwrap().is_fr);
        assert!(c("|FR| BEINSPORTS 1 ᴴᴰ", "").unwrap().is_fr);
    }

    #[test]
    fn chaines_etrangeres_exclues() {
        assert!(!c("AR| beIN SPORTS 1", "ARABIC SPORTS").unwrap().is_fr);
        assert!(!c("TR: BEIN SPORTS 1 HD", "TURKIYE").unwrap().is_fr);
        assert!(!c("beIN SPORTS MENA 1", "FR SPORTS").unwrap().is_fr);
        assert!(!c("beIN SPORTS 1 (AUS)", "").unwrap().is_fr);
        assert!(!c("US: beIN Sports", "USA SPORTS").unwrap().is_fr);
        // Aucune indication de pays : on ne devine pas.
        assert!(!c("beIN SPORTS 1", "SPORTS").unwrap().is_fr);
    }

    #[test]
    fn pas_une_bein() {
        assert!(c("FR - CANAL+ SPORT", "FRANCE").is_none());
        assert!(c("FR - RMC SPORT 1", "FRANCE").is_none());
    }

    #[test]
    fn meilleure_qualite_par_chaine_logique() {
        let items: Vec<(String, String, String)> = [
            ("10", "FR - BEIN SPORTS 1 HD"),
            ("11", "FR - BEIN SPORTS 1 FHD"),
            ("12", "FR - BEIN SPORTS 1 FHD BACKUP"),
            ("20", "FR - BEIN SPORTS 2 HD"),
            ("30", "AR - BEIN SPORTS 1"),
            ("40", "FR - BEIN SPORTS MAX 10"),
            ("41", "FR - BEIN SPORTS MAX 4"),
        ]
        .iter()
        .map(|(id, n)| (id.to_string(), n.to_string(), String::new()))
        .collect();
        let detected = detect(&items);
        assert_eq!(detected.len(), 7);
        assert!(!detected.last().unwrap().is_fr);
        let preferred: Vec<String> = preferred_fr(&detected)
            .into_iter()
            .map(|c| c.stream_id)
            .collect();
        assert_eq!(preferred, ["11", "20", "41", "40"]);
    }
}
