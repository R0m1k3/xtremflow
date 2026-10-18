//! Guide TV construit à partir de dumps XMLTV publics.
//!
//! Beaucoup de panneaux Xtream servent un EPG figé depuis plusieurs jours, ou
//! n'en servent aucun : `get_simple_data_table` répond alors correctement mais
//! avec des programmes périmés. Ce service télécharge des dumps XMLTV
//! indépendants, les indexe par chaîne, et permet de compléter le guide.
//!
//! Le parsing est fait en flux (`quick-xml`, événement par événement) : un
//! dump national pèse couramment 50 Mo décompressés, en charger l'arbre DOM
//! complet coûterait plusieurs centaines de mégaoctets dans le conteneur.

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::sync::{Arc, LazyLock, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use chrono::{DateTime, NaiveDate, TimeDelta, Utc};
use futures::future::{BoxFuture, FutureExt, Shared};
use quick_xml::Reader;
use quick_xml::events::{BytesStart, Event};
use regex::Regex;

use crate::dart_time::utc_iso;
use crate::util::log_redactor::redact_url;

/// Index : clé de chaîne normalisée → programmes triés par heure de début.
///
/// Les clés d'alias (nom affiché, clé souple) partagent la même liste via
/// l'`Arc` : pas de copie des programmes par alias.
pub type XmltvIndex = HashMap<String, Arc<Vec<XmltvProgramme>>>;

/// Un programme du guide, horaires en UTC.
///
/// Les indicateurs (`is_new`, `is_live`, `is_premiere`, `previously_shown`)
/// reprennent les éléments vides XMLTV `<new/>`, `<live/>`, `<premiere/>` et
/// `<previously-shown/>` : ils servent à distinguer un direct d'une
/// rediffusion. Leur absence ne prouve rien — beaucoup de dumps ne les
/// renseignent jamais.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct XmltvProgramme {
    pub title: String,
    pub description: String,
    pub start: DateTime<Utc>,
    pub stop: DateTime<Utc>,
    /// `<sub-title>` (souvent l'affiche du match ou le titre d'épisode).
    pub sub_title: Option<String>,
    /// `<category>`, dans l'ordre du dump (l'élément peut se répéter).
    pub categories: Vec<String>,
    pub is_new: bool,
    pub is_live: bool,
    pub is_premiere: bool,
    pub previously_shown: bool,
}

impl XmltvProgramme {
    /// Forme JSON servie par l'API EPG (mêmes clés que le guide du panneau,
    /// plus les métadonnées XMLTV — absentes du guide du panneau, donc à lire
    /// comme facultatives côté client).
    pub fn to_json(&self, channel_id: &str) -> serde_json::Value {
        serde_json::json!({
            "title": self.title,
            "description": self.description,
            "start": utc_iso(self.start),
            "end": utc_iso(self.stop),
            "channel_id": channel_id,
            "sub_title": self.sub_title,
            "categories": self.categories,
            "is_new": self.is_new,
            "is_live": self.is_live,
            "is_premiere": self.is_premiere,
            "previously_shown": self.previously_shown,
        })
    }
}

/// Horizon d'indexation par défaut, en heures.
const DEFAULT_HORIZON_HOURS: u64 = 48;
/// Bornes de `EPG_HORIZON_HOURS` : en dessous de 12 h le guide se vide en
/// cours de soirée, au-delà de 14 jours aucun dump ne publie de programmes.
const MIN_HORIZON_HOURS: u64 = 12;
const MAX_HORIZON_HOURS: u64 = 336;

/// Horizon en heures lu depuis la valeur brute de `EPG_HORIZON_HOURS` :
/// défaut si absente ou illisible, ramenée dans les bornes sinon.
fn horizon_hours(raw: Option<&str>) -> u64 {
    raw.and_then(|v| v.trim().parse::<u64>().ok())
        .unwrap_or(DEFAULT_HORIZON_HOURS)
        .clamp(MIN_HORIZON_HOURS, MAX_HORIZON_HOURS)
}

/// Réglages du service.
#[derive(Clone, Debug)]
pub struct XmltvConfig {
    /// Dumps XMLTV à agréger, dans l'ordre de priorité décroissante.
    pub source_urls: Vec<String>,

    /// Fréquence de rafraîchissement de l'index.
    pub refresh_interval: Duration,

    /// Les programmes terminés depuis plus longtemps que cette durée sont
    /// écartés à l'indexation : personne ne consulte le guide d'hier, et les
    /// garder double la taille de l'index.
    pub retention: Duration,

    /// Les programmes qui commencent au-delà de cet horizon sont écartés à
    /// l'indexation.
    ///
    /// Un dump national couvre souvent sept jours pour un millier de chaînes ;
    /// tout garder en mémoire dans le conteneur coûte des centaines de
    /// mégaoctets pour un guide qui n'affiche que le programme courant et les
    /// suivants.
    pub horizon: Duration,

    /// Délai minimal entre deux tentatives quand aucune source n'a répondu.
    ///
    /// Sans ce recul, une source morte était retéléchargée à chaque
    /// consultation du guide — une requête sortante par chaîne affichée, soit
    /// exactement le flot qu'un index est censé éviter.
    pub retry_backoff: Duration,

    /// Plafond de téléchargement d'un dump. Le guide est facultatif : mieux
    /// vaut abandonner et servir le panneau que faire attendre l'utilisateur.
    pub download_timeout: Duration,
}

impl XmltvConfig {
    /// Réglages par défaut : rafraîchissement 6 h, rétention 6 h, horizon
    /// 48 h, recul 15 min après échec, téléchargement plafonné à 5 min.
    ///
    /// L'horizon se règle avec `EPG_HORIZON_HOURS` (12 à 336 h) : voir plus
    /// loin les matchs à enregistrer coûte de la mémoire d'index.
    pub fn new(source_urls: Vec<String>) -> Self {
        let horizon = horizon_hours(std::env::var("EPG_HORIZON_HOURS").ok().as_deref());
        Self {
            source_urls,
            refresh_interval: Duration::from_secs(6 * 3600),
            retention: Duration::from_secs(6 * 3600),
            horizon: Duration::from_secs(horizon * 3600),
            retry_backoff: Duration::from_secs(15 * 60),
            download_timeout: Duration::from_secs(5 * 60),
        }
    }
}

type Logger = Arc<dyn Fn(&str) + Send + Sync>;
type RefreshFuture = Shared<BoxFuture<'static, ()>>;

/// Service d'index XMLTV, partagé via `Arc<XmltvEpgService>`.
pub struct XmltvEpgService {
    inner: Arc<Inner>,
}

struct Inner {
    config: XmltvConfig,
    client: reqwest::Client,
    state: Mutex<State>,
    log: Logger,
}

#[derive(Default)]
struct State {
    index: Arc<XmltvIndex>,
    indexed_at: Option<Instant>,
    failed_at: Option<Instant>,
    /// Rafraîchissement en cours, partagé par les appels concurrents.
    refresh_in_flight: Option<RefreshFuture>,
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Libère la place du rafraîchissement en cours quand il se termine — même
/// s'il panique, sinon plus aucun rafraîchissement ne serait jamais relancé.
struct RefreshGuard(Arc<Inner>);

impl Drop for RefreshGuard {
    fn drop(&mut self) {
        self.0.lock().refresh_in_flight = None;
    }
}

/// Préfixe pays des noms de panneau : `FR - `, `FR: `, `|FR| `, `[FR] `…
static COUNTRY_PREFIX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        r"^{W}*[\|\[\(]?{W}*([A-Za-z]{{2,3}}){W}*[\|\]\)]?{W}*[-:|]{W}*|^{W}*[\|\[\(]{W}*([A-Za-z]{{2,3}}){W}*[\|\]\)]{W}*",
        W = JS_SPACE_CLASS
    ))
    .unwrap()
});

/// Marqueurs de qualité ou de source en fin de nom, sans rapport avec la
/// chaîne elle-même.
static QUALITY_SUFFIX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        r"(?i)({W}+|^)(fhd|uhd|hd|sd|hq|lq|4k|8k|hevc|h\.?265|h\.?264|1080p?|720p?|50fps|60fps|backup|raw|vip|multi|\(backup\)|\(multi\)){W}*$",
        W = JS_SPACE_CLASS
    ))
    .unwrap()
});

/// Symboles décoratifs (◉, ᴴᴰ, ★…) : tout ce qui n'est ni lettre, ni
/// chiffre, ni ponctuation utile.
static DECORATIVE_SYMBOLS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(&format!(r"[^\p{{L}}\p{{N}}{JS_SPACE_CHARS}+.&\-()]")).unwrap());

