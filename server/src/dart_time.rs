//! Dates au format de l'ancien serveur Dart.
//!
//! POURQUOI : la base SQLite de production a été écrite par le serveur Dart.
//! Ses colonnes de dates contiennent la sortie de `DateTime.toIso8601String()`
//! (heure locale sans suffixe pour les sessions et les horodatages de
//! création, UTC avec `Z` pour les fenêtres d'enregistrement), et certaines
//! requêtes les comparent comme des chaînes (`expires_at < ?`,
//! `start_time BETWEEN ? AND ?`). Reproduire exactement ce format garde la
//! base existante lisible et les comparaisons justes, sans migration.

use chrono::{
    DateTime, Datelike, Local, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Timelike, Utc,
};
use regex::Regex;
use std::sync::LazyLock;

/// Équivalent d'un `DateTime` Dart : un instant « mural » et un drapeau UTC.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DartDateTime {
    pub naive: NaiveDateTime,
    pub utc: bool,
}

/// Grammaire de `DateTime.parse` (SDK Dart).
static PARSE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(concat!(
        r"^([+-]?\d{4,6})-?(\d\d)-?(\d\d)",
        r"(?:[ T](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?",
        r"( ?[zZ]| ?([-+])(\d\d)(?::?(\d\d))?)?)?$",
    ))
    .unwrap()
});

fn truncate_micros(naive: NaiveDateTime) -> NaiveDateTime {
    let micros = naive.and_utc().timestamp_subsec_micros();
    naive.with_nanosecond(micros * 1000).unwrap_or(naive)
}

impl DartDateTime {
    /// `DateTime.now()` : heure locale, précision microseconde.
    pub fn now_local() -> Self {
        Self {
            naive: truncate_micros(Local::now().naive_local()),
            utc: false,
        }
    }

    pub fn from_utc(dt: DateTime<Utc>) -> Self {
        Self {
            naive: truncate_micros(dt.naive_utc()),
            utc: true,
        }
    }

    /// Instant local (`DateTime.toLocal()`).
    pub fn local_from_utc(dt: DateTime<Utc>) -> Self {
        Self {
            naive: truncate_micros(dt.with_timezone(&Local).naive_local()),
            utc: false,
        }
    }

    /// `DateTime.tryParse`.
    pub fn parse(raw: &str) -> Option<Self> {
        let caps = PARSE_RE.captures(raw)?;
        let num = |i: usize| -> Option<i64> { caps.get(i).map(|m| m.as_str().parse().ok())? };
        let year = num(1)? as i32;
        let month = num(2)? as u32;
        let day = num(3)? as u32;
        let hour = num(4).unwrap_or(0) as u32;
        let minute = num(5).unwrap_or(0) as u32;
        let second = num(6).unwrap_or(0) as u32;
        let micros = caps
            .get(7)
            .map(|m| {
                let digits = m.as_str().as_bytes();
                let mut value: u32 = 0;
                for i in 0..6 {
                    value *= 10;
                    if i < digits.len() {
                        value += (digits[i] - b'0') as u32;
                    }
                }
                value
            })
            .unwrap_or(0);

        let date = NaiveDate::from_ymd_opt(year, month, day)?;
        // Dart normalise les débordements (24:00, :60) ; on les ajoute en durée.
        let base = NaiveTime::from_hms_micro_opt(0, 0, 0, micros)?;
        let mut naive = date.and_time(base)
            + chrono::Duration::hours(hour as i64)
            + chrono::Duration::minutes(minute as i64)
            + chrono::Duration::seconds(second as i64);

        let utc = caps.get(8).is_some();
        if let Some(sign) = caps.get(9) {
            let hours = num(10).unwrap_or(0);
            let minutes = num(11).unwrap_or(0);
            let offset = chrono::Duration::minutes(hours * 60 + minutes);
            naive = if sign.as_str() == "-" {
                naive + offset
            } else {
                naive - offset
            };
        }
        Some(Self { naive, utc })
    }

