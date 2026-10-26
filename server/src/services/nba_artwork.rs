//! Vignettes des matchs NBA enregistrés, pour Plex et Jellyfin.
//!
//! POURQUOI : sans image, une bibliothèque Plex/Jellyfin affiche une capture
//! prise au hasard dans le fichier (souvent une pub ou un plateau télé) et
//! rien ne distingue un match d'un autre. On génère une vignette « Celtics @
//! Lakers » avec les logos des deux équipes, déposée à côté du fichier sous
//! les noms que les deux serveurs cherchent, plus un `.nfo` (titre, date,
//! résumé) et une copie intégrée au MKV.
//!
//! Formats déposés à côté de `X.mkv` :
//! - `X.jpg`, `X-poster.jpg` : affiche 2:3 (Plex « local assets », Jellyfin),
//!   lisible même recadrée en 16:9 (tuiles paysage des bibliothèques
//!   « Autres vidéos » de Plex) ;
//! - `X-thumb.jpg`, `X-fanart.jpg` : vignette 16:9 ;
//! - `X.nfo` : métadonnées au format Kodi « movie », lues par Jellyfin.

use crate::dart_time::DartDateTime;
use crate::models::NbaGame;
use crate::services::nba_teams::{self, Team};
use ab_glyph::{Font, FontVec, PxScale, ScaleFont};
use chrono::{DateTime, Datelike, Local, Timelike, Utc};
use image::{Rgba, RgbaImage, imageops};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

const THUMB: (u32, u32) = (1280, 720);
const POSTER: (u32, u32) = (1000, 1500);

/// Version de la mise en page : les annexes des enregistrements existants
/// sont redessinées quand elle change (voir `NbaAutoRecorder`).
pub const LAYOUT_VERSION: u32 = 2;

/// Police : `ARTWORK_FONT`, sinon DejaVu (image Docker), sinon Arial (Windows).
static FONT: LazyLock<Option<FontVec>> = LazyLock::new(|| {
    let candidates = [
        std::env::var("ARTWORK_FONT").unwrap_or_default(),
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf".into(),
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf".into(),
        "C:\\Windows\\Fonts\\arialbd.ttf".into(),
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf".into(),
    ];
    let font = candidates.iter().filter(|p| !p.is_empty()).find_map(|p| {
        std::fs::read(p)
            .ok()
            .and_then(|b| FontVec::try_from_vec(b).ok())
    });
    if font.is_none() {
        println!("[NBA] Aucune police trouvée (ARTWORK_FONT) : vignettes sans texte");
    }
    font
});

fn hex_color(hex: &str) -> [u8; 3] {
    let v = u32::from_str_radix(hex.trim_start_matches('#'), 16).unwrap_or(0x333333);
    [(v >> 16) as u8, (v >> 8) as u8, v as u8]
}

fn shade(c: [u8; 3], factor: f32) -> [u8; 3] {
    c.map(|v| (v as f32 * factor).clamp(0.0, 255.0) as u8)
}

fn blend(dst: &mut Rgba<u8>, src: [u8; 3], alpha: f32) {
    let a = alpha.clamp(0.0, 1.0);
    for (d, s) in dst.0.iter_mut().zip(src) {
        *d = (*d as f32 * (1.0 - a) + s as f32 * a) as u8;
    }
    dst.0[3] = 255;
}

/// Fond : couleur de l'équipe visiteuse vers celle de l'équipe à domicile,
/// assombries pour que logos et texte ressortent.
fn background(w: u32, h: u32, from: [u8; 3], to: [u8; 3], vertical: bool) -> RgbaImage {
    let (a, b) = (shade(from, 0.55), shade(to, 0.55));
    RgbaImage::from_fn(w, h, |x, y| {
        let t = if vertical {
            y as f32 / h as f32
        } else {
            // Diagonale douce.
            (x as f32 / w as f32 * 0.8 + y as f32 / h as f32 * 0.2).clamp(0.0, 1.0)
        };
        let t = ((t - 0.5) * 2.2 + 0.5).clamp(0.0, 1.0);
        let mix = |i: usize| (a[i] as f32 * (1.0 - t) + b[i] as f32 * t) as u8;
        Rgba([mix(0), mix(1), mix(2), 255])
    })
}