/// Abréviations du panneau pour les chaînes publiques (« F3 ALPES »), là
/// où les dumps écrivent `France.3.-.Alpes.fr`.
///
/// Le `\b` final de l'expression Dart (`^F\s?([2-5])\b`) est une limite de
/// mot ASCII : il est vérifié à la main dans [`XmltvEpgService::clean_channel_name`],
/// le `\b` de `regex` étant Unicode.
static FRANCE_ABBREV: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(&format!(r"(?i)^F{JS_SPACE_CLASS}?([2-5])")).unwrap());

/// Caractères de `\s` en JavaScript/Dart (diffère du `\s` Unicode de
/// `regex` : U+FEFF en plus, U+0085 en moins).
const JS_SPACE_CHARS: &str =
    r"\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}";
const JS_SPACE_CLASS: &str = r"[\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]";

fn is_js_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{0B}' | '\u{0C}' | '\r' | ' ' | '\u{A0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

/// `String.trim()` de Dart : espaces Unicode plus le BOM.
fn dart_trim(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace() || c == '\u{FEFF}')
}

/// Jetons sans valeur distinctive pour reconnaître une chaîne.
const LOOSE_NOISE: &[&str] = &["channel", "tv", "hd", "fhd", "uhd", "sd", "4k", "hevc"];

/// Codes pays en fin d'identifiant XMLTV (`TF1.fr`, `RTS1.ch`).
const COUNTRY_CODES: &[&str] = &[
    "fr", "be", "ch", "lu", "mc", "ca", "uk", "us", "es", "it", "de", "pt", "nl",
];

fn fold_accent(c: char) -> char {
    match c {
        'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' => 'a',
        'è' | 'é' | 'ê' | 'ë' => 'e',
        'ì' | 'í' | 'î' | 'ï' => 'i',
        'ò' | 'ó' | 'ô' | 'õ' | 'ö' => 'o',
        'ù' | 'ú' | 'û' | 'ü' => 'u',
        'ç' => 'c',
        'ñ' => 'n',
        other => other,
    }
}

fn loose_index_key(loose: &str) -> String {
    if loose.is_empty() {
        String::new()
    } else {
        format!("~{loose}")
    }
}

/// Positions des « +1 » (`\+\s*1(?![0-9])` côté Dart, écrit à la main faute
/// de look-ahead dans `regex`). Correspondances disjointes, de gauche à
/// droite, comme `replaceAll`.
fn plus_one_spans(s: &str) -> Vec<(usize, usize)> {
    let mut spans = Vec::new();
    let mut i = 0;
    while i < s.len() {
        if s[i..].starts_with('+') {
            let mut j = i + 1;
            while let Some(c) = s[j..].chars().next() {
                if !is_js_space(c) {
                    break;
                }
                j += c.len_utf8();
            }
            if s[j..].starts_with('1') {
                let end = j + 1;
                if !matches!(s[end..].chars().next(), Some('0'..='9')) {
                    spans.push((i, end));
                    i = end;
                    continue;
                }
            }
        }
        i += s[i..].chars().next().map_or(1, char::len_utf8);
    }
    spans
}

fn replace_plus_one(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut last = 0;
    for (start, end) in plus_one_spans(s) {
        out.push_str(&s[last..start]);
        out.push(' ');
        last = end;
    }
    out.push_str(&s[last..]);
    out
}

impl XmltvEpgService {
    pub fn new(config: XmltvConfig, client: reqwest::Client) -> Self {
        Self::with_logger(config, client, Arc::new(|line: &str| println!("{line}")))
    }

