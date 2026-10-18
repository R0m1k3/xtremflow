//! Les 30 franchises NBA et la reconnaissance de leurs noms dans les titres
//! et descriptions EPG.
//!
//! POURQUOI : l'EPG beIN Sports écrit les affiches de façons très variées
//! (« NBA : Boston / Detroit », « Basket-ball - Celtics - Pistons »,
//! « LA Lakers @ Golden State »…). Un match du calendrier ne peut être
//! rattaché à un programme que si l'on retrouve ses deux équipes dans ce
//! texte libre.

/// Une franchise. `abbr` est l'abréviation ESPN (source du calendrier et des
/// logos), qui diffère parfois du tricode NBA (GS, NY, SA, NO, UTAH, WSH).
#[derive(Debug, PartialEq, Eq)]
pub struct Team {
    pub abbr: &'static str,
    /// Ville telle qu'affichée (« Los Angeles »).
    pub city: &'static str,
    /// Surnom (« Lakers »).
    pub nickname: &'static str,
    /// Couleur principale (hex sans #) pour les vignettes.
    pub color: &'static str,
    /// Variantes de surnom acceptées (en plus de `nickname`).
    nick_aliases: &'static [&'static str],
    /// Formes de ville sans ambiguïté qui suffisent à identifier l'équipe.
    city_aliases: &'static [&'static str],
}

impl Team {
    pub fn full_name(&self) -> String {
        format!("{} {}", self.city, self.nickname)
    }

    /// URL du logo PNG (500 px, fond transparent) sur le CDN ESPN.
    pub fn logo_url(&self) -> String {
        format!(
            "https://a.espncdn.com/i/teamlogos/nba/500/{}.png",
            self.abbr.to_ascii_lowercase()
        )
    }
}

macro_rules! team {
    ($abbr:literal, $city:literal, $nick:literal, $color:literal, [$($n:literal),*], [$($c:literal),*]) => {
        Team {
            abbr: $abbr,
            city: $city,
            nickname: $nick,
            color: $color,
            nick_aliases: &[$($n),*],
            city_aliases: &[$($c),*],
        }
    };
}

/// « Los Angeles » est volontairement absent des alias de ville : il désigne
/// deux équipes. Seules les formes « LA Lakers », « L.A. Clippers »… (qui
/// contiennent le surnom) les distinguent.
pub static TEAMS: [Team; 30] = [
    team!("ATL", "Atlanta", "Hawks", "C8102E", [], ["atlanta"]),
    team!("BOS", "Boston", "Celtics", "007A33", [], ["boston"]),
    team!("BKN", "Brooklyn", "Nets", "000000", [], ["brooklyn"]),
    team!("CHA", "Charlotte", "Hornets", "1D1160", [], ["charlotte"]),
    team!("CHI", "Chicago", "Bulls", "CE1141", [], ["chicago"]),
    team!(
        "CLE",
        "Cleveland",
        "Cavaliers",
        "860038",
        ["cavs"],
        ["cleveland"]
    ),
    team!("DAL", "Dallas", "Mavericks", "00538C", ["mavs"], ["dallas"]),
    team!("DEN", "Denver", "Nuggets", "0E2240", [], ["denver"]),
    team!("DET", "Detroit", "Pistons", "C8102E", [], ["detroit"]),
    team!(
        "GS",
        "Golden State",
        "Warriors",
        "1D428A",
        ["dubs"],
        ["golden state"]
    ),
    team!("HOU", "Houston", "Rockets", "CE1141", [], ["houston"]),
    team!("IND", "Indiana", "Pacers", "002D62", [], ["indiana"]),
    team!("LAC", "Los Angeles", "Clippers", "C8102E", [], []),
    team!("LAL", "Los Angeles", "Lakers", "552583", [], []),
    team!(
        "MEM",
        "Memphis",
        "Grizzlies",
        "5D76A9",
        ["grizz"],
        ["memphis"]
    ),
    team!("MIA", "Miami", "Heat", "98002E", [], ["miami"]),
    team!("MIL", "Milwaukee", "Bucks", "00471B", [], ["milwaukee"]),
    team!(
        "MIN",
        "Minnesota",
        "Timberwolves",
        "0C2340",
        ["wolves", "t wolves"],
        ["minnesota"]
    ),
    team!(
        "NO",
        "New Orleans",
        "Pelicans",
        "0C2340",
        ["pels"],
        ["new orleans", "nouvelle orleans"]
    ),
    team!("NY", "New York", "Knicks", "006BB6", [], ["new york"]),
    team!(
        "OKC",
        "Oklahoma City",
        "Thunder",
        "007AC1",
        [],
        ["oklahoma city", "oklahoma", "okc"]
    ),
    team!("ORL", "Orlando", "Magic", "0077C0", [], ["orlando"]),
    team!(
        "PHI",
        "Philadelphia",
        "76ers",
        "006BB6",
        ["sixers", "76 ers"],
        ["philadelphia", "philadelphie", "philly"]
    ),
    team!("PHX", "Phoenix", "Suns", "1D1160", [], ["phoenix"]),
    team!(
        "POR",
        "Portland",
        "Trail Blazers",
        "E03A3E",
        ["blazers", "trailblazers"],
        ["portland"]
    ),
    team!("SAC", "Sacramento", "Kings", "5A2D81", [], ["sacramento"]),
    team!("SA", "San Antonio", "Spurs", "000000", [], ["san antonio"]),
    team!("TOR", "Toronto", "Raptors", "CE1141", [], ["toronto"]),
    team!("UTAH", "Utah", "Jazz", "002B5C", [], ["utah"]),
    team!("WSH", "Washington", "Wizards", "002B5C", [], ["washington"]),
];

