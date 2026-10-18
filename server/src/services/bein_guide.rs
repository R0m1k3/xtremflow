//! Programme officiel des chaînes beIN Sports France (API du site
//! beinsports.com, `api/opta`).
//!
//! POURQUOI : le calendrier NBA liste tous les matchs, mais beIN n'en
//! diffuse qu'une partie, et l'EPG du panneau IPTV ne voit qu'environ 48 h
//! devant. Le guide beIN couvre ~8 jours, nomme la chaîne exacte et indique
//! pour chaque diffusion si elle est en direct (`live`) ou une rediffusion
//! (`replay`, attribut « Rediffusion »).

use crate::services::nba_teams::normalize;
use chrono::{DateTime, Duration, Utc};
use serde_json::Value;

const API: &str = "https://www.beinsports.com/api/opta";

/// Une diffusion du guide beIN.
#[derive(Clone, Debug, PartialEq)]
pub struct BeinBroadcast {
    /// Nom de la chaîne dans le guide (« beIN SPORTS 1 », « beIN SPORTS MAX 4 »).
    pub channel: String,
    pub title: String,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    /// Diffusion en direct selon beIN.
    pub live: bool,
}

fn date(v: &Value, key: &str) -> Option<DateTime<Utc>> {
    v.get(key)
        .and_then(Value::as_str)
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&Utc))
}

/// Réponse `tv-event` → diffusions. Une diffusion est « en direct »
/// seulement si beIN le dit et qu'elle n'est marquée ni rediffusion ni
/// replay.
pub fn parse_events(json: &Value) -> Vec<BeinBroadcast> {
    let Some(rows) = json.get("rows").and_then(Value::as_array) else {
        return Vec::new();
    };
    rows.iter()
        .filter_map(|r| {
            let channel = r
                .pointer("/channel/name")
                .or_else(|| r.pointer("/channel/data/name"))
                .and_then(Value::as_str)?
                .to_string();
            let rerun_attr = r
                .pointer("/data/airingAttributes")
                .and_then(Value::as_array)
                .is_some_and(|a| {
                    a.iter().any(|x| {
                        x.get("name")
                            .and_then(Value::as_str)
                            .is_some_and(|n| normalize(n).contains("rediffusion"))
                    })
                });
            let flag = |k: &str| r.get(k).and_then(Value::as_bool).unwrap_or(false);
            Some(BeinBroadcast {
                channel,
                title: r.get("title").and_then(Value::as_str)?.to_string(),
                start: date(r, "startDate")?,
                end: date(r, "endDate")?,
                live: flag("live") && !flag("replay") && !rerun_attr,
            })
        })
        .collect()
}

async fn get_json(client: &reqwest::Client, url: &str) -> Result<Value, String> {
    let r = client
        .get(url)
        .header("User-Agent", "Mozilla/5.0 (XtremFlow)")
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !r.status().is_success() {
        return Err(format!("HTTP {}", r.status()));
    }
    let body = r.bytes().await.map_err(|e| e.to_string())?;
    tokio::task::spawn_blocking(move || serde_json::from_slice::<Value>(&body))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

/// Diffusions NBA des `days` prochains jours sur toutes les beIN France.
/// `None` si le guide est injoignable (l'appelant se rabat sur l'EPG IPTV).
pub async fn fetch_nba(client: &reqwest::Client, days: i64) -> Option<Vec<BeinBroadcast>> {
    let channels = match get_json(client, &format!("{API}/tv-channel?region=fr-fr")).await {
        Ok(v) => v,
        Err(e) => {
            println!("[beIN] Chaînes indisponibles : {e}");
            return None;
        }
    };
    let ids: Vec<String> = channels
        .get("rows")
        .and_then(Value::as_array)?
        .iter()
        .filter_map(|c| c.get("id").and_then(Value::as_str).map(str::to_string))
        .collect();
    if ids.is_empty() {
        return None;
    }
    let now = Utc::now();
    let fmt = |d: DateTime<Utc>| d.format("%Y-%m-%dT%H:%M:%S.000Z").to_string();
    // Sérialiseur dans son propre bloc : il n'est pas `Send` et ne doit pas
    // vivre au-delà d'un `await`.
    let query = {
        let mut q = url::form_urlencoded::Serializer::new(String::new());
        q.append_pair("searchKey", "NBA")
            .append_pair("startBefore", &fmt(now + Duration::days(days)))
            .append_pair("endAfter", &fmt(now - Duration::hours(6)))
            .append_pair("limit", "3000");
        for id in &ids {
            q.append_pair("channelIds", id);
        }
        q.finish()
    };
    match get_json(client, &format!("{API}/tv-event?{query}")).await {
        Ok(v) => Some(parse_events(&v)),
        Err(e) => {
            println!("[beIN] Programme indisponible : {e}");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{"count": 4, "rows": [
      {"title": "Basket-ball : NBA - Detroit Pistons / Boston Celtics",
       "startDate": "2026-10-20T19:00:00.000Z", "endDate": "2026-10-20T21:45:00.000Z",
       "live": true, "replay": false, "channel": {"name": "beIN SPORTS 1"},
       "data": {"airingAttributes": [{"id": 48, "name": "Inédit crypté"}]}},
      {"title": "Basket-ball : NBA - Detroit Pistons / Boston Celtics",
       "startDate": "2026-10-21T07:15:00.000Z", "endDate": "2026-10-21T09:00:00.000Z",
       "live": false, "replay": true, "channel": {"name": "beIN SPORTS 1"},
       "data": {"airingAttributes": [{"id": 12, "name": "Rediffusion"}]}},
      {"title": "Basket-ball : NBA - Charlotte Hornets / Miami Heat",
       "startDate": "2026-10-25T20:00:00.000Z", "endDate": "2026-10-25T22:00:00.000Z",
       "live": true, "replay": false, "channel": {"name": "beIN SPORTS 3"},
       "data": {"airingAttributes": [{"id": 12, "name": "Rediffusion"}]}},
      {"title": "sans chaîne", "startDate": "2026-10-25T20:00:00.000Z",
       "endDate": "2026-10-25T22:00:00.000Z", "live": true}
    ]}"#;

    #[test]
    fn lit_le_guide_bein() {
        let v: Value = serde_json::from_str(SAMPLE).unwrap();
        let b = parse_events(&v);
        assert_eq!(b.len(), 3);
        assert_eq!(b[0].channel, "beIN SPORTS 1");
        assert!(b[0].live);
        assert_eq!(b[0].start.to_rfc3339(), "2026-10-20T19:00:00+00:00");
        // Rediffusion explicite.
        assert!(!b[1].live);
        // « live » contredit par l'attribut Rediffusion : pas en direct.
        assert!(!b[2].live);
    }
}
