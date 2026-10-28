//! Repérage des coupures pub des enregistrements (Comskip), pour Jellyfin.
//!
//! POURQUOI : Jellyfin propose de passer une pub quand l'élément porte un
//! « segment » de type Commercial. Le plugin officiel Chapter Segments
//! Provider fabrique ces segments à partir des chapitres du MKV : on y
//! inscrit donc chaque coupure détectée comme un chapitre « Commercial »,
//! le reste du programme en chapitres « Programme ». Un `X.edl` (format
//! Kodi, type 3 = coupure pub) est déposé à côté du fichier ; il sert aussi
//! de témoin « déjà analysé » pour le rattrapage au démarrage.
//!
//! La détection tourne après la clôture de l'enregistrement, une à la fois
//! et en priorité basse : Comskip décode toute la vidéo (de l'ordre d'un
//! quart d'heure pour un match en HD), le fichier reste lisible pendant ce
//! temps et n'est remplacé qu'une fois la version chapitrée complète.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{LazyLock, Mutex};
use std::time::Duration;
use tokio::sync::Semaphore;

/// Titre des chapitres de pub, celui que le plugin de Jellyfin reconnaît.
pub const COMMERCIAL_CHAPTER: &str = "Commercial";
const PROGRAMME_CHAPTER: &str = "Programme";

/// Au-delà, Comskip est jugé bloqué (un match de 4 h en prend moins d'une).
const COMSKIP_TIMEOUT: Duration = Duration::from_secs(6 * 3600);

/// Réglages par défaut : ceux de Comskip, sorties réduites à l'EDL.
/// `COMSKIP_INI` permet de fournir un fichier ajusté aux chaînes suivies.
const DEFAULT_INI: &str = "\
detect_method=43
verbose=0
thread_count=2
live_tv=0
output_default=0
output_edl=1
edl_skip_field=3
delete_logo_file=1
";

/// Fichiers en file d'attente ou en cours d'analyse.
static QUEUED: LazyLock<Mutex<HashSet<PathBuf>>> = LazyLock::new(|| Mutex::new(HashSet::new()));
/// Une seule analyse à la fois : Comskip occupe un cœur entier.
static SLOT: Semaphore = Semaphore::const_new(1);

/// Coupure pub, en secondes depuis le début du fichier.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Break {
    pub start: f64,
    pub end: f64,
}

/// `COMMERCIAL_DETECTION=false` coupe la détection (activée par défaut).
fn enabled() -> bool {
    let value = std::env::var("COMMERCIAL_DETECTION").unwrap_or_default();
    !matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "false" | "0" | "no" | "off"
    )
}

/// Binaire Comskip : `COMSKIP_PATH`, celui de l'image Docker, sinon le PATH.
fn comskip_path() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("COMSKIP_PATH")
        && !path.is_empty()
    {
        return Some(PathBuf::from(path));
    }
    let bundled = Path::new("/usr/local/bin/comskip");
    if cfg!(target_os = "linux") && bundled.exists() {
        return Some(bundled.to_path_buf());
    }
    let names: &[&str] = if cfg!(windows) {
        &["comskip.exe"]
    } else {
        &["comskip"]
    };
    std::env::split_paths(&std::env::var_os("PATH")?)
        .flat_map(|dir| names.iter().map(move |n| dir.join(n)))
        .find(|p| p.is_file())
}

/// Comskip utilisable, ou `None` (détection coupée ou binaire absent).
fn detector() -> Option<PathBuf> {
    if enabled() { comskip_path() } else { None }
}

/// Ligne de démarrage du serveur : état de la détection.
pub fn status_line() -> String {
    if !enabled() {
        return "[Pubs] Détection des pubs désactivée (COMMERCIAL_DETECTION)".to_string();
    }
    match comskip_path() {
        Some(path) => format!("[Pubs] Détection des pubs active ({})", path.display()),
        None => "[Pubs] Comskip introuvable : détection des pubs inactive".to_string(),
    }
}

/// Liste des coupures déposée à côté de `video`.
pub fn edl_path(video: &Path) -> PathBuf {
    video.with_extension("edl")
}

/// Fichiers de travail du remux (copie chapitrée, chapitres FFmpeg), cachés
/// pour que Jellyfin et Plex n'en fassent pas un nouvel élément.
pub fn temp_paths(video: &Path) -> [PathBuf; 2] {
    let hidden = |ext: &str| {
        let name = video.with_extension(ext);
        let name = name.file_name().unwrap_or_default().to_string_lossy();
        video.with_file_name(format!(".{name}"))
    };
    [hidden("chapters.mkv"), hidden("chapters.txt")]
}