/// Largeur d'un texte à une taille donnée.
fn text_width(font: &FontVec, text: &str, px: f32) -> f32 {
    let scaled = font.as_scaled(PxScale::from(px));
    let mut width = 0.0;
    let mut prev = None;
    for c in text.chars() {
        let id = scaled.glyph_id(c);
        if let Some(p) = prev {
            width += scaled.kern(p, id);
        }
        width += scaled.h_advance(id);
        prev = Some(id);
    }
    width
}

/// Texte centré sur `cx`, ligne de base à `baseline`. Réduit la taille
/// jusqu'à tenir dans `max_width`.
fn draw_text(
    img: &mut RgbaImage,
    text: &str,
    mut px: f32,
    cx: f32,
    baseline: f32,
    max_width: f32,
    color: [u8; 3],
) {
    let Some(font) = FONT.as_ref() else { return };
    while px > 12.0 && text_width(font, text, px) > max_width {
        px -= 2.0;
    }
    let scaled = font.as_scaled(PxScale::from(px));
    let mut x = cx - text_width(font, text, px) / 2.0;
    let mut prev = None;
    for c in text.chars() {
        let id = scaled.glyph_id(c);
        if let Some(p) = prev {
            x += scaled.kern(p, id);
        }
        let glyph = id.with_scale_and_position(px, ab_glyph::point(x, baseline));
        x += scaled.h_advance(id);
        prev = Some(id);
        let Some(outline) = font.outline_glyph(glyph) else {
            continue;
        };
        let bounds = outline.px_bounds();
        outline.draw(|gx, gy, coverage| {
            let px_x = bounds.min.x as i64 + gx as i64;
            let px_y = bounds.min.y as i64 + gy as i64;
            if px_x >= 0 && px_y >= 0 && (px_x as u32) < img.width() && (px_y as u32) < img.height()
            {
                blend(img.get_pixel_mut(px_x as u32, px_y as u32), color, coverage);
            }
        });
    }
}

/// Logo centré dans un carré `size` autour de (cx, cy) ; à défaut de logo,
/// un disque aux couleurs de l'équipe avec son abréviation.
fn draw_logo(
    img: &mut RgbaImage,
    logo: Option<&RgbaImage>,
    team: &TeamArt,
    cx: i64,
    cy: i64,
    size: u32,
) {
    if let Some(logo) = logo {
        let ratio = (size as f32 / logo.width().max(logo.height()) as f32).min(4.0);
        let (w, h) = (
            (logo.width() as f32 * ratio) as u32,
            (logo.height() as f32 * ratio) as u32,
        );
        let resized = imageops::resize(logo, w.max(1), h.max(1), imageops::FilterType::Lanczos3);
        imageops::overlay(img, &resized, cx - w as i64 / 2, cy - h as i64 / 2);
        return;
    }
    let r = size as f32 / 2.0;
    let color = hex_color(&team.color);
    for y in (cy - r as i64).max(0)..(cy + r as i64).min(img.height() as i64) {
        for x in (cx - r as i64).max(0)..(cx + r as i64).min(img.width() as i64) {
            let d = (((x - cx) as f32).powi(2) + ((y - cy) as f32).powi(2)).sqrt();
            if d <= r {
                blend(
                    img.get_pixel_mut(x as u32, y as u32),
                    color,
                    (r - d).clamp(0.0, 1.0),
                );
            }
        }
    }
    draw_text(
        img,
        &team.abbr,
        size as f32 * 0.38,
        cx as f32,
        cy as f32 + size as f32 * 0.13,
        size as f32 * 0.85,
        [255, 255, 255],
    );
}

/// Bandeau sombre en bas de l'image.
fn banner(img: &mut RgbaImage, height: u32) {
    let (w, h) = img.dimensions();
    for y in h.saturating_sub(height)..h {
        for x in 0..w {
            blend(img.get_pixel_mut(x, y), [0, 0, 0], 0.62);
        }
    }
}

/// Ce qu'il faut savoir d'une équipe pour la dessiner.
#[derive(Clone, Debug)]
pub struct TeamArt {
    pub abbr: String,
    pub nickname: String,
    pub color: String,
}