/// Équipe par abréviation ESPN (insensible à la casse). Accepte aussi les
/// tricodes NBA officiels qui diffèrent (GSW, NYK, SAS, NOP, UTA, WAS, BRK).
pub fn by_abbr(abbr: &str) -> Option<&'static Team> {
    let up = abbr.trim().to_ascii_uppercase();
    let espn = match up.as_str() {
        "GSW" => "GS",
        "NYK" => "NY",
        "SAS" => "SA",
        "NOP" => "NO",
        "UTA" => "UTAH",
        "WAS" => "WSH",
        "BRK" => "BKN",
        "PHO" => "PHX",
        other => other,
    };
    TEAMS.iter().find(|t| t.abbr == espn)
}

/// Minuscules, sans accents, tout ce qui n'est pas alphanumérique devient un
/// espace unique : « L.A. Lakers » → « l a lakers ».
pub fn normalize(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last_space = true;
    for ch in text.chars().flat_map(char::to_lowercase) {
        let ch = match ch {
            'à' | 'â' | 'ä' | 'á' | 'ã' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' | 'í' => 'i',
            'ô' | 'ö' | 'ó' => 'o',
            'ù' | 'û' | 'ü' | 'ú' => 'u',
            'ç' => 'c',
            'ñ' => 'n',
            c => c,
        };
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_space = false;
        } else if !last_space {
            out.push(' ');
            last_space = true;
        }
    }
    out.trim_end().to_string()
}

/// Position (en octets, dans le texte normalisé) de `needle` comme suite de
/// mots entiers.
fn find_words(hay: &str, needle: &str) -> Option<usize> {
    let mut from = 0;
    while let Some(i) = hay[from..].find(needle) {
        let start = from + i;
        let end = start + needle.len();
        let left_ok = start == 0 || hay.as_bytes()[start - 1] == b' ';
        let right_ok = end == hay.len() || hay.as_bytes()[end] == b' ';
        if left_ok && right_ok {
            return Some(start);
        }
        from = start + 1;
    }
    None
}

/// Équipes citées dans un texte, dans l'ordre d'apparition, sans doublon.
///
/// Un surnom (« Lakers », « Sixers ») suffit toujours ; une ville seulement
/// quand elle est sans ambiguïté (pas « Los Angeles »).
pub fn extract_teams(text: &str) -> Vec<&'static Team> {
    let hay = normalize(text);
    let mut found: Vec<(usize, &'static Team)> = Vec::new();
    for team in &TEAMS {
        let nick = normalize(team.nickname);
        let positions = std::iter::once(nick.as_str())
            .chain(team.nick_aliases.iter().copied())
            .chain(team.city_aliases.iter().copied())
            .filter_map(|alias| find_words(&hay, alias));
        if let Some(pos) = positions.min() {
            found.push((pos, team));
        }
    }
    found.sort_by_key(|(pos, _)| *pos);
    found.into_iter().map(|(_, t)| t).collect()
}

/// Le texte mentionne-t-il la NBA ou le basket ?
pub fn mentions_nba(text: &str) -> bool {
    let hay = normalize(text);
    ["nba", "basket", "basketball", "basket ball"]
        .iter()
        .any(|w| find_words(&hay, w).is_some())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn abbrs(text: &str) -> Vec<&'static str> {
        extract_teams(text).iter().map(|t| t.abbr).collect()
    }

    #[test]
    fn trente_franchises_distinctes() {
        let mut set: Vec<_> = TEAMS.iter().map(|t| t.abbr).collect();
        set.sort();
        set.dedup();
        assert_eq!(set.len(), 30);
    }

    #[test]
    fn formes_courantes_de_l_epg() {
        assert_eq!(abbrs("NBA : Boston / Detroit"), ["BOS", "DET"]);
        assert_eq!(abbrs("Basket-ball - Celtics - Pistons"), ["BOS", "DET"]);
        assert_eq!(
            abbrs("NBA - L.A. Lakers @ Golden State Warriors"),
            ["LAL", "GS"]
        );
        assert_eq!(abbrs("LA Clippers vs Los Angeles Lakers"), ["LAC", "LAL"]);
        assert_eq!(abbrs("Philadelphie 76ers - New York Knicks"), ["PHI", "NY"]);
        assert_eq!(abbrs("Sixers / Trail Blazers"), ["PHI", "POR"]);
        assert_eq!(
            abbrs("Oklahoma City Thunder at San Antonio Spurs"),
            ["OKC", "SA"]
        );
    }

    #[test]
    fn los_angeles_seul_est_ambigu() {
        assert!(abbrs("Match à Los Angeles").is_empty());
    }

    #[test]
    fn pas_de_faux_positif_dans_un_mot() {
        // « heat » dans « heathrow », « magic » dans « magical » : refusés.
        assert!(abbrs("Heathrow magical").is_empty());
        // « Kings » de Sacramento reconnu seul, mais pas dans « Vikings ».
        assert_eq!(abbrs("Vikings"), Vec::<&str>::new());
        assert_eq!(abbrs("Kings"), ["SAC"]);
    }

    #[test]
    fn tricodes_nba_et_espn() {
        assert_eq!(by_abbr("GSW").unwrap().abbr, "GS");
        assert_eq!(by_abbr("utah").unwrap().nickname, "Jazz");
        assert_eq!(by_abbr("LAL").unwrap().full_name(), "Los Angeles Lakers");
        assert!(by_abbr("XXX").is_none());
        assert_eq!(
            by_abbr("NY").unwrap().logo_url(),
            "https://a.espncdn.com/i/teamlogos/nba/500/ny.png"
        );
    }

    #[test]
    fn mention_nba() {
        assert!(mentions_nba("Basket-ball : NBA"));
        assert!(mentions_nba("NBA Extra"));
        assert!(!mentions_nba("Ligue 1 : PSG / OM"));
    }
}