/// L'enregistrement attend-il encore son analyse ?
pub fn needs_detection(video: &Path) -> bool {
    detector().is_some()
        && std::fs::metadata(video).is_ok_and(|m| m.is_file() && m.len() > 0)
        && !edl_path(video).exists()
}

/// Met `video` en file d'analyse (sans effet si déjà en file ou si la
/// détection est inactive).
pub fn schedule(video: &Path, ffmpeg: String) {
    let Some(comskip) = detector() else {
        return;
    };
    let video = video.to_path_buf();
    if !QUEUED.lock().unwrap().insert(video.clone()) {
        return;
    }
    tokio::spawn(async move {
        let _slot = SLOT.acquire().await;
        process(&video, &comskip, &ffmpeg).await;
        QUEUED.lock().unwrap().remove(&video);
    });
}

async fn process(video: &Path, comskip: &Path, ffmpeg: &str) {
    // Supprimé pendant l'attente (rotation disque, suppression manuelle).
    if !video.exists() {
        return;
    }
    let name = video
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    println!("[Pubs] Analyse de « {name} »…");
    let breaks = match detect(video, comskip).await {
        Ok(breaks) => breaks,
        Err(e) => {
            // Pas d'EDL : nouvel essai au prochain démarrage du serveur.
            println!("[Pubs] Analyse impossible pour « {name} » : {e}");
            return;
        }
    };
    let duration = crate::util::media_probe::duration(&video.to_string_lossy()).await;
    let breaks = normalize(breaks, duration);
    if !breaks.is_empty() && is_mkv(video) {
        let chapters = ffmetadata(&breaks, duration);
        if let Err(e) = embed_chapters(video, &chapters, ffmpeg).await {
            // Pas d'EDL non plus : nouvel essai au prochain démarrage.
            println!("[Pubs] Chapitres non ajoutés à « {name} » : {e}");
            return;
        }
    }
    if !video.exists() {
        return;
    }
    if let Err(e) = tokio::fs::write(edl_path(video), edl(&breaks)).await {
        println!("[Pubs] Écriture de l'EDL impossible pour « {name} » : {e}");
        return;
    }
    let total: f64 = breaks.iter().map(|b| b.end - b.start).sum();
    println!(
        "[Pubs] « {name} » : {} coupure(s), {} min au total",
        breaks.len(),
        (total / 60.0).round()
    );
}

fn is_mkv(video: &Path) -> bool {
    video
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("mkv"))
}

/// Lance Comskip dans un dossier de travail jetable et lit l'EDL produit.
async fn detect(video: &Path, comskip: &Path) -> Result<Vec<Break>, String> {
    let work = std::env::temp_dir().join("xtremflow_comskip");
    let _ = tokio::fs::remove_dir_all(&work).await;
    tokio::fs::create_dir_all(&work)
        .await
        .map_err(|e| format!("dossier de travail : {e}"))?;
    let result = run_comskip(video, comskip, &work).await;
    let _ = tokio::fs::remove_dir_all(&work).await;
    result
}

async fn run_comskip(video: &Path, comskip: &Path, work: &Path) -> Result<Vec<Break>, String> {
    let ini = match std::env::var("COMSKIP_INI") {
        Ok(path) if !path.is_empty() => PathBuf::from(path),
        _ => {
            let path = work.join("comskip.ini");
            tokio::fs::write(&path, DEFAULT_INI)
                .await
                .map_err(|e| format!("comskip.ini : {e}"))?;
            path
        }
    };
    // Priorité basse : la lecture et le transcodage passent avant.
    let nice = Path::new("/usr/bin/nice");
    let mut command = if cfg!(unix) && nice.exists() {
        let mut c = tokio::process::Command::new(nice);
        c.args(["-n", "15"]).arg(comskip);
        c
    } else {
        tokio::process::Command::new(comskip)
    };
    command
        .arg(format!("--ini={}", ini.display()))
        .arg(format!("--output={}", work.display()))
        .arg(video)
        .current_dir(work)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let output = tokio::time::timeout(COMSKIP_TIMEOUT, command.output())
        .await
        .map_err(|_| "Comskip bloqué, analyse abandonnée".to_string())?
        .map_err(|e| format!("Comskip impossible à lancer : {e}"))?;
    // Comskip crée l'EDL dès le départ et le remplit à la fin ; son code de
    // sortie dit seulement s'il a trouvé des pubs (0 ou 1 selon la version).
    let code = output.status.code().unwrap_or(-1);
    let edl = find_edl(work).await;
    match (code, edl) {
        (0 | 1, Some(text)) => Ok(parse_edl(&text)),
        _ => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let tail = stderr
                .split(['\r', '\n'])
                .map(str::trim)
                .rfind(|l| !l.is_empty())
                .unwrap_or("")
                .to_string();
            Err(format!("Comskip code {code} {tail}").trim_end().to_string())
        }
    }
}