impl TeamArt {
    pub fn from_abbr(abbr: &str, fallback_name: &str) -> Self {
        match nba_teams::by_abbr(abbr) {
            Some(Team {
                abbr,
                nickname,
                color,
                ..
            }) => Self {
                abbr: abbr.to_string(),
                nickname: nickname.to_string(),
                color: color.to_string(),
            },
            None => Self {
                abbr: abbr.to_uppercase(),
                nickname: fallback_name.to_string(),
                color: "333333".into(),
            },
        }
    }
}

/// Textes de la vignette.
pub struct ArtText {
    /// « Celtics @ Lakers »
    pub matchup: String,
    /// « mer. 22 oct. 2026 · 02:30 · beIN SPORTS 1 »
    pub details: String,
}

/// Vignette 16:9.
pub fn render_thumb(
    away: &TeamArt,
    home: &TeamArt,
    away_logo: Option<&RgbaImage>,
    home_logo: Option<&RgbaImage>,
    text: &ArtText,
) -> RgbaImage {
    let (w, h) = THUMB;
    let mut img = background(w, h, hex_color(&away.color), hex_color(&home.color), false);
    draw_text(
        &mut img,
        "NBA",
        44.0,
        w as f32 / 2.0,
        70.0,
        400.0,
        [255, 255, 255],
    );
    draw_logo(&mut img, away_logo, away, 320, 300, 340);
    draw_logo(&mut img, home_logo, home, 960, 300, 340);
    draw_text(
        &mut img,
        "@",
        110.0,
        w as f32 / 2.0,
        340.0,
        200.0,
        [255, 255, 255],
    );
    banner(&mut img, 170);
    draw_text(
        &mut img,
        &text.matchup,
        64.0,
        w as f32 / 2.0,
        625.0,
        1180.0,
        [255, 255, 255],
    );
    draw_text(
        &mut img,
        &text.details,
        34.0,
        w as f32 / 2.0,
        685.0,
        1180.0,
        [220, 220, 220],
    );
    img
}

/// Affiche 2:3.
///
/// POURQUOI : Plex affiche les « Autres vidéos » en tuiles 16:9 en
/// recadrant l'affiche au centre (bande y ≈ 470–1030). Logos et « @ » y
/// tiennent côte à côte ; titre et bandeau, hors de la bande, ne servent qu'à
/// l'affiche entière.
pub fn render_poster(
    away: &TeamArt,
    home: &TeamArt,
    away_logo: Option<&RgbaImage>,
    home_logo: Option<&RgbaImage>,
    text: &ArtText,
) -> RgbaImage {
    let (w, h) = POSTER;
    let mut img = background(w, h, hex_color(&away.color), hex_color(&home.color), true);
    draw_text(
        &mut img,
        "NBA",
        84.0,
        w as f32 / 2.0,
        330.0,
        600.0,
        [255, 255, 255],
    );
    draw_logo(&mut img, away_logo, away, 255, 735, 360);
    draw_logo(&mut img, home_logo, home, 745, 735, 360);
    draw_text(
        &mut img,
        "@",
        100.0,
        w as f32 / 2.0,
        770.0,
        120.0,
        [255, 255, 255],
    );
    banner(&mut img, 260);
    draw_text(
        &mut img,
        &text.matchup,
        72.0,
        w as f32 / 2.0,
        1340.0,
        920.0,
        [255, 255, 255],
    );
    draw_text(
        &mut img,
        &text.details,
        34.0,
        w as f32 / 2.0,
        1420.0,
        920.0,
        [220, 220, 220],
    );
    img
}

const JOURS: [&str; 7] = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."];
const MOIS: [&str; 12] = [
    "janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.",
    "déc.",
];

/// « mer. 22 oct. 2026 · 02:30 » en heure locale du serveur (TZ).
pub fn french_date(dt: DateTime<Utc>) -> String {
    let l = dt.with_timezone(&Local);
    format!(
        "{} {} {} {} · {:02}:{:02}",
        JOURS[l.weekday().num_days_from_monday() as usize],
        l.day(),
        MOIS[l.month0() as usize],
        l.year(),
        l.hour(),
        l.minute()
    )
}