    fn with_logger(config: XmltvConfig, client: reqwest::Client, log: Logger) -> Self {
        Self {
            inner: Arc::new(Inner {
                config,
                client,
                state: Mutex::new(State::default()),
                log,
            }),
        }
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn has_data(&self) -> bool {
        !self.inner.lock().index.is_empty()
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn channel_count(&self) -> usize {
        self.inner.lock().index.len()
    }

    /// Programmes d'une chaîne, ou liste vide si inconnue.
    ///
    /// `channel_id` est l'`epg_channel_id` renvoyé par Xtream ; `display_name`
    /// est le nom de la chaîne, utilisé en second recours car les dumps publics
    /// construisent souvent leur identifiant à partir du nom affiché.
    pub async fn programmes_for(
        &self,
        channel_id: Option<&str>,
        display_name: Option<&str>,
    ) -> Vec<XmltvProgramme> {
        self.ensure_fresh().await;
        let index = Arc::clone(&self.inner.lock().index);

        if let Some(direct) = lookup(&index, channel_id, display_name) {
            return direct.as_ref().clone();
        }

        // Chaîne décalée sans guide propre (« TF1 +1 » absent des dumps) : le
        // guide de la chaîne principale, une heure plus tard, est exact.
        if let Some(name) = display_name
            && !plus_one_spans(name).is_empty()
        {
            let base = replace_plus_one(name);
            let hour = TimeDelta::hours(1);
            return lookup(&index, None, Some(&base))
                .map(|hits| {
                    hits.iter()
                        .map(|p| XmltvProgramme {
                            start: p.start + hour,
                            stop: p.stop + hour,
                            ..p.clone()
                        })
                        .collect()
                })
                .unwrap_or_default();
        }
        Vec::new()
    }

    /// Clé « souple » : sans code pays final ni mots génériques
    /// (« AB3.Channel.fr » et « AB3 » → `ab3`).
    ///
    /// Servie dans un espace de noms à part, consultée en tout dernier : elle
    /// rattrape les variantes d'écriture sans fausser les correspondances
    /// exactes.
    pub fn loose_key(raw: Option<&str>) -> String {
        let Some(raw) = raw else {
            return String::new();
        };
        let folded: String = raw.to_lowercase().chars().map(fold_accent).collect();
        let mut tokens: Vec<&str> = folded
            .split(|c: char| !matches!(c, 'a'..='z' | '0'..='9'))
            .filter(|t| !t.is_empty())
            .collect();
        if tokens.len() > 1 && tokens.last().is_some_and(|t| COUNTRY_CODES.contains(t)) {
            tokens.pop();
        }
        tokens.retain(|t| !LOOSE_NOISE.contains(t));
        tokens.concat()
    }

    /// Clés candidates pour retrouver une chaîne du panneau par son nom.
    ///
    /// POURQUOI : en prod, 59 % des chaînes françaises n'ont pas
    /// d'`epg_channel_id`. Leur nom brut (« FR - TF1 FHD ◉ » → `frtf1fhd`) ne
    /// correspond à aucune entrée XMLTV (`TF1.fr`, « TF1 »). On retire le
    /// préfixe pays, les marqueurs de qualité et les symboles, puis on tente
    /// aussi la forme `nom.pays` qu'utilisent les dumps publics.
    ///
    /// Le décalage horaire (« +1 ») est conservé : TF1 +1 n'a pas le guide
    /// de TF1.
    pub fn name_keys(name: &str) -> Vec<String> {
        let mut candidates = vec![Self::normalize_key(Some(name))];
        let (cleaned, country) = Self::clean_channel_name(name);
        let base = Self::normalize_key(Some(&cleaned));
        if !base.is_empty() {
            let suffixed = format!("{base}{}", country.as_deref().unwrap_or("fr"));
            candidates.push(base);
            candidates.push(suffixed);
        }
        // Dédoublonnage en gardant l'ordre (le `toSet()` de Dart est ordonné).
        let mut seen = HashSet::new();
        candidates
            .into_iter()
            .filter(|k| !k.is_empty() && seen.insert(k.clone()))
            .collect()
    }

    /// Nom de chaîne débarrassé du préfixe pays, des symboles et des
    /// marqueurs de qualité ; second élément = code pays du préfixe, s'il y
    /// en a.
    pub fn clean_channel_name(raw: &str) -> (String, Option<String>) {
        let mut cleaned: &str = raw;
        let mut country = None;
        if let Some(caps) = COUNTRY_PREFIX.captures(raw) {
            country = caps
                .get(1)
                .or_else(|| caps.get(2))
                .map(|m| m.as_str().to_lowercase());
            cleaned = &raw[caps.get(0).map_or(0, |m| m.end())..];
        }
        // Symboles décoratifs (◉, ᴴᴰ, ★…) : tout ce qui n'est ni lettre, ni
        // chiffre, ni ponctuation utile.
        let mut cleaned = dart_trim(&DECORATIVE_SYMBOLS.replace_all(cleaned, " ")).to_string();
        loop {
            let previous = cleaned.clone();
            cleaned = dart_trim(&QUALITY_SUFFIX.replacen(&cleaned, 1, "")).to_string();
            if cleaned == previous || cleaned.is_empty() {
                break;
            }
        }
        if let Some(caps) = FRANCE_ABBREV.captures(&cleaned) {
            let whole = caps.get(0).unwrap();
            // Limite de mot ASCII après le chiffre (le `\b` de Dart).
            let boundary = !matches!(
                cleaned[whole.end()..].chars().next(),
                Some('a'..='z' | 'A'..='Z' | '0'..='9' | '_')
            );
            if boundary {
                cleaned = format!("France {}{}", &caps[1], &cleaned[whole.end()..]);
            }
        }
        (cleaned, country)
    }

    /// Recharge l'index s'il est absent ou périmé. Les appels concurrents
    /// partagent le même téléchargement.
    ///
    /// Le rafraîchissement tourne dans sa propre tâche : comme une `Future`
    /// Dart, il va au bout même si l'appelant abandonne (requête HTTP coupée).
    pub async fn ensure_fresh(&self) {
        // Sans source, `_refresh` Dart ne faisait rien : inutile de lancer une
        // tâche.
        if self.inner.config.source_urls.is_empty() {
            return;
        }
        let pending = {
            let mut state = self.inner.lock();
            if state
                .indexed_at
                .is_some_and(|at| at.elapsed() < self.inner.config.refresh_interval)
            {
                return;
            }
            if state
                .failed_at
                .is_some_and(|at| at.elapsed() < self.inner.config.retry_backoff)
            {
                return;
            }
            match &state.refresh_in_flight {
                Some(pending) => pending.clone(),
                None => {
                    let inner = Arc::clone(&self.inner);
                    let task = tokio::spawn(async move {
                        let _guard = RefreshGuard(Arc::clone(&inner));
                        refresh(&inner).await;
                    });
                    let pending = async move {
                        let _ = task.await;
                    }
                    .boxed()
                    .shared();
                    state.refresh_in_flight = Some(pending.clone());
                    pending
                }
            }
        };
        pending.await;
    }

    /// Exposé pour les tests. Un XML illisible (où Dart levait une exception)
    /// donne un index vide.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn parse_for_test(&self, xml: &str) -> XmltvIndex {
        parse(xml, self.inner.config.retention, self.inner.config.horizon).unwrap_or_default()
    }

    /// Clé de correspondance : minuscules, sans ponctuation ni accents.
    ///
    /// Les dumps publics écrivent `France.2.fr` là où le panneau annonce
    /// `France2.fr` ; sans normalisation, la moitié des chaînes ne trouvent
    /// jamais leur guide.
    pub fn normalize_key(raw: Option<&str>) -> String {
        let Some(raw) = raw else {
            return String::new();
        };
        raw.to_lowercase()
            .chars()
            .map(fold_accent)
            .filter(|c| matches!(c, 'a'..='z' | '0'..='9'))
            .collect()
    }

    /// « 20260811200000 +0200 » → instant UTC.
    ///
    /// Reproduit `DateTime.tryParse` de Dart : 14 chiffres ASCII exigés, les
    /// valeurs hors bornes (mois 13, jour 32…) étant reportées sur l'unité
    /// supérieure plutôt que rejetées. Longueurs et positions comptées en
    /// unités UTF-16, comme en Dart.
    pub fn parse_xmltv_date(raw: Option<&str>) -> Option<DateTime<Utc>> {
        let raw = raw?;
        let units: Vec<u16> = raw.encode_utf16().collect();
        if units.len() < 14 {
            return None;
        }
        let digits = &units[..14];
        if !digits
            .iter()
            .all(|u| (b'0' as u16..=b'9' as u16).contains(u))
        {
            return None;
        }
        let num = |range: std::ops::Range<usize>| -> i64 {
            digits[range]
                .iter()
                .fold(0i64, |acc, u| acc * 10 + i64::from(*u - b'0' as u16))
        };
        let base = dart_utc(
            num(0..4),
            num(4..6),
            num(6..8),
            num(8..10),
            num(10..12),
            num(12..14),
        )?;

        if units.len() < 20 {
            return Some(base);
        }
        let offset = &units[15..20];
        let sign: i64 = if offset[0] == b'-' as u16 { -1 } else { 1 };
        let (Some(hours), Some(minutes)) = (
            dart_int_try_parse(&String::from_utf16_lossy(&offset[1..3])),
            dart_int_try_parse(&String::from_utf16_lossy(&offset[3..5])),
        ) else {
            return Some(base);
        };
        base.checked_sub_signed(TimeDelta::hours(sign * hours) + TimeDelta::minutes(sign * minutes))
    }
}

/// `DateTime.utc(y, m, d, h, min, s)` de Dart, avec report des valeurs hors
/// bornes (mois 0 → décembre précédent, jour 0 → veille du 1er, etc.).
fn dart_utc(
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
) -> Option<DateTime<Utc>> {
    let months = year * 12 + (month - 1);
    let y = i32::try_from(months.div_euclid(12)).ok()?;
    let m = u32::try_from(months.rem_euclid(12) + 1).ok()?;
    let first = NaiveDate::from_ymd_opt(y, m, 1)?.and_hms_opt(0, 0, 0)?;
    let delta = TimeDelta::days(day - 1)
        + TimeDelta::hours(hour)
        + TimeDelta::minutes(minute)
        + TimeDelta::seconds(second);
    Some(first.checked_add_signed(delta)?.and_utc())
}

/// `int.tryParse` de Dart (base 10) : espaces autour tolérés, signe
/// facultatif.
fn dart_int_try_parse(raw: &str) -> Option<i64> {
    let s = dart_trim(raw);
    let (negative, digits) = match s.as_bytes().first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let value: i64 = digits.parse().ok()?;
    Some(if negative { -value } else { value })
}

fn lookup(
    index: &XmltvIndex,
    channel_id: Option<&str>,
    display_name: Option<&str>,
) -> Option<Arc<Vec<XmltvProgramme>>> {
    let mut keys = vec![XmltvEpgService::normalize_key(channel_id)];
    if let Some(name) = display_name {
        keys.extend(XmltvEpgService::name_keys(name));
    }
    // Clés souples en dernier recours, dans leur propre espace de noms.
    keys.push(loose_index_key(&XmltvEpgService::loose_key(channel_id)));
    if let Some(name) = display_name {
        let (cleaned, _) = XmltvEpgService::clean_channel_name(name);
        keys.push(loose_index_key(&XmltvEpgService::loose_key(Some(&cleaned))));
    }
    keys.iter()
        .filter(|k| !k.is_empty())
        .find_map(|k| index.get(k).filter(|hit| !hit.is_empty()).cloned())
}

/// Ligne de journal d'une source en échec. L'URL (déjà masquée) peut être le
/// `xmltv.php` du panneau, identifiants de l'abonné en clair ; le texte de
/// l'erreur est masqué aussi, les erreurs HTTP recopiant l'URL demandée.
fn failure_line(safe_url: &str, error: &str) -> String {
    format!("[XmltvEpg] {safe_url} : échec ({})", redact_url(error))
}

async fn refresh(inner: &Arc<Inner>) {
    let config = &inner.config;
    if config.source_urls.is_empty() {
        return;
    }

    let mut merged = XmltvIndex::new();
    let mut ok = 0;

    for url in &config.source_urls {
        // La source peut être le `xmltv.php` du panneau, dont l'URL porte les
        // identifiants de l'abonné en clair : ne jamais la journaliser telle
        // quelle (elle finirait dans `docker logs`). Le texte de l'erreur est
        // masqué aussi, reqwest recopiant l'URL demandée.
        let safe_url = redact_url(url);
        match download_and_parse(inner, url).await {
            Ok(parsed) => {
                let count = parsed.len();
                // Première source servie gagne : les suivantes ne comblent que
                // les chaînes encore absentes.
                if merged.is_empty() {
                    merged = parsed;
                } else {
                    for (key, programmes) in parsed {
                        merged.entry(key).or_insert(programmes);
                    }
                }
                ok += 1;
                (inner.log)(&format!("[XmltvEpg] {safe_url} : {count} chaînes indexées"));
            }
            Err(error) => (inner.log)(&failure_line(&safe_url, &error)),
        }
    }

    if ok == 0 {
        // Garder l'index précédent plutôt que de servir un guide vide.
        inner.lock().failed_at = Some(Instant::now());
        (inner.log)("[XmltvEpg] aucune source disponible, index précédent conservé");
        return;
    }

    let count = merged.len();
    let previous = {
        let mut state = inner.lock();
        state.indexed_at = Some(Instant::now());
        state.failed_at = None;
        std::mem::replace(&mut state.index, Arc::new(merged))
    };
    (inner.log)(&format!("[XmltvEpg] index prêt : {count} chaînes"));
    // Libérer l'ancien index (des centaines de milliers de chaînes de
    // caractères) hors de la boucle asynchrone.
    tokio::task::spawn_blocking(move || drop(previous));
}

/// Télécharge `url` puis l'indexe sur un thread bloquant dédié.
///
/// Décompresser et parser un dump de plusieurs milliers de chaînes sur la
/// boucle asynchrone la gelait pendant des secondes. Plus rien d'autre ne
/// répondait — en particulier le relais `turbo.ts`, qui cessait d'envoyer des
/// octets au lecteur : la lecture se coupait systématiquement au démarrage,
/// au moment précis où l'écran des chaînes demandait le guide.
async fn download_and_parse(inner: &Inner, url: &str) -> Result<XmltvIndex, String> {
    let timeout = inner.config.download_timeout;
    let body = match tokio::time::timeout(timeout, download(&inner.client, url)).await {
        Ok(result) => result?,
        Err(_) => {
            return Err(format!(
                "TimeoutException after {}: Future not completed",
                dart_duration(timeout)
            ));
        }
    };
    let retention = inner.config.retention;
    let horizon = inner.config.horizon;
    tokio::task::spawn_blocking(move || decode_and_parse(&body, retention, horizon))
        .await
        .map_err(|e| e.to_string())?
}

async fn download(client: &reqwest::Client, url: &str) -> Result<bytes::Bytes, String> {
    let response = client.get(url).send().await.map_err(|e| error_text(&e))?;
    let status = response.status().as_u16();
    if status != 200 {
        return Err(format!("HttpException: HTTP {status}"));
    }
    response.bytes().await.map_err(|e| error_text(&e))
}

/// Texte d'une erreur avec ses causes (reqwest cache la cause réelle —
/// connexion refusée, DNS… — derrière un message générique).
fn error_text(error: &dyn std::error::Error) -> String {
    let mut text = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        text.push_str(": ");
        text.push_str(&cause.to_string());
        source = cause.source();
    }
    text
}