    /// `DateTime.toIso8601String()`.
    pub fn to_iso(self) -> String {
        let n = &self.naive;
        let year = n.year();
        let year_str = if (0..=9999).contains(&year) {
            format!("{year:04}")
        } else if year < 0 {
            format!("-{:06}", -year)
        } else {
            format!("+{year:06}")
        };
        let micros_total = n.nanosecond() / 1000;
        let ms = micros_total / 1000;
        let us = micros_total % 1000;
        let mut out = format!(
            "{year_str}-{:02}-{:02}T{:02}:{:02}:{:02}.{ms:03}",
            n.month(),
            n.day(),
            n.hour(),
            n.minute(),
            n.second()
        );
        if us != 0 {
            out.push_str(&format!("{us:03}"));
        }
        if self.utc {
            out.push('Z');
        }
        out
    }

    /// Instant absolu (`DateTime.toUtc()`).
    pub fn to_utc(self) -> DateTime<Utc> {
        if self.utc {
            return self.naive.and_utc();
        }
        match Local.from_local_datetime(&self.naive) {
            chrono::LocalResult::Single(dt) => dt.with_timezone(&Utc),
            chrono::LocalResult::Ambiguous(dt, _) => dt.with_timezone(&Utc),
            // Heure qui n'existe pas (passage à l'heure d'été) : décaler d'une
            // heure, comme le fait la libc.
            chrono::LocalResult::None => Local
                .from_local_datetime(&(self.naive + chrono::Duration::hours(1)))
                .earliest()
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(|| self.naive.and_utc()),
        }
    }

    /// `DateTime.toUtc()` gardé au format Dart.
    pub fn as_utc(self) -> Self {
        Self::from_utc(self.to_utc())
    }

    pub fn add(self, d: chrono::Duration) -> Self {
        if self.utc {
            Self::from_utc(self.to_utc() + d)
        } else {
            Self::local_from_utc(self.to_utc() + d)
        }
    }
}

/// `DateTime.now().toIso8601String()` (heure locale).
pub fn now_local_iso() -> String {
    DartDateTime::now_local().to_iso()
}

/// Instant UTC au format Dart (`...Z`).
pub fn utc_iso(dt: DateTime<Utc>) -> String {
    DartDateTime::from_utc(dt).to_iso()
}

/// `'${DateTime.now()}'` : format de `DateTime.toString()` (journaux).
pub fn now_display() -> String {
    display_naive(DartDateTime::now_local().naive)
}

/// `'${instant.toLocal()}'` (journaux).
pub fn display_local(dt: DateTime<Utc>) -> String {
    display_naive(DartDateTime::local_from_utc(dt).naive)
}

fn display_naive(n: NaiveDateTime) -> String {
    let micros_total = n.nanosecond() / 1000;
    let ms = micros_total / 1000;
    let us = micros_total % 1000;
    let mut out = format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{ms:03}",
        n.year(),
        n.month(),
        n.day(),
        n.hour(),
        n.minute(),
        n.second()
    );
    if us != 0 {
        out.push_str(&format!("{us:03}"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formate_comme_dart() {
        let d = DartDateTime::parse("2026-08-11T18:00:00Z").unwrap();
        assert!(d.utc);
        assert_eq!(d.to_iso(), "2026-08-11T18:00:00.000Z");

        let d = DartDateTime::parse("2026-08-11T18:00:00.123456").unwrap();
        assert!(!d.utc);
        assert_eq!(d.to_iso(), "2026-08-11T18:00:00.123456");

        let d = DartDateTime::parse("2026-08-11T18:00:00.120").unwrap();
        assert_eq!(d.to_iso(), "2026-08-11T18:00:00.120");
    }

    #[test]
    fn lit_le_format_sqlite() {
        let d = DartDateTime::parse("2026-10-12 12:03:22").unwrap();
        assert!(!d.utc);
        assert_eq!(d.to_iso(), "2026-10-12T12:03:22.000");
    }

    #[test]
    fn applique_les_decalages() {
        let d = DartDateTime::parse("2026-08-11T20:00:00+02:00").unwrap();
        assert!(d.utc);
        assert_eq!(d.to_iso(), "2026-08-11T18:00:00.000Z");
        let d = DartDateTime::parse("2026-08-11T20:00:00-0130").unwrap();
        assert_eq!(d.to_iso(), "2026-08-11T21:30:00.000Z");
    }

    #[test]
    fn rejette_les_valeurs_invalides() {
        assert!(DartDateTime::parse("").is_none());
        assert!(DartDateTime::parse("abc").is_none());
        assert!(DartDateTime::parse("2026-13-01").is_none());
    }
}