fn texts(game: &NbaGame, away: &TeamArt, home: &TeamArt) -> ArtText {
    let tipoff = DartDateTime::parse(&game.tipoff_utc)
        .map(DartDateTime::to_utc)
        .unwrap_or_else(Utc::now);
    let mut details = french_date(tipoff);
    if let Some(ch) = &game.channel_name {
        details = format!("{details} · {ch}");
    }
    ArtText {
        matchup: format!("{} @ {}", away.nickname, home.nickname),
        details,
    }
}

/// Dossier des vignettes et logos en cache.
pub fn artwork_dir(recordings_dir: &Path) -> PathBuf {
    recordings_dir.join(".artwork")
}

/// Logo d'équipe : cache disque, sinon CDN ESPN.
async fn team_logo(client: &reqwest::Client, dir: &Path, abbr: &str) -> Option<RgbaImage> {
    let team = nba_teams::by_abbr(abbr)?;
    let path = dir.join("logos").join(format!("{}.png", team.abbr));
    let bytes = match tokio::fs::read(&path).await {
        Ok(b) => b,
        Err(_) => {
            let r = client
                .get(team.logo_url())
                .timeout(std::time::Duration::from_secs(20))
                .send()
                .await
                .ok()?;
            if !r.status().is_success() {
                return None;
            }
            let b = r.bytes().await.ok()?.to_vec();
            let _ = tokio::fs::create_dir_all(path.parent()?).await;
            let _ = tokio::fs::write(&path, &b).await;
            b
        }
    };
    image::load_from_memory(&bytes).ok().map(|i| i.to_rgba8())
}

fn save_jpeg(img: &RgbaImage, path: &Path) -> std::io::Result<()> {
    let rgb = image::DynamicImage::ImageRgba8(img.clone()).to_rgb8();
    let mut out = std::fs::File::create(path)?;
    let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 88);
    enc.encode_image(&rgb).map_err(std::io::Error::other)
}

/// Génère (ou régénère) vignette et affiche d'un match dans le cache.
/// Renvoie `(thumb, poster)`.
pub async fn ensure_artwork(
    client: &reqwest::Client,
    recordings_dir: &Path,
    game: &NbaGame,
) -> Option<(PathBuf, PathBuf)> {
    let dir = artwork_dir(recordings_dir);
    if let Err(e) = tokio::fs::create_dir_all(&dir).await {
        println!("[NBA] Dossier {} impossible à créer : {e}", dir.display());
        return None;
    }
    let away = TeamArt::from_abbr(&game.away_tri, &game.away);
    let home = TeamArt::from_abbr(&game.home_tri, &game.home);
    let away_logo = team_logo(client, &dir, &game.away_tri).await;
    let home_logo = team_logo(client, &dir, &game.home_tri).await;
    let text = texts(game, &away, &home);
    let safe_id: String = game
        .game_id
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    let thumb_path = dir.join(format!("{safe_id}-thumb.jpg"));
    let poster_path = dir.join(format!("{safe_id}-poster.jpg"));
    let (tp, pp) = (thumb_path.clone(), poster_path.clone());
    tokio::task::spawn_blocking(move || {
        save_jpeg(
            &render_thumb(&away, &home, away_logo.as_ref(), home_logo.as_ref(), &text),
            &tp,
        )?;
        save_jpeg(
            &render_poster(&away, &home, away_logo.as_ref(), home_logo.as_ref(), &text),
            &pp,
        )
    })
    .await
    .ok()?
    .map_err(|e| println!("[NBA] Vignette {} impossible : {e}", game.game_id))
    .ok()?;
    Some((thumb_path, poster_path))
}