async fn find_edl(dir: &Path) -> Option<String> {
    let mut entries = tokio::fs::read_dir(dir).await.ok()?;
    while let Ok(Some(entry)) = entries.next_entry().await {
        let path = entry.path();
        if path
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("edl"))
        {
            return tokio::fs::read_to_string(&path).await.ok();
        }
    }
    None
}

/// Lignes `début fin type` (secondes) ; les lignes illisibles sont ignorées.
pub fn parse_edl(text: &str) -> Vec<Break> {
    text.lines()
        .filter_map(|line| {
            let mut fields = line.split_whitespace();
            let start: f64 = fields.next()?.parse().ok()?;
            let end: f64 = fields.next()?.parse().ok()?;
            (start.is_finite() && end.is_finite()).then_some(Break { start, end })
        })
        .collect()
}

/// Coupures triées, bornées à la durée du fichier, chevauchements fusionnés.
pub fn normalize(mut breaks: Vec<Break>, duration: Option<f64>) -> Vec<Break> {
    let limit = duration.unwrap_or(f64::INFINITY);
    for b in &mut breaks {
        b.start = b.start.max(0.0);
        b.end = b.end.min(limit);
    }
    breaks.retain(|b| b.end - b.start >= 1.0);
    breaks.sort_by(|a, b| a.start.total_cmp(&b.start));
    let mut merged: Vec<Break> = Vec::with_capacity(breaks.len());
    for b in breaks {
        match merged.last_mut() {
            Some(last) if b.start <= last.end => last.end = last.end.max(b.end),
            _ => merged.push(b),
        }
    }
    merged
}

/// EDL au format Kodi : type 3 = coupure pub.
pub fn edl(breaks: &[Break]) -> String {
    breaks
        .iter()
        .map(|b| format!("{:.2}\t{:.2}\t3\n", b.start, b.end))
        .collect()
}

/// Chapitres FFmpeg (`;FFMETADATA1`) couvrant tout le fichier : programme et
/// coupures en alternance. Sans durée connue, le fichier s'arrête au début
/// du dernier chapitre « Programme ».
pub fn ffmetadata(breaks: &[Break], duration: Option<f64>) -> String {
    let mut chapters: Vec<(f64, f64, &str)> = Vec::new();
    let mut cursor = 0.0;
    for b in breaks {
        if b.start - cursor >= 1.0 {
            chapters.push((cursor, b.start, PROGRAMME_CHAPTER));
        }
        chapters.push((b.start, b.end, COMMERCIAL_CHAPTER));
        cursor = b.end;
    }
    if let Some(duration) = duration
        && duration - cursor >= 1.0
    {
        chapters.push((cursor, duration, PROGRAMME_CHAPTER));
    }
    let ms = |s: f64| (s * 1000.0).round() as i64;
    let mut out = String::from(";FFMETADATA1\n");
    for (start, end, title) in chapters {
        out.push_str(&format!(
            "[CHAPTER]\nTIMEBASE=1/1000\nSTART={}\nEND={}\ntitle={title}\n",
            ms(start),
            ms(end)
        ));
    }
    out
}

