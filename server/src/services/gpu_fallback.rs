//! Repli GPU → CPU des transcodages.
//!
//! Quand la VRAM est saturée (plusieurs sessions NVENC, un autre processus
//! sur la carte) ou que le GPU dépasse son quota de sessions d'encodage,
//! FFmpeg échoue à l'ouverture de l'encodeur et meurt en une seconde. Sans
//! repli, le lecteur recevait un 502, relançait… et retombait sur le même
//! GPU saturé : le flux restait illisible tant que la carte était pleine.

use regex::Regex;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

/// Signatures FFmpeg d'un échec imputable au GPU NVIDIA (NVENC/NVDEC/CUDA).
///
/// N'est consulté que pour une session lancée sur le GPU : « opening
/// encoder » y désigne donc forcément h264_nvenc.
static GPU_FAILURE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)nvenc|cuda|cuvid|nvdec|OpenEncodeSession|No capable devices|out of memory|Device creation failed|hwaccel|opening encoder",
    )
    .unwrap()
});

/// Vrai si [error] (stderr récent de FFmpeg) trahit une panne GPU, et non
/// une source injoignable ou un délai dépassé — qu'un repli CPU ne
/// réglerait pas, et qui doublerait inutilement la charge du serveur.
pub fn is_gpu_failure(error: Option<&str>) -> bool {
    error.is_some_and(|e| GPU_FAILURE.is_match(e))
}

/// Mémorise une panne GPU récente pour que les sessions suivantes partent
/// directement sur le CPU, au lieu de payer chacune un échec NVENC avant
/// leur repli.
pub struct GpuHealth {
    cooldown: Duration,
    unavailable_until: Mutex<Option<Instant>>,
}

impl GpuHealth {
    pub fn new(cooldown: Duration) -> Self {
        Self {
            cooldown,
            unavailable_until: Mutex::new(None),
        }
    }

    pub fn available(&self) -> bool {
        self.available_at(Instant::now())
    }

    pub fn available_at(&self, now: Instant) -> bool {
        match *self.unavailable_until.lock().unwrap() {
            None => true,
            Some(until) => now >= until,
        }
    }

    pub fn mark_failed(&self) {
        self.mark_failed_at(Instant::now());
    }

    pub fn mark_failed_at(&self, now: Instant) {
        *self.unavailable_until.lock().unwrap() = Some(now + self.cooldown);
    }
}

impl Default for GpuHealth {
    fn default() -> Self {
        Self::new(Duration::from_secs(120))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detecte_les_pannes_gpu() {
        assert!(is_gpu_failure(Some(
            "FFmpeg exited (1): [h264_nvenc @ 0x55] OpenEncodeSessionEx failed: out of memory (10)"
        )));
        assert!(is_gpu_failure(Some(
            "[h264_nvenc @ 0x1] No capable devices found"
        )));
        assert!(is_gpu_failure(Some(
            "cu->cuInit(0) failed -> CUDA_ERROR_OUT_OF_MEMORY"
        )));
        assert!(is_gpu_failure(Some(
            "Error while opening encoder for output stream #0:0 - maybe incorrect parameters such as bit_rate, rate, width or height"
        )));
    }

    #[test]
    fn ignore_les_pannes_amont_et_les_delais() {
        assert!(!is_gpu_failure(Some(
            "FFmpeg exited (1): http://x/live/u/p/1.ts: Server returned 404 Not Found"
        )));
        assert!(!is_gpu_failure(Some("Timeout waiting for transcoder")));
        assert!(!is_gpu_failure(None));
    }

    #[test]
    fn disponible_apres_le_delai() {
        let health = GpuHealth::new(Duration::from_secs(120));
        let t0 = Instant::now();
        assert!(health.available_at(t0));
        health.mark_failed_at(t0);
        assert!(!health.available_at(t0 + Duration::from_secs(119)));
        assert!(health.available_at(t0 + Duration::from_secs(120)));
    }
}