/// Chemins des fichiers annexes de `X.mkv`.
pub fn sidecar_paths(video: &Path) -> Vec<PathBuf> {
    let stem = video.with_extension("");
    let s = stem.to_string_lossy();
    [
        "{}.jpg",
        "{}-poster.jpg",
        "{}-thumb.jpg",
        "{}-fanart.jpg",
        "{}.nfo",
    ]
    .iter()
    .map(|pattern| PathBuf::from(pattern.replace("{}", &s)))
    .collect()
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// `.nfo` Kodi « movie » (Jellyfin le lit nativement).
pub fn nfo(game: &NbaGame, title: &str) -> String {
    let tipoff = DartDateTime::parse(&game.tipoff_utc)
        .map(DartDateTime::to_utc)
        .unwrap_or_else(Utc::now);
    let local = tipoff.with_timezone(&Local);
    let channel = game
        .channel_name
        .clone()
        .unwrap_or_else(|| "beIN SPORTS".into());
    let plot = format!(
        "{} reçoit {} — diffusion en direct sur {}, {}.",
        game.home,
        game.away,
        channel,
        french_date(tipoff)
    );
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<movie>\n  <title>{}</title>\n  <sorttitle>{} {}</sorttitle>\n  <plot>{}</plot>\n  <premiered>{}</premiered>\n  <year>{}</year>\n  <genre>Basketball</genre>\n  <genre>NBA</genre>\n  <studio>{}</studio>\n  <tag>NBA</tag>\n  <tag>{}</tag>\n  <tag>{}</tag>\n  <uniqueid type=\"espn\" default=\"true\">{}</uniqueid>\n</movie>\n",
        xml_escape(title),
        local.format("%Y-%m-%d"),
        xml_escape(title),
        xml_escape(&plot),
        local.format("%Y-%m-%d"),
        local.year(),
        xml_escape(&channel),
        xml_escape(&game.home),
        xml_escape(&game.away),
        xml_escape(&game.game_id),
    )
}

/// Après un enregistrement réussi : dépose vignettes et `.nfo` à côté du
/// fichier, puis intègre la vignette au MKV (pièce jointe `cover.jpg`).
pub async fn finish_recording(
    client: &reqwest::Client,
    recordings_dir: &Path,
    game: &NbaGame,
    video: &Path,
    title: &str,
    ffmpeg: &str,
) {
    // Annexes incomplètes : dossier sans doute non inscriptible, le remux
    // échouerait aussi (et le rattrapage le relancerait à chaque passage).
    if let Some(thumb) = write_sidecars(client, recordings_dir, game, video, title).await
        && has_sidecars(video)
    {
        embed_cover(video, &thumb, title, ffmpeg).await;
    }
}

/// Les annexes de `video` ont-elles déjà été déposées ?
pub fn has_sidecars(video: &Path) -> bool {
    sidecar_paths(video).iter().all(|p| p.exists())
}

/// Dépose (ou redessine) vignettes et `.nfo` à côté du fichier, sans
/// toucher au MKV. Renvoie la vignette 16:9 générée.
pub async fn write_sidecars(
    client: &reqwest::Client,
    recordings_dir: &Path,
    game: &NbaGame,
    video: &Path,
    title: &str,
) -> Option<PathBuf> {
    let (thumb, poster) = ensure_artwork(client, recordings_dir, game).await?;
    let paths = sidecar_paths(video);
    let copies = [
        (&poster, &paths[0]),
        (&poster, &paths[1]),
        (&thumb, &paths[2]),
        (&thumb, &paths[3]),
    ];
    for (src, dst) in copies {
        if let Err(e) = tokio::fs::copy(src, dst).await {
            println!("[NBA] Copie de {} impossible : {e}", dst.display());
        }
    }
    if let Err(e) = tokio::fs::write(&paths[4], nfo(game, title)).await {
        println!("[NBA] Écriture de {} impossible : {e}", paths[4].display());
    }
    Some(thumb)
}

