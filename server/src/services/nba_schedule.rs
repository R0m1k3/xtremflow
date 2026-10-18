//! Calendrier NBA (API publique ESPN « scoreboard »).
//!
//! POURQUOI : l'EPG ne voit qu'environ 48 h devant. Le calendrier officiel
//! donne les matchs des semaines à l'avance, avec leur coup d'envoi exact :
//! c'est lui qui permet d'afficher les futurs enregistrements et de
//! distinguer la diffusion en direct (qui colle au coup d'envoi) des
//! rediffusions. Le CDN de nba.com refuse les requêtes serveur (403), ESPN
//! les accepte et fournit en plus abréviations, couleurs et logos.

use crate::models::ScheduledGame;
use crate::services::nba_teams;
use chrono::{DateTime, Duration, NaiveDate, Utc};
use serde_json::Value;

const SCOREBOARD: &str = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard";

/// Date ESPN (`2025-11-06T00:00Z`, sans secondes) ou RFC 3339 complète.
fn parse_espn_date(raw: &str) -> Option<DateTime<Utc>> {
    if let Ok(dt) = DateTime::parse_from_rfc3339(raw) {
        return Some(dt.with_timezone(&Utc));
    }
    chrono::NaiveDateTime::parse_from_str(raw, "%Y-%m-%dT%H:%MZ")
        .ok()
        .map(|n| n.and_utc())
}

/// Extrait les matchs d'une réponse « scoreboard ». Les événements
/// incomplets (équipe inconnue, date illisible) sont ignorés.
pub fn parse_scoreboard(json: &Value) -> Vec<ScheduledGame> {
    let Some(events) = json.get("events").and_then(Value::as_array) else {
        return Vec::new();
    };
    events
        .iter()
        .filter_map(|event| {
            let game_id = event.get("id")?.as_str()?.to_string();
            let date = parse_espn_date(event.get("date")?.as_str()?)?;
            let competitors = event
                .get("competitions")?
                .get(0)?
                .get("competitors")?
                .as_array()?;
            let side = |which: &str| {
                competitors
                    .iter()
                    .find(|c| c.get("homeAway").and_then(Value::as_str) == Some(which))
                    .and_then(|c| c.get("team"))
            };
            let (home, away) = (side("home")?, side("away")?);
            let text = |team: &Value, key: &str| {
                team.get(key)
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
            let home_abbr = text(home, "abbreviation");
            let away_abbr = text(away, "abbreviation");
            // Normalise vers la table locale (noms complets cohérents) ;
            // une abréviation inconnue (match d'exhibition) garde le texte ESPN.
            let name = |team: &Value, abbr: &str| {
                nba_teams::by_abbr(abbr)
                    .map(|t| t.full_name())
                    .unwrap_or_else(|| text(team, "displayName"))
            };
            Some(ScheduledGame {
                game_id,
                home: name(home, &home_abbr),
                away: name(away, &away_abbr),
                home_id: text(home, "id"),
                away_id: text(away, "id"),
                home_tri: home_abbr,
                away_tri: away_abbr,
                tipoff_utc: date,
            })
        })
        .collect()
}

/// Matchs des journées ESPN `[first, first + days)`. Une journée en échec
/// est sautée : mieux vaut un calendrier partiel que rien.
pub async fn fetch_days(
    client: &reqwest::Client,
    first: NaiveDate,
    days: i64,
) -> Vec<ScheduledGame> {
    let mut games = Vec::new();
    for offset in 0..days {
        let day = first + Duration::days(offset);
        let url = format!("{SCOREBOARD}?dates={}", day.format("%Y%m%d"));
        let response = client
            .get(&url)
            .header("User-Agent", "Mozilla/5.0 (XtremFlow)")
            .timeout(std::time::Duration::from_secs(20))
            .send()
            .await;
        match response {
            Ok(r) if r.status().is_success() => match r
                .bytes()
                .await
                .map_err(|e| e.to_string())
                .and_then(|b| serde_json::from_slice::<Value>(&b).map_err(|e| e.to_string()))
            {
                Ok(json) => games.extend(parse_scoreboard(&json)),
                Err(e) => println!("[NBA] Calendrier {day} illisible: {e}"),
            },
            Ok(r) => println!("[NBA] Calendrier {day}: HTTP {}", r.status()),
            Err(e) => println!("[NBA] Calendrier {day} injoignable: {e}"),
        }
    }
    games.sort_by_key(|g| g.tipoff_utc);
    games.dedup_by(|a, b| a.game_id == b.game_id);
    games
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
      "events": [
        {
          "id": "401810026",
          "date": "2025-11-06T00:00Z",
          "name": "Philadelphia 76ers at Cleveland Cavaliers",
          "competitions": [{
            "competitors": [
              {"homeAway": "home", "team": {"id": "5", "abbreviation": "CLE", "displayName": "Cleveland Cavaliers"}},
              {"homeAway": "away", "team": {"id": "20", "abbreviation": "PHI", "displayName": "Philadelphia 76ers"}}
            ]
          }]
        },
        {
          "id": "401810027",
          "date": "2025-11-06T03:00Z",
          "competitions": [{
            "competitors": [
              {"homeAway": "home", "team": {"id": "9", "abbreviation": "GS", "displayName": "Golden State Warriors"}},
              {"homeAway": "away", "team": {"id": "99", "abbreviation": "WLD", "displayName": "World Team"}}
            ]
          }]
        },
        {"id": "broken", "date": "n/a", "competitions": []}
      ]
    }"#;

    #[test]
    fn lit_le_scoreboard_espn() {
        let json: Value = serde_json::from_str(SAMPLE).unwrap();
        let games = parse_scoreboard(&json);
        assert_eq!(games.len(), 2);
        let g = &games[0];
        assert_eq!(g.game_id, "401810026");
        assert_eq!(g.home, "Cleveland Cavaliers");
        assert_eq!(g.away, "Philadelphia 76ers");
        assert_eq!((g.home_tri.as_str(), g.away_tri.as_str()), ("CLE", "PHI"));
        assert_eq!(g.tipoff_utc.to_rfc3339(), "2025-11-06T00:00:00+00:00");
        // Équipe inconnue de la table locale : nom ESPN conservé.
        assert_eq!(games[1].away, "World Team");
    }

    #[test]
    fn dates_espn() {
        assert!(parse_espn_date("2026-10-21T01:30Z").is_some());
        assert!(parse_espn_date("2026-10-21T01:30:00Z").is_some());
        assert!(parse_espn_date("demain").is_none());
    }
}
