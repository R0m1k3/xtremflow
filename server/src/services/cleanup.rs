//! Purge périodique des fichiers temporaires et des logs de plus de 24 h.
//!
//! Ne JAMAIS cibler le dossier temporaire système en récursif : il contient
//! le dossier des sessions HLS — les fichiers de plus de 24 h y seraient
//! supprimés aveuglément.

use crate::dart_time::now_local_iso;
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

pub struct CleanupService {
    targets: Mutex<Vec<PathBuf>>,
    max_age: Duration,
}

impl CleanupService {
    pub fn new() -> Self {
        Self {
            targets: Mutex::new(Vec::new()),
            max_age: Duration::from_secs(24 * 3600),
        }
    }

    /// Ajoute un dossier surveillé (créé s'il manque).
    pub fn add_target(&self, dir: &str) {
        let path = PathBuf::from(dir);
        if !path.exists() {
            match std::fs::create_dir_all(&path) {
                Ok(()) => println!("CleanupService: Created missing directory: {dir}"),
                Err(e) => {
                    println!(
                        "CleanupService: Should monitor {dir} but it does not exist and could not be created: {e}"
                    );
                    return;
                }
            }
        }
        self.targets.lock().unwrap().push(path);
        println!("CleanupService: Monitoring {dir}");
    }

    /// Lance la purge immédiatement puis toutes les 6 heures.
    pub fn start(self: &std::sync::Arc<Self>) {
        println!("CleanupService: Starting scheduler (Interval: 6h)");
        let this = self.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(6 * 3600));
            loop {
                interval.tick().await;
                this.run_cleanup().await;
            }
        });
    }

    /// Purge manuelle (aussi exposée via /api/admin/purge).
    pub async fn run_cleanup(&self) -> Value {
        println!("CleanupService: Running cleanup task...");
        let targets = self.targets.lock().unwrap().clone();
        let max_age = self.max_age;
        let (deleted, freed, errors) = tokio::task::spawn_blocking(move || {
            let mut deleted = 0u64;
            let mut freed = 0u64;
            let mut errors = Vec::new();
            let threshold = SystemTime::now() - max_age;
            for dir in targets {
                if !dir.exists() {
                    continue;
                }
                match clean_directory(&dir, threshold) {
                    Ok((count, bytes)) => {
                        deleted += count;
                        freed += bytes;
                    }
                    Err(e) => {
                        println!("CleanupService: Error processing {}: {e}", dir.display());
                        errors.push(format!("Error in {}: {e}", dir.display()));
                    }
                }
            }
            (deleted, freed, errors)
        })
        .await
        .unwrap_or((0, 0, vec!["cleanup task panicked".to_string()]));

        println!(
            "CleanupService: Cleanup complete. Deleted {deleted} files, freed {:.2} MB",
            freed as f64 / 1024.0 / 1024.0
        );
        json!({
            "status": "complete",
            "deleted_files": deleted,
            "freed_bytes": freed,
            "timestamp": now_local_iso(),
            "errors": errors,
        })
    }
}

/// Supprime récursivement les fichiers modifiés avant [threshold] (sans
/// suivre les liens symboliques).
fn clean_directory(dir: &Path, threshold: SystemTime) -> std::io::Result<(u64, u64)> {
    let mut count = 0;
    let mut bytes = 0;
    for entry in std::fs::read_dir(dir)? {
        let Ok(entry) = entry else { continue };
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_symlink() {
            continue;
        }
        if file_type.is_dir() {
            if let Ok((c, b)) = clean_directory(&entry.path(), threshold) {
                count += c;
                bytes += b;
            }
            continue;
        }
        if !file_type.is_file() {
            continue;
        }
        let Ok(meta) = entry.metadata() else { continue };
        let Ok(modified) = meta.modified() else {
            continue;
        };
        // Erreurs individuelles ignorées (fichier verrouillé…).
        if modified < threshold && std::fs::remove_file(entry.path()).is_ok() {
            count += 1;
            bytes += meta.len();
        }
    }
    Ok((count, bytes))
}