/// Remux sans réencodage avec la vignette en pièce jointe et le titre en
/// métadonnée. En cas d'échec, le fichier d'origine reste intact.
async fn embed_cover(video: &Path, cover: &Path, title: &str, ffmpeg: &str) {
    let tmp = video.with_extension("cover.mkv");
    let status = tokio::process::Command::new(ffmpeg)
        .args(["-hide_banner", "-nostats", "-loglevel", "error", "-y", "-i"])
        .arg(video)
        .args(["-map", "0", "-c", "copy", "-attach"])
        .arg(cover)
        .args([
            "-metadata:s:t",
            "mimetype=image/jpeg",
            "-metadata:s:t",
            "filename=cover.jpg",
            "-metadata",
        ])
        .arg(format!("title={title}"))
        .arg(&tmp)
        .stdin(std::process::Stdio::null())
        .status()
        .await;
    let ok =
        status.is_ok_and(|s| s.success()) && std::fs::metadata(&tmp).is_ok_and(|m| m.len() > 0);
    if ok {
        if let Err(e) = tokio::fs::rename(&tmp, video).await {
            println!("[NBA] Remplacement du fichier impossible : {e}");
            let _ = tokio::fs::remove_file(&tmp).await;
        }
    } else {
        println!("[NBA] Intégration de la vignette au MKV impossible : fichier conservé tel quel");
        let _ = tokio::fs::remove_file(&tmp).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn game() -> NbaGame {
        NbaGame {
            game_id: "401810026".into(),
            rule_id: "r".into(),
            home: "Los Angeles Lakers".into(),
            away: "Boston Celtics".into(),
            home_id: "13".into(),
            away_id: "2".into(),
            home_tri: "LAL".into(),
            away_tri: "BOS".into(),
            tipoff_utc: "2026-10-22T02:30:00.000Z".into(),
            status: "scheduled".into(),
            decision: "auto".into(),
            channel_id: Some("1".into()),
            channel_name: Some("beIN SPORTS 1".into()),
            epg_title: None,
            epg_start: None,
            epg_end: None,
            recording_id: None,
            confidence: None,
            conflict: false,
            updated_at: String::new(),
        }
    }

    #[test]
    fn dimensions_et_couleurs_sans_logo() {
        let away = TeamArt::from_abbr("BOS", "Boston Celtics");
        let home = TeamArt::from_abbr("LAL", "Los Angeles Lakers");
        let text = texts(&game(), &away, &home);
        assert_eq!(text.matchup, "Celtics @ Lakers");
        assert!(text.details.ends_with("· beIN SPORTS 1"));
        let thumb = render_thumb(&away, &home, None, None, &text);
        assert_eq!(thumb.dimensions(), THUMB);
        let poster = render_poster(&away, &home, None, None, &text);
        assert_eq!(poster.dimensions(), POSTER);
        // Le disque de repli prend la couleur de l'équipe (vert Celtics) :
        // canal vert dominant au bord du disque visiteur.
        let p = thumb.get_pixel(320, 300 - 150);
        assert!(p.0[1] > p.0[0] && p.0[1] > p.0[2], "{p:?}");
    }

    #[test]
    fn fichiers_annexes_plex_jellyfin() {
        let paths = sidecar_paths(Path::new("/rec/NBA - Celtics @ Lakers.mkv"));
        let names: Vec<String> = paths
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            [
                "NBA - Celtics @ Lakers.jpg",
                "NBA - Celtics @ Lakers-poster.jpg",
                "NBA - Celtics @ Lakers-thumb.jpg",
                "NBA - Celtics @ Lakers-fanart.jpg",
                "NBA - Celtics @ Lakers.nfo",
            ]
        );
    }

    #[test]
    fn nfo_echappe_et_complet() {
        let mut g = game();
        g.channel_name = Some("beIN <SPORTS> & co".into());
        let xml = nfo(&g, "NBA - Celtics @ Lakers");
        assert!(xml.contains("<title>NBA - Celtics @ Lakers</title>"));
        assert!(xml.contains("beIN &lt;SPORTS&gt; &amp; co"));
        assert!(xml.contains("<uniqueid type=\"espn\" default=\"true\">401810026</uniqueid>"));
        assert!(xml.contains("<genre>NBA</genre>"));
    }

    /// Aperçu réel (réseau) : `ARTWORK_PREVIEW_DIR=... cargo test apercu -- --ignored`.
    #[tokio::test]
    #[ignore]
    async fn apercu_avec_logos() {
        let dir = PathBuf::from(std::env::var("ARTWORK_PREVIEW_DIR").unwrap());
        let (thumb, poster) = ensure_artwork(&reqwest::Client::new(), &dir, &game())
            .await
            .unwrap();
        assert!(thumb.exists() && poster.exists());
    }

    #[test]
    fn equipe_inconnue() {
        let t = TeamArt::from_abbr("wld", "World Team");
        assert_eq!(t.abbr, "WLD");
        assert_eq!(t.nickname, "World Team");
    }
}