/// Format `Duration.toString()` de Dart : `0:05:00.000000`.
fn dart_duration(d: Duration) -> String {
    let micros = d.as_micros();
    let hours = micros / 3_600_000_000;
    let minutes = (micros / 60_000_000) % 60;
    let seconds = (micros / 1_000_000) % 60;
    let fraction = micros % 1_000_000;
    format!("{hours}:{minutes:02}:{seconds:02}.{fraction:06}")
}

fn decode_and_parse(
    raw: &[u8],
    retention: Duration,
    horizon: Duration,
) -> Result<XmltvIndex, String> {
    // Beaucoup de miroirs servent du .gz sans en-tête Content-Encoding : on
    // regarde le nombre magique plutôt que de se fier aux en-têtes.
    let inflated;
    let bytes = if raw.len() > 2 && raw[0] == 0x1f && raw[1] == 0x8b {
        let mut out = Vec::new();
        flate2::read::MultiGzDecoder::new(raw)
            .read_to_end(&mut out)
            .map_err(|e| format!("FormatException: {e}"))?;
        inflated = out;
        &inflated[..]
    } else {
        raw
    };
    parse(&String::from_utf8_lossy(bytes), retention, horizon)
}

#[derive(Clone, Copy, PartialEq)]
enum TextTag {
    Title,
    Desc,
    SubTitle,
    Category,
    DisplayName,
}

/// Métadonnées XMLTV d'un `<programme>` en cours de lecture.
#[derive(Default)]
struct ProgrammeMeta {
    sub_title: String,
    category: String,
    categories: Vec<String>,
    is_new: bool,
    is_live: bool,
    is_premiere: bool,
    previously_shown: bool,
}

/// Valeur d'un attribut (entités décodées), ou chaîne vide s'il est absent.
fn attr(event: &BytesStart<'_>, name: &[u8]) -> String {
    let mut attributes = event.attributes();
    attributes.with_checks(false);
    for attribute in attributes {
        // Attribut mal formé : traité comme absent plutôt que de rejeter le
        // dump entier.
        let Ok(attribute) = attribute else { break };
        if attribute.key.as_ref() == name {
            return decode_entities(&String::from_utf8_lossy(&attribute.value)).into_owned();
        }
    }
    String::new()
}