/// Remux sans réencodage avec les chapitres ; pistes, pochette et
/// métadonnées conservées. En cas d'échec, le fichier d'origine reste intact.
async fn embed_chapters(video: &Path, chapters: &str, ffmpeg: &str) -> Result<(), String> {
    let [tmp, meta] = temp_paths(video);
    tokio::fs::write(&meta, chapters)
        .await
        .map_err(|e| e.to_string())?;
    let output = tokio::process::Command::new(ffmpeg)
        .args(["-hide_banner", "-nostats", "-loglevel", "error", "-y", "-i"])
        .arg(video)
        .args(["-f", "ffmetadata", "-i"])
        .arg(&meta)
        .args(["-map", "0", "-map_metadata", "0", "-map_chapters", "1"])
        .args(["-c", "copy"])
        .arg(&tmp)
        .stdin(Stdio::null())
        .output()
        .await;
    let _ = tokio::fs::remove_file(&meta).await;
    let size = |p: &Path| std::fs::metadata(p).map(|m| m.len()).unwrap_or(0);
    let problem = match &output {
        Err(e) => Some(format!("FFmpeg impossible à lancer : {e}")),
        Ok(o) if !o.status.success() => Some(
            String::from_utf8_lossy(&o.stderr)
                .lines()
                .last()
                .unwrap_or("FFmpeg en échec")
                .to_string(),
        ),
        // Même contenu, quelques octets de chapitres en plus.
        Ok(_) if (size(&tmp) as f64) < size(video) as f64 * 0.98 => {
            Some("copie incomplète".to_string())
        }
        Ok(_) => None,
    };
    if let Some(problem) = problem {
        let _ = tokio::fs::remove_file(&tmp).await;
        return Err(problem);
    }
    // Supprimé pendant le remux : ne pas le recréer.
    if !video.exists() {
        let _ = tokio::fs::remove_file(&tmp).await;
        return Ok(());
    }
    tokio::fs::rename(&tmp, video).await.map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        e.to_string()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b(start: f64, end: f64) -> Break {
        Break { start, end }
    }

    #[test]
    fn fichiers_de_travail_caches() {
        let [mkv, txt] = temp_paths(Path::new("/rec/NBA - A @ B (2026-10-22) 0123.mkv"));
        assert_eq!(
            mkv,
            Path::new("/rec/.NBA - A @ B (2026-10-22) 0123.chapters.mkv")
        );
        assert_eq!(
            txt,
            Path::new("/rec/.NBA - A @ B (2026-10-22) 0123.chapters.txt")
        );
    }

    #[test]
    fn lecture_de_l_edl_comskip() {
        let text = "181.00\t244.96\t3\n\n1205.5 1390.25 0\nbad line\n";
        assert_eq!(parse_edl(text), vec![b(181.0, 244.96), b(1205.5, 1390.25)]);
        assert!(parse_edl("").is_empty());
    }

    #[test]
    fn coupures_triees_bornees_et_fusionnees() {
        let breaks = vec![
            b(500.0, 620.0),
            b(-2.0, 30.0),
            b(600.0, 700.0),
            b(10.0, 10.5),
        ];
        assert_eq!(
            normalize(breaks, Some(650.0)),
            vec![b(0.0, 30.0), b(500.0, 650.0)]
        );
        // Coupure entièrement après la fin mesurée : écartée.
        assert!(normalize(vec![b(700.0, 760.0)], Some(650.0)).is_empty());
    }

    #[test]
    fn edl_au_format_kodi() {
        assert_eq!(
            edl(&[b(181.0, 244.955), b(1200.0, 1380.0)]),
            "181.00\t244.96\t3\n1200.00\t1380.00\t3\n"
        );
        assert_eq!(edl(&[]), "");
    }

    #[test]
    fn chapitres_programme_et_pub_en_alternance() {
        let meta = ffmetadata(&[b(181.0, 245.0), b(600.0, 720.5)], Some(1000.0));
        assert_eq!(
            meta,
            ";FFMETADATA1\n\
             [CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=181000\ntitle=Programme\n\
             [CHAPTER]\nTIMEBASE=1/1000\nSTART=181000\nEND=245000\ntitle=Commercial\n\
             [CHAPTER]\nTIMEBASE=1/1000\nSTART=245000\nEND=600000\ntitle=Programme\n\
             [CHAPTER]\nTIMEBASE=1/1000\nSTART=600000\nEND=720500\ntitle=Commercial\n\
             [CHAPTER]\nTIMEBASE=1/1000\nSTART=720500\nEND=1000000\ntitle=Programme\n"
        );
    }

    #[test]
    fn pub_en_tout_debut_ou_en_toute_fin() {
        let meta = ffmetadata(&[b(0.0, 40.0), b(950.0, 1000.0)], Some(1000.0));
        let titles: Vec<&str> = meta
            .lines()
            .filter_map(|l| l.strip_prefix("title="))
            .collect();
        assert_eq!(titles, ["Commercial", "Programme", "Commercial"]);
        // Durée inconnue : rien après la dernière coupure.
        let meta = ffmetadata(&[b(100.0, 160.0)], None);
        assert!(meta.ends_with("START=100000\nEND=160000\ntitle=Commercial\n"));
    }
}