/// Décodage des entités comme le paquet Dart `xml` : les cinq entités XML et
/// les références numériques ; toute entité inconnue ou invalide reste telle
/// quelle (une entité fautive ne doit pas faire échouer tout le dump).
fn decode_entities(input: &str) -> Cow<'_, str> {
    let Some(first) = input.find('&') else {
        return Cow::Borrowed(input);
    };
    let mut out = String::with_capacity(input.len());
    out.push_str(&input[..first]);
    let mut rest = &input[first..];
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        rest = &rest[amp..];
        let Some(semicolon) = rest.find(';') else {
            // Plus aucun `;` : aucune entité ne peut suivre.
            break;
        };
        match decode_entity(&rest[1..semicolon]) {
            Some(c) => {
                out.push(c);
                rest = &rest[semicolon + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    Cow::Owned(out)
}

fn decode_entity(entity: &str) -> Option<char> {
    match entity {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        _ => {
            let number = entity.strip_prefix('#')?;
            let code = if let Some(hex) = number.strip_prefix(['x', 'X']) {
                if hex.is_empty() || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return None;
                }
                u32::from_str_radix(hex, 16).ok()?
            } else {
                if number.is_empty() || !number.bytes().all(|b| b.is_ascii_digit()) {
                    return None;
                }
                number.parse().ok()?
            };
            char::from_u32(code)
        }
    }
}

fn parse(xml: &str, retention: Duration, horizon: Duration) -> Result<XmltvIndex, String> {
    let now = Utc::now();
    let cutoff = TimeDelta::from_std(retention)
        .ok()
        .and_then(|d| now.checked_sub_signed(d))
        .unwrap_or(DateTime::<Utc>::MIN_UTC);
    let limit = TimeDelta::from_std(horizon)
        .ok()
        .and_then(|d| now.checked_add_signed(d))
        .unwrap_or(DateTime::<Utc>::MAX_UTC);
    let mut by_channel: HashMap<String, Vec<XmltvProgramme>> = HashMap::new();

    // Alias : plusieurs dumps déclarent <channel id="X"> avec un ou plusieurs
    // <display-name> différents de l'identifiant (« TF1 HD », « TF1 »). On
    // les indexe TOUS : seul le premier l'était, et c'était souvent la
    // variante la moins proche du nom annoncé par le panneau.
    // Ordre d'insertion conservé (`Map` ordonnée en Dart) : l'application
    // des alias en dépend.
    let mut aliases: Vec<(String, String)> = Vec::new();
    let mut alias_names: HashSet<String> = HashSet::new();
    let mut put_alias = |name: String, id: &str| {
        if alias_names.insert(name.clone()) {
            aliases.push((name, id.to_string()));
        }
    };
    let mut display_names: Vec<String> = Vec::new();

    let mut channel_id: Option<String> = None;
    let mut programme_channel: Option<String> = None;
    let mut start: Option<DateTime<Utc>> = None;
    let mut stop: Option<DateTime<Utc>> = None;
    let mut current_tag: Option<TextTag> = None;
    let mut title = String::new();
    let mut desc = String::new();
    let mut meta = ProgrammeMeta::default();
    let mut display_name = String::new();
    // Les programmes d'une chaîne se suivent : mémoriser la dernière clé
    // évite de renormaliser le même identifiant des milliers de fois.
    let mut last_key: Option<(String, String)> = None;

    let mut reader = Reader::from_str(xml);
    {
        // Lecture non validante, comme `parseEvents` côté Dart.
        let config = reader.config_mut();
        config.trim_text(false);
        config.check_end_names = false;
        config.allow_unmatched_ends = true;
        config.expand_empty_elements = false;
    }

    loop {
        let event = reader
            .read_event()
            .map_err(|e| format!("XmlParserException: {e} at {}", reader.error_position()))?;
        match event {
            Event::Eof => break,
            Event::Start(ref e) | Event::Empty(ref e) => {
                match e.name().as_ref() {
                    b"channel" => {
                        channel_id = Some(attr(e, b"id"));
                        display_name.clear();
                        display_names.clear();
                    }
                    b"programme" => {
                        programme_channel = Some(attr(e, b"channel"));
                        start = XmltvEpgService::parse_xmltv_date(Some(&attr(e, b"start")));
                        stop = XmltvEpgService::parse_xmltv_date(Some(&attr(e, b"stop")));
                        title.clear();
                        desc.clear();
                        meta = ProgrammeMeta::default();
                    }
                    b"title" => current_tag = Some(TextTag::Title),
                    b"desc" => current_tag = Some(TextTag::Desc),
                    b"sub-title" => current_tag = Some(TextTag::SubTitle),
                    b"category" => {
                        meta.category.clear();
                        current_tag = Some(TextTag::Category);
                    }
                    b"display-name" => current_tag = Some(TextTag::DisplayName),
                    // Indicateurs : vides en principe (`<new/>`), mais
                    // `<premiere>` porte parfois un texte et `<previously-shown>`
                    // des attributs — seule la présence compte.
                    b"new" => meta.is_new = true,
                    b"live" => meta.is_live = true,
                    b"premiere" => meta.is_premiere = true,
                    b"previously-shown" => meta.previously_shown = true,
                    _ => {}
                }
                if matches!(event, Event::Empty(_)) {
                    current_tag = None;
                }
            }
            Event::Text(ref t) => {
                if let Some(tag) = current_tag {
                    let raw = String::from_utf8_lossy(t.as_ref());
                    let text = decode_entities(&raw);
                    match tag {
                        TextTag::Title => title.push_str(&text),
                        TextTag::Desc => desc.push_str(&text),
                        TextTag::SubTitle => meta.sub_title.push_str(&text),
                        TextTag::Category => meta.category.push_str(&text),
                        TextTag::DisplayName => display_name.push_str(&text),
                    }
                }
            }
            Event::CData(ref c) => {
                if let Some(tag) = current_tag {
                    let text = String::from_utf8_lossy(c.as_ref());
                    match tag {
                        TextTag::Title => title.push_str(&text),
                        TextTag::Desc => desc.push_str(&text),
                        TextTag::SubTitle => meta.sub_title.push_str(&text),
                        TextTag::Category => meta.category.push_str(&text),
                        TextTag::DisplayName => display_name.push_str(&text),
                    }
                }
            }
            Event::End(ref e) => {
                match e.name().as_ref() {
                    b"display-name" => {
                        display_names.push(std::mem::take(&mut display_name));
                    }
                    b"category" => {
                        let category = dart_trim(&meta.category);
                        if !category.is_empty() {
                            meta.categories.push(category.to_string());
                        }
                        meta.category.clear();
                    }
                    b"channel" => {
                        let id = XmltvEpgService::normalize_key(channel_id.as_deref());
                        for raw in &display_names {
                            let name = XmltvEpgService::normalize_key(Some(raw));
                            if !id.is_empty() && !name.is_empty() && id != name {
                                put_alias(name, &id);
                            }
                        }
                        // Clés souples (espace de noms « ~ ») : premier arrivé
                        // gagne.
                        if !id.is_empty() {
                            let raws = std::iter::once(channel_id.as_deref())
                                .chain(display_names.iter().map(|s| Some(s.as_str())));
                            for raw in raws {
                                let loose = loose_index_key(&XmltvEpgService::loose_key(raw));
                                if !loose.is_empty() {
                                    put_alias(loose, &id);
                                }
                            }
                        }
                        channel_id = None;
                    }
                    b"programme" => {
                        if let (Some(channel), Some(s), Some(e)) = (&programme_channel, start, stop)
                            && e > cutoff
                            && s < limit
                        {
                            let key = match &last_key {
                                Some((raw, key)) if raw == channel => key.clone(),
                                _ => {
                                    let key = XmltvEpgService::normalize_key(Some(channel));
                                    last_key = Some((channel.clone(), key.clone()));
                                    key
                                }
                            };
                            if !key.is_empty() {
                                let meta = std::mem::take(&mut meta);
                                let sub_title = dart_trim(&meta.sub_title);
                                by_channel.entry(key).or_default().push(XmltvProgramme {
                                    title: dart_trim(&title).to_string(),
                                    description: dart_trim(&desc).to_string(),
                                    start: s,
                                    stop: e,
                                    sub_title: (!sub_title.is_empty())
                                        .then(|| sub_title.to_string()),
                                    categories: meta.categories,
                                    is_new: meta.is_new,
                                    is_live: meta.is_live,
                                    is_premiere: meta.is_premiere,
                                    previously_shown: meta.previously_shown,
                                });
                            }
                        }
                        programme_channel = None;
                        start = None;
                        stop = None;
                    }
                    _ => {}
                }
                current_tag = None;
            }
            _ => {}
        }
    }

    let mut index: XmltvIndex = by_channel
        .into_iter()
        .map(|(key, mut list)| {
            list.sort_by_key(|a| a.start);
            (key, Arc::new(list))
        })
        .collect();

    // Rendre les chaînes atteignables aussi par leur nom affiché.
    for (name, id) in aliases {
        if let Some(programmes) = index.get(&id).cloned() {
            index.entry(name).or_insert(programmes);
        }
    }

    Ok(index)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::Router;
    use axum::http::{StatusCode, Uri};
    use chrono::Timelike;
    use std::io::Write;
    use std::sync::atomic::{AtomicUsize, Ordering};

    type Svc = XmltvEpgService;

    fn stamp(d: DateTime<Utc>) -> String {
        d.format("%Y%m%d%H%M%S +0000").to_string()
    }

    /// Extrait représentatif d'un dump XMLTV public : décalage horaire
    /// explicite, identifiant ponctué côté source là où le panneau annonce
    /// `France2.fr`, et un `display-name` distinct de l'identifiant.
    fn fixture(start: DateTime<Utc>, stop: DateTime<Utc>) -> String {
        format!(
            r#"<?xml version="1.0" encoding="utf-8" ?>
<tv>
  <channel id="France.2.fr"><display-name>FR - FRANCE 2</display-name></channel>
  <programme start="{}" stop="{}" channel="France.2.fr">
    <title lang="fr">Journal de 20h</title>
    <desc lang="fr">L'info du soir</desc>
  </programme>
</tv>
"#,
            stamp(start),
            stamp(stop)
        )
    }

    fn offline_service() -> Svc {
        Svc::new(XmltvConfig::new(vec![]), reqwest::Client::new())
    }

    /// Mini serveur HTTP local (remplace le `MockClient` Dart) : compte les
    /// appels et renvoie `(statut, corps)`.
    async fn serve(
        respond: impl Fn(&Uri) -> (StatusCode, bytes::Bytes) + Send + Sync + 'static,
    ) -> (String, Arc<AtomicUsize>) {
        let calls = Arc::new(AtomicUsize::new(0));
        let respond = Arc::new(respond);
        let counter = Arc::clone(&calls);
        let app = Router::new().fallback(move |uri: Uri| {
            let respond = Arc::clone(&respond);
            let counter = Arc::clone(&counter);
            async move {
                counter.fetch_add(1, Ordering::SeqCst);
                respond(&uri)
            }
        });
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        (format!("http://{addr}"), calls)
    }

    async fn service_with(dump: String) -> (Svc, Arc<AtomicUsize>) {
        let body = bytes::Bytes::from(dump.into_bytes());
        let (base, calls) = serve(move |_| (StatusCode::OK, body.clone())).await;
        let svc = Svc::new(
            XmltvConfig::new(vec![format!("{base}/epg.xml")]),
            reqwest::Client::new(),
        );
        (svc, calls)
    }

    fn now_s() -> DateTime<Utc> {
        Utc::now().with_nanosecond(0).unwrap()
    }

    // --- normalizeKey ---

    #[test]
    fn normalize_rapproche_les_identifiants_ponctues_differemment() {
        // Le cœur du repli : sans cette normalisation, `France2.fr` du panneau
        // et `France.2.fr` du dump ne se rencontrent jamais.
        assert_eq!(
            Svc::normalize_key(Some("France2.fr")),
            Svc::normalize_key(Some("France.2.fr"))
        );
    }

    #[test]
    fn normalize_replie_la_casse_et_les_accents() {
        assert_eq!(Svc::normalize_key(Some("Chérie 25")), "cherie25");
    }

    #[test]
    fn normalize_rend_une_cle_vide_sur_entree_nulle_ou_sans_caractere_utile() {
        assert_eq!(Svc::normalize_key(None), "");
        assert_eq!(Svc::normalize_key(Some("...")), "");
    }

    // --- nameKeys ---

    fn has(keys: &[String], k: &str) -> bool {
        keys.iter().any(|x| x == k)
    }

    #[test]
    fn name_keys_retire_le_prefixe_pays_et_les_marqueurs_de_qualite() {
        assert!(has(&Svc::name_keys("FR - TF1 FHD ◉"), "tf1"));
        assert!(has(&Svc::name_keys("FR - FRANCE 4 FHD"), "france4"));
        assert!(has(&Svc::name_keys("|FR| M6 HD"), "m6"));
        assert!(has(&Svc::name_keys("[FR] Arte UHD 4K"), "arte"));
        assert!(has(&Svc::name_keys("FR: RMC Story HEVC"), "rmcstory"));
    }

    #[test]
    fn name_keys_propose_aussi_la_forme_nom_pays() {
        // Les dumps publics identifient souvent la chaîne par `TF1.fr`.
        assert!(has(&Svc::name_keys("FR - TF1 FHD"), "tf1fr"));
    }

    #[test]
    fn name_keys_garde_la_variante_decalee_distincte() {
        assert!(!has(&Svc::name_keys("FR - TF1 +1 FHD"), "tf1"));
    }

    #[test]
    fn name_keys_ne_reduit_pas_un_nom_court_a_rien() {
        assert!(has(&Svc::name_keys("M6"), "m6"));
        assert!(!has(&Svc::name_keys("HD"), ""));
    }

    #[test]
    fn clean_channel_name_rend_le_pays_et_developpe_f3() {
        assert_eq!(
            Svc::clean_channel_name("FR - F3 ALPES HD"),
            ("France 3 ALPES".to_string(), Some("fr".to_string()))
        );
        assert_eq!(Svc::clean_channel_name("TF1"), ("TF1".to_string(), None));
        // `\b` ASCII de Dart : « F2é » se développe, « F2x » non.
        assert_eq!(Svc::clean_channel_name("F2é").0, "France 2é");
        assert_eq!(Svc::clean_channel_name("F2x").0, "F2x");
    }

    #[test]
    fn plus_one_se_comporte_comme_le_lookahead_dart() {
        assert_eq!(replace_plus_one("TF1 +1 FHD"), "TF1   FHD");
        assert_eq!(replace_plus_one("TF1 + 1"), "TF1  ");
        assert!(plus_one_spans("Canal +10").is_empty());
        assert!(plus_one_spans("Canal+").is_empty());
        assert_eq!(replace_plus_one("A+1+1"), "A  ");
    }

    // --- correspondances élargies (chaînes vides mesurées en prod) ---

    fn channel(id: &str, name: &str, title: &str, start: DateTime<Utc>) -> String {
        format!(
            r#"
  <channel id="{id}"><display-name>{name}</display-name></channel>
  <programme start="{}" stop="{}" channel="{id}"><title>{title}</title></programme>"#,
            stamp(start),
            stamp(start + TimeDelta::hours(1))
        )
    }

    #[tokio::test]
    async fn f3_alpes_du_panneau_trouve_france_3_alpes() {
        let now = now_s();
        let (svc, _) = service_with(format!(
            "<tv>{}</tv>",
            channel("France.3.-.Alpes.fr", "France 3 Alpes", "JT Alpes", now)
        ))
        .await;
        let hits = svc.programmes_for(None, Some("FR - F3 ALPES HD")).await;
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "JT Alpes");
    }

    #[tokio::test]
    async fn ab3_trouve_ab3_channel_fr_par_cle_souple() {
        let now = now_s();
        let (svc, _) = service_with(format!(
            "<tv>{}</tv>",
            channel("AB3.Channel.fr", "AB3 Channel", "Série", now)
        ))
        .await;
        let hits = svc
            .programmes_for(Some("AB3.fr"), Some("FR - AB3 FHD"))
            .await;
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "Série");
    }

    #[tokio::test]
    async fn tf1_plus_1_reprend_le_guide_de_tf1_decale_d_une_heure() {
        let now = now_s();
        let (svc, _) = service_with(format!(
            "<tv>{}</tv>",
            channel("TF1.fr", "TF1", "Le 13h", now)
        ))
        .await;
        let hits = svc.programmes_for(None, Some("FR - TF1 +1 FHD")).await;
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "Le 13h");
        assert_eq!(hits[0].start, now + TimeDelta::hours(1));
    }

    #[tokio::test]
    async fn une_chaine_plus_1_qui_a_son_propre_guide_le_garde() {
        let now = now_s();
        let (svc, _) = service_with(format!(
            "<tv>{}{}</tv>",
            channel("Boomerang.fr", "Boomerang", "Normal", now),
            channel("Boomerang.+1.fr", "Boomerang +1", "Décalé", now)
        ))
        .await;
        let hits = svc.programmes_for(None, Some("FR - BOOMERANG +1")).await;
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "Décalé");
    }

    // --- programmesFor par nom ---

    #[tokio::test]
    async fn trouve_le_guide_d_une_chaine_sans_epg_channel_id_par_son_nom() {
        let now = now_s();
        let dump = format!(
            r#"<tv>
  <channel id="TF1.fr"><display-name>TF1 HD</display-name><display-name>TF1</display-name></channel>
  <programme start="{}" stop="{}" channel="TF1.fr">
    <title>Le 13h</title>
  </programme>
</tv>
"#,
            stamp(now),
            stamp(now + TimeDelta::hours(1))
        );
        let (svc, _) = service_with(dump).await;
        let hits = svc.programmes_for(None, Some("FR - TF1 FHD ◉")).await;
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "Le 13h");
    }

    #[test]
    fn indexe_chaque_display_name_pas_seulement_le_premier() {
        let now = now_s();
        let index = offline_service().parse_for_test(&format!(
            r#"<tv>
  <channel id="x.fr"><display-name>Premier Nom</display-name><display-name>Second Nom</display-name></channel>
  <programme start="{}" stop="{}" channel="x.fr"><title>T</title></programme>
</tv>"#,
            stamp(now),
            stamp(now + TimeDelta::hours(1))
        ));
        assert!(index.contains_key(&Svc::normalize_key(Some("Second Nom"))));
        // Les alias partagent la liste de la chaîne, sans copie.
        assert!(Arc::ptr_eq(
            &index[&Svc::normalize_key(Some("Second Nom"))],
            &index["xfr"]
        ));
    }

    // --- parseXmltvDate ---

    #[test]
    fn date_applique_le_decalage_horaire_annonce() {
        assert_eq!(
            Svc::parse_xmltv_date(Some("20260811200000 +0200")),
            Some(Utc.with_ymd_and_hms(2026, 8, 11, 18, 0, 0).unwrap())
        );
    }

    #[test]
    fn date_sans_decalage_traitee_comme_utc() {
        assert_eq!(
            Svc::parse_xmltv_date(Some("20260811200000")),
            Some(Utc.with_ymd_and_hms(2026, 8, 11, 20, 0, 0).unwrap())
        );
    }

    #[test]
    fn date_rejette_une_valeur_tronquee() {
        assert_eq!(Svc::parse_xmltv_date(Some("202608")), None);
        assert_eq!(Svc::parse_xmltv_date(None), None);
        assert_eq!(Svc::parse_xmltv_date(Some("2026O811200000")), None);
    }

    #[test]
    fn date_decalage_negatif_et_report_hors_bornes() {
        assert_eq!(
            Svc::parse_xmltv_date(Some("20260811200000 -0530")),
            Some(Utc.with_ymd_and_hms(2026, 8, 12, 1, 30, 0).unwrap())
        );
        // Comme `DateTime.parse` de Dart : le 32 août devient le 1er septembre.
        assert_eq!(
            Svc::parse_xmltv_date(Some("20260832000000")),
            Some(Utc.with_ymd_and_hms(2026, 9, 1, 0, 0, 0).unwrap())
        );
    }

    use chrono::TimeZone;

    // --- parse ---

    #[test]
    fn indexe_un_programme_en_cours_et_decode_son_titre() {
        let now = Utc::now();
        let index = offline_service().parse_for_test(&fixture(
            now - TimeDelta::minutes(10),
            now + TimeDelta::minutes(20),
        ));
        let programmes = index
            .get(&Svc::normalize_key(Some("France2.fr")))
            .expect("chaîne indexée");
        assert_eq!(programmes.len(), 1);
        assert_eq!(programmes[0].title, "Journal de 20h");
        assert_eq!(programmes[0].description, "L'info du soir");
    }

    #[test]
    fn rend_la_chaine_atteignable_par_son_nom_affiche() {
        let now = Utc::now();
        let index = offline_service().parse_for_test(&fixture(now, now + TimeDelta::minutes(20)));
        assert!(index.contains_key(&Svc::normalize_key(Some("FR - FRANCE 2"))));
    }

    #[test]
    fn ecarte_les_programmes_termines_hors_fenetre_de_retention() {
        let old = Utc::now() - TimeDelta::days(2);
        let index = offline_service().parse_for_test(&fixture(old, old + TimeDelta::minutes(30)));
        assert!(index.is_empty());
    }

    #[test]
    fn decode_entites_cdata_et_tolere_les_entites_inconnues() {
        let now = now_s();
        let index = offline_service().parse_for_test(&format!(
            r#"<tv><programme start="{}" stop="{}" channel="A&amp;B.fr"><title>Tom &amp; Jerry &nbsp;&#233;&#x41; AT&T</title><desc><![CDATA[<b>brut</b> &amp;]]></desc><sub-title/></programme></tv>"#,
            stamp(now),
            stamp(now + TimeDelta::hours(1))
        ));
        let programmes = index.get("abfr").expect("chaîne indexée");
        assert_eq!(programmes[0].title, "Tom & Jerry &nbsp;éA AT&T");
        assert_eq!(programmes[0].description, "<b>brut</b> &amp;");
    }

    #[test]
    fn programmes_tries_par_heure_de_debut() {
        let now = now_s();
        let index = offline_service().parse_for_test(&format!(
            r#"<tv><programme start="{}" stop="{}" channel="c"><title>B</title></programme><programme start="{}" stop="{}" channel="c"><title>A</title></programme></tv>"#,
            stamp(now + TimeDelta::hours(1)),
            stamp(now + TimeDelta::hours(2)),
            stamp(now),
            stamp(now + TimeDelta::hours(1)),
        ));
        let titles: Vec<_> = index["c"].iter().map(|p| p.title.as_str()).collect();
        assert_eq!(titles, ["A", "B"]);
    }

    #[test]
    fn to_json_au_format_dart() {
        let p = XmltvProgramme {
            title: "T".into(),
            description: "D".into(),
            start: Utc.with_ymd_and_hms(2026, 8, 11, 18, 0, 0).unwrap(),
            stop: Utc.with_ymd_and_hms(2026, 8, 11, 19, 0, 0).unwrap(),
            ..Default::default()
        };
        assert_eq!(
            p.to_json("42"),
            serde_json::json!({
                "title": "T",
                "description": "D",
                "start": "2026-08-11T18:00:00.000Z",
                "end": "2026-08-11T19:00:00.000Z",
                "channel_id": "42",
                "sub_title": null,
                "categories": [],
                "is_new": false,
                "is_live": false,
                "is_premiere": false,
                "previously_shown": false,
            })
        );
    }

    #[test]
    fn to_json_expose_les_metadonnees_xmltv() {
        let p = XmltvProgramme {
            title: "NBA".into(),
            sub_title: Some("Lakers - Celtics".into()),
            categories: vec!["Sport".into(), "Basket-ball".into()],
            is_live: true,
            is_new: true,
            ..Default::default()
        };
        let json = p.to_json("beinsports1.fr");
        assert_eq!(json["sub_title"], "Lakers - Celtics");
        assert_eq!(
            json["categories"],
            serde_json::json!(["Sport", "Basket-ball"])
        );
        assert_eq!(json["is_live"], true);
        assert_eq!(json["is_new"], true);
        assert_eq!(json["is_premiere"], false);
        assert_eq!(json["previously_shown"], false);
        assert_eq!(json["title"], "NBA");
    }

    // --- ensureFresh ---

    #[tokio::test]
    async fn ne_retelecharge_pas_tant_que_l_index_est_frais() {
        let now = Utc::now();
        let (svc, calls) = service_with(fixture(now, now + TimeDelta::minutes(30))).await;
        svc.ensure_fresh().await;
        svc.ensure_fresh().await;
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(svc.has_data());
    }

    #[tokio::test]
    async fn les_appels_concurrents_partagent_un_seul_telechargement() {
        let now = Utc::now();
        let (svc, calls) = service_with(fixture(now, now + TimeDelta::minutes(30))).await;
        futures::future::join_all((0..8).map(|_| svc.ensure_fresh())).await;
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(svc.has_data());
    }

    #[tokio::test]
    async fn espace_les_tentatives_apres_un_echec() {
        // Sans ce recul, une source morte était retéléchargée à chaque
        // consultation du guide : une requête sortante par chaîne affichée.
        let (base, calls) = serve(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                bytes::Bytes::from_static(b"nope"),
            )
        })
        .await;
        let svc = Svc::new(
            XmltvConfig::new(vec![format!("{base}/epg.xml")]),
            reqwest::Client::new(),
        );
        svc.ensure_fresh().await;
        svc.ensure_fresh().await;
        svc.ensure_fresh().await;
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(!svc.has_data());
    }

    #[tokio::test]
    async fn conserve_l_index_precedent_apres_un_echec() {
        let now = Utc::now();
        let fail = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let body = bytes::Bytes::from(fixture(now, now + TimeDelta::minutes(30)).into_bytes());
        let flag = Arc::clone(&fail);
        let (base, _) = serve(move |_| {
            if flag.load(Ordering::SeqCst) {
                (StatusCode::BAD_GATEWAY, bytes::Bytes::new())
            } else {
                (StatusCode::OK, body.clone())
            }
        })
        .await;
        let mut config = XmltvConfig::new(vec![format!("{base}/epg.xml")]);
        config.refresh_interval = Duration::ZERO;
        let svc = Svc::new(config, reqwest::Client::new());
        svc.ensure_fresh().await;
        let before = svc.channel_count();
        assert!(before > 0);
        fail.store(true, Ordering::SeqCst);
        svc.ensure_fresh().await;
        assert_eq!(svc.channel_count(), before);
    }

    #[tokio::test]
    async fn decompresse_un_dump_gzip_sans_en_tete() {
        let now = Utc::now();
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gz.write_all(fixture(now, now + TimeDelta::minutes(30)).as_bytes())
            .unwrap();
        let body = bytes::Bytes::from(gz.finish().unwrap());
        let (base, _) = serve(move |_| (StatusCode::OK, body.clone())).await;
        let svc = Svc::new(
            XmltvConfig::new(vec![format!("{base}/epg.xml.gz")]),
            reqwest::Client::new(),
        );
        let hits = svc.programmes_for(Some("France2.fr"), None).await;
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "Journal de 20h");
    }

    // --- réactivité du serveur ---

    #[tokio::test(flavor = "current_thread")]
    async fn l_indexation_ne_gele_pas_la_boucle_d_evenements() {
        // Décoder et parser un dump de plusieurs milliers de chaînes sur la
        // boucle asynchrone bloquait tout le reste pendant des secondes — y
        // compris le relais `turbo.ts` des flux en cours, d'où des coupures
        // systématiques au démarrage de la lecture. Runtime mono-thread : un
        // parsing hors `spawn_blocking` gèlerait le battement ci-dessous.
        let now = Utc::now();
        // ~7000 chaînes comme un vrai dump de panneau ; 3 programmes par
        // chaîne (au lieu de 30 côté Dart) pour garder le test rapide.
        let description =
            "Résumé du programme, avec assez de texte pour peser comme un vrai guide. ".repeat(4);
        let mut xml = String::from(r#"<?xml version="1.0"?><tv>"#);
        for c in 0..7000 {
            xml.push_str(&format!(
                r#"<channel id="Chaine.{c}.fr"><display-name>FR - CHAINE {c}</display-name></channel>"#
            ));
            for p in 0..3 {
                let start = now + TimeDelta::minutes(30 * p);
                let stop = start + TimeDelta::minutes(30);
                xml.push_str(&format!(
                    r#"<programme start="{}" stop="{}" channel="Chaine.{c}.fr"><title>Programme {p}</title><desc>{description}</desc></programme>"#,
                    stamp(start),
                    stamp(stop)
                ));
            }
        }
        xml.push_str("</tv>");
        let (svc, _) = service_with(xml).await;

        // Un « battement » toutes les 10 ms : le plus long écart observé est
        // le temps pendant lequel la boucle est restée bloquée.
        let beat = Arc::new(Mutex::new((Instant::now(), Duration::ZERO)));
        let heartbeat = {
            let beat = Arc::clone(&beat);
            tokio::spawn(async move {
                loop {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                    let mut b = beat.lock().unwrap();
                    let gap = b.0.elapsed();
                    b.1 = b.1.max(gap);
                    b.0 = Instant::now();
                }
            })
        };
        svc.ensure_fresh().await;
        heartbeat.abort();
        let (last, mut worst) = *beat.lock().unwrap();
        // Le dernier blocage n'est suivi d'aucun battement : le compter aussi.
        worst = worst.max(last.elapsed());

        assert!(
            svc.channel_count() >= 7000,
            "{} chaînes",
            svc.channel_count()
        );
        assert!(
            worst < Duration::from_millis(250),
            "boucle d'événements gelée {} ms",
            worst.as_millis()
        );
    }

    // --- horizon ---

    #[test]
    fn ecarte_les_programmes_au_dela_de_l_horizon() {
        // Un dump national couvre sept jours : tout garder ferait grossir
        // l'index pour un guide qui n'affiche que le programme courant.
        let mut config = XmltvConfig::new(vec![]);
        config.horizon = Duration::from_secs(48 * 3600);
        let svc = Svc::new(config, reqwest::Client::new());
        let far = Utc::now() + TimeDelta::days(5);
        assert!(
            svc.parse_for_test(&fixture(far, far + TimeDelta::hours(1)))
                .is_empty()
        );
    }

    #[test]
    fn horizon_lu_depuis_l_environnement_borne() {
        assert_eq!(horizon_hours(None), 48);
        assert_eq!(horizon_hours(Some("")), 48);
        assert_eq!(horizon_hours(Some("abc")), 48);
        assert_eq!(horizon_hours(Some("-5")), 48);
        assert_eq!(horizon_hours(Some(" 168 ")), 168);
        assert_eq!(horizon_hours(Some("1")), 12);
        assert_eq!(horizon_hours(Some("12")), 12);
        assert_eq!(horizon_hours(Some("336")), 336);
        assert_eq!(horizon_hours(Some("9999")), 336);
    }

    #[test]
    fn horizon_long_garde_les_matchs_a_une_semaine() {
        let mut config = XmltvConfig::new(vec![]);
        config.horizon = Duration::from_secs(horizon_hours(Some("168")) * 3600);
        let svc = Svc::new(config, reqwest::Client::new());
        let far = Utc::now() + TimeDelta::days(5);
        assert!(
            !svc.parse_for_test(&fixture(far, far + TimeDelta::hours(1)))
                .is_empty()
        );
    }

    // --- métadonnées XMLTV (direct / rediffusion) ---

    /// Deux matchs sur beIN : un direct balisé en éléments vides, une
    /// rediffusion balisée en paires ouvrante/fermante (`<new></new>`), avec
    /// attributs et texte là où certains dumps en mettent.
    fn metadata_fixture(start: DateTime<Utc>) -> String {
        let s = |h: i64| stamp(start + TimeDelta::hours(h));
        format!(
            r#"<?xml version="1.0" encoding="utf-8" ?>
<tv>
  <channel id="beINSports1.fr"><display-name>beIN SPORTS 1</display-name></channel>
  <programme start="{}" stop="{}" channel="beINSports1.fr">
    <title lang="fr">NBA</title>
    <sub-title lang="fr">Los Angeles Lakers - Boston Celtics</sub-title>
    <desc lang="fr">Saison régulière</desc>
    <category lang="fr">Sport</category>
    <category lang="en"> Basketball </category>
    <category lang="fr"/>
    <new/>
    <live/>
    <premiere/>
  </programme>
  <programme start="{}" stop="{}" channel="beINSports1.fr">
    <title lang="fr">NBA</title>
    <sub-title lang="fr"><![CDATA[Lakers &amp; Celtics]]></sub-title>
    <category lang="fr">Sport &amp; Basket</category>
    <new></new>
    <live></live>
    <premiere lang="fr">Première diffusion</premiere>
    <previously-shown start="20261017020000 +0000" channel="beINSports1.fr"></previously-shown>
  </programme>
  <programme start="{}" stop="{}" channel="beINSports1.fr">
    <title lang="fr">Rediffusion</title>
    <sub-title/>
    <previously-shown start="20261017020000 +0000"/>
  </programme>
</tv>
"#,
            s(0),
            s(2),
            s(2),
            s(4),
            s(4),
            s(6)
        )
    }

    fn bein_programmes(start: DateTime<Utc>) -> Vec<XmltvProgramme> {
        let index = offline_service().parse_for_test(&metadata_fixture(start));
        let key = Svc::normalize_key(Some("beINSports1.fr"));
        index.get(&key).expect("chaîne indexée").as_ref().clone()
    }

    #[test]
    fn lit_sous_titre_categories_et_indicateurs_en_elements_vides() {
        let start = now_s() + TimeDelta::hours(1);
        let programmes = bein_programmes(start);
        assert_eq!(programmes.len(), 3);
        let live = &programmes[0];
        assert_eq!(live.title, "NBA");
        assert_eq!(live.description, "Saison régulière");
        assert_eq!(
            live.sub_title.as_deref(),
            Some("Los Angeles Lakers - Boston Celtics")
        );
        // Catégorie vide écartée, espaces retirés, ordre conservé.
        assert_eq!(live.categories, vec!["Sport", "Basketball"]);
        assert!(live.is_new);
        assert!(live.is_live);
        assert!(live.is_premiere);
        assert!(!live.previously_shown);
    }

    #[test]
    fn lit_les_indicateurs_en_paires_ouvrante_fermante() {
        let start = now_s() + TimeDelta::hours(1);
        let programmes = bein_programmes(start);
        let paired = &programmes[1];
        assert_eq!(paired.sub_title.as_deref(), Some("Lakers &amp; Celtics"));
        assert_eq!(paired.categories, vec!["Sport & Basket"]);
        assert!(paired.is_new);
        assert!(paired.is_live);
        assert!(paired.is_premiere);
        assert!(paired.previously_shown);
        // Le texte de <premiere> ne déborde ni sur le titre ni sur la
        // description.
        assert_eq!(paired.title, "NBA");
        assert_eq!(paired.description, "");
    }

    #[test]
    fn indicateurs_remis_a_zero_entre_programmes() {
        let start = now_s() + TimeDelta::hours(1);
        let programmes = bein_programmes(start);
        let rerun = &programmes[2];
        assert_eq!(rerun.title, "Rediffusion");
        assert_eq!(rerun.sub_title, None);
        assert!(rerun.categories.is_empty());
        assert!(!rerun.is_new);
        assert!(!rerun.is_live);
        assert!(!rerun.is_premiere);
        assert!(rerun.previously_shown);
    }

    #[tokio::test]
    async fn decalage_plus_un_garde_les_metadonnees() {
        let start = now_s() + TimeDelta::hours(1);
        let (svc, _) = service_with(metadata_fixture(start)).await;
        let shifted = svc.programmes_for(None, Some("beIN SPORTS 1 +1")).await;
        assert_eq!(shifted.len(), 3);
        assert_eq!(shifted[0].start, start + TimeDelta::hours(1));
        assert!(shifted[0].is_live);
        assert_eq!(shifted[0].categories, vec!["Sport", "Basketball"]);
    }

    // --- journalisation (xmltv_epg_log_redaction_test.dart) ---

    /// URL du dump `xmltv.php` d'un panneau Xtream : les identifiants de
    /// l'abonné y figurent en clair, comme en production.
    const PANEL_QUERY: &str = "/xmltv.php?username=john&password=hunter2";

    fn capturing(url: String) -> (Svc, Arc<Mutex<Vec<String>>>) {
        let lines = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&lines);
        let svc = Svc::with_logger(
            XmltvConfig::new(vec![url]),
            reqwest::Client::new(),
            Arc::new(move |line: &str| sink.lock().unwrap().push(line.to_string())),
        );
        (svc, lines)
    }

    #[tokio::test]
    async fn masque_les_identifiants_de_l_url_quand_la_source_repond() {
        let (base, _) = serve(|_| {
            (
                StatusCode::OK,
                bytes::Bytes::from_static(br#"<?xml version="1.0"?><tv></tv>"#),
            )
        })
        .await;
        let (svc, lines) = capturing(format!("{base}{PANEL_QUERY}"));
        svc.ensure_fresh().await;
        let lines = lines.lock().unwrap().clone();
        let xmltv: Vec<_> = lines
            .iter()
            .filter(|l| l.starts_with("[XmltvEpg]"))
            .collect();
        assert!(!xmltv.is_empty());
        for line in &xmltv {
            assert!(!line.contains("john"), "{line}");
            assert!(!line.contains("hunter2"), "{line}");
        }
        assert!(
            lines
                .iter()
                .any(|l| l.contains("username=***&password=***")),
            "{lines:?}"
        );
    }

    #[tokio::test]
    async fn masque_les_identifiants_de_l_url_et_de_l_erreur_en_cas_d_echec() {
        // Les erreurs reqwest recopient l'URL demandée dans leur message :
        // c'est par là que les identifiants fuyaient aussi. Port fermé →
        // connexion refusée.
        let port = {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            listener.local_addr().unwrap().port()
        };
        let (svc, lines) = capturing(format!("http://127.0.0.1:{port}{PANEL_QUERY}"));
        svc.ensure_fresh().await;
        let lines = lines.lock().unwrap().clone();
        let failure = lines
            .iter()
            .find(|l| l.contains("échec"))
            .unwrap_or_else(|| panic!("aucune ligne d'échec journalisée : {lines:?}"));
        assert!(!failure.contains("john"), "{failure}");
        assert!(!failure.contains("hunter2"), "{failure}");
        // URL masquée en tête de ligne, et dans le texte de l'erreur.
        assert_eq!(
            failure.matches("username=***&password=***").count(),
            2,
            "{failure}"
        );
        assert!(!svc.has_data());
    }

    #[test]
    fn ligne_d_echec_masque_le_texte_de_l_exception() {
        let line = failure_line(
            &redact_url("http://panel.example:8080/xmltv.php?username=john&password=hunter2"),
            "ClientException: Connection refused, uri=http://panel.example:8080/xmltv.php?username=john&password=hunter2",
        );
        assert!(!line.contains("john"));
        assert!(!line.contains("hunter2"));
        assert!(line.contains("username=***&password=***"));
        assert!(line.contains("Connection refused"));
        assert!(line.starts_with(
            "[XmltvEpg] http://panel.example:8080/xmltv.php?username=***&password=*** : échec ("
        ));
    }

    #[test]
    fn duree_au_format_dart() {
        assert_eq!(dart_duration(Duration::from_secs(300)), "0:05:00.000000");
        assert_eq!(
            dart_duration(Duration::from_millis(3_723_500)),
            "1:02:03.500000"
        );
    }
}
