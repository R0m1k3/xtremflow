//! Logique de décision pure du planificateur d'enregistrements, isolée pour
//! être testable.

use chrono::{DateTime, Duration, Utc};

#[derive(Debug, PartialEq, Eq)]
pub enum RecordingAction {
    /// Démarrer maintenant.
    Start,
    /// Capacité atteinte mais fenêtre encore ouverte : réessayer plus tard.
    Wait,
    /// L'heure de fin est passée avant que la capture ait pu démarrer.
    Fail,
    /// Pas encore l'heure.
    None,
}

/// Que faire d'un enregistrement planifié à ce tick du scheduler ?
pub fn decide_recording_action(
    now: DateTime<Utc>,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    active_count: usize,
    max_concurrent: usize,
) -> RecordingAction {
    if now > end {
        return RecordingAction::Fail;
    }
    if now <= start {
        return RecordingAction::None;
    }
    if active_count >= max_concurrent {
        return RecordingAction::Wait;
    }
    RecordingAction::Start
}

/// Pourquoi un enregistrement planifié n'a jamais démarré.
#[derive(Debug, PartialEq, Eq)]
pub enum MissCause {
    /// Premier passage du planificateur depuis le (re)démarrage du serveur :
    /// le serveur était arrêté pendant toute la fenêtre.
    ServerDown,
    /// Aucun passage depuis cet instant, antérieur au début de la fenêtre :
    /// processus suspendu ou bloqué.
    Stalled(DateTime<Utc>),
    /// Créneaux pleins : titres des captures qui les occupaient.
    Capacity(Vec<String>),
    /// Fenêtre déjà passée quand l'enregistrement est apparu en base.
    Unknown,
}

/// Un passage a lieu toutes les 10 s : si la fenêtre s'est ouverte et
/// refermée sans démarrage, soit aucun passage n'a eu lieu pendant (serveur
/// arrêté ou bloqué), soit chacun a trouvé les créneaux pleins.
pub fn decide_miss_cause(
    start: DateTime<Utc>,
    previous_tick: Option<DateTime<Utc>>,
    waited_for: Option<Vec<String>>,
) -> MissCause {
    if let Some(busy) = waited_for {
        return MissCause::Capacity(busy);
    }
    match previous_tick {
        None => MissCause::ServerDown,
        Some(t) if t < start => MissCause::Stalled(t),
        Some(_) => MissCause::Unknown,
    }
}

/// Sort d'un enregistrement resté au statut « recording » en base alors
/// qu'aucun processus FFmpeg ne lui correspond (redémarrage du conteneur…).
#[derive(Debug, PartialEq, Eq)]
pub enum OrphanAction {
    /// La fenêtre est encore ouverte : relancer la capture.
    Resume,
    /// La fenêtre est passée mais un fichier partiel existe : le conserver.
    Finish,
    /// Rien d'exploitable n'a été capturé.
    Fail,
}

pub fn decide_orphan_action(
    now: DateTime<Utc>,
    end: DateTime<Utc>,
    has_file: bool,
) -> OrphanAction {
    let remaining = end - now;
    if remaining > Duration::seconds(60) {
        return OrphanAction::Resume;
    }
    if has_file {
        OrphanAction::Finish
    } else {
        OrphanAction::Fail
    }
}

/// Suite à donner quand un processus FFmpeg se termine.
#[derive(Debug, PartialEq, Eq)]
pub enum PostExitAction {
    /// La capture est allée jusqu'au bout (ou assez loin) : terminé.
    Complete,
    /// FFmpeg s'est arrêté trop tôt : relancer sur la fin de fenêtre.
    Retry,
    /// Arrêt prématuré sans rien d'exploitable.
    Fail,
}

/// FFmpeg rend la main dès que la source se tarit : sur un flux IPTV, une
/// coupure amont à mi-parcours ne doit pas condamner l'heure restante.
///
/// Aucun plafond d'échecs : tant que la fenêtre est ouverte, on relance
/// (au rythme de [ffmpeg_retry_delay]). Sur un compte à une connexion, le
/// panneau refuse le flux tant qu'un autre lecteur l'occupe ; abandonner
/// au bout de quelques minutes faisait perdre tout le match (constaté en
/// prod : 30 refus en 13 min, 3 h 20 de match perdues).
pub fn decide_post_exit_action(
    now: DateTime<Utc>,
    end: DateTime<Utc>,
    exit_code: i32,
    has_file: bool,
) -> PostExitAction {
    let remaining = end - now;
    if remaining > Duration::seconds(60) {
        return PostExitAction::Retry;
    }
    // `255` est le code renvoyé par FFmpeg quand on l'interrompt proprement.
    let clean_exit = exit_code == 0 || exit_code == 255;
    if clean_exit || has_file {
        PostExitAction::Complete
    } else {
        PostExitAction::Fail
    }
}

/// Cause lisible d'un code de sortie FFmpeg, pour le motif d'échec affiché.
///
/// FFmpeg ≥ 7 sort avec son code d'erreur interne (`AVERROR`, négatif)
/// tronqué à un octet : 243 = −13 = `EACCES`. Seules les causes que
/// l'utilisateur peut corriger sont nommées.
pub fn describe_ffmpeg_exit(exit_code: i32) -> Option<&'static str> {
    match exit_code {
        // −13 EACCES
        243 => Some("permission refusée sur le dossier d'enregistrement"),
        // −2 ENOENT
        254 => Some("fichier ou dossier introuvable"),
        // −28 ENOSPC
        228 => Some("disque plein"),
        // −30 EROFS
        226 => Some("dossier d'enregistrement en lecture seule"),
        // Erreurs HTTP du fournisseur (AVERROR_HTTP_*)
        8 => Some("flux refusé par le fournisseur (erreur HTTP)"),
        c if c < 0 => Some("FFmpeg interrompu par un signal"),
        _ => None,
    }
}

/// Durée de capture (`-t`) : le temps restant jusqu'à la fin programmée,
/// et non la durée théorique du programme — un démarrage tardif (ou une
/// relance après coupure) ne doit pas décaler la fin de l'enregistrement.
pub fn capture_duration(now: DateTime<Utc>, end: DateTime<Utc>) -> Duration {
    let remaining = end - now;
    let minimum = Duration::seconds(30);
    if remaining < minimum {
        minimum
    } else {
        remaining
    }
}

/// Délai avant relance de FFmpeg, croissant avec les échecs consécutifs.
///
/// Rouvrir la source dans la seconde se fait refuser sur les comptes limités
/// en connexions simultanées ; s'acharner à cette cadence pendant une panne
/// amont ne ferait qu'épuiser le quota de relances.
pub fn ffmpeg_retry_delay(consecutive_failures: u32) -> std::time::Duration {
    let steps = (consecutive_failures as i64 - 1).clamp(0, 4) as u32;
    let seconds = 3u64 * (1 << steps);
    std::time::Duration::from_secs(seconds.min(30))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn now() -> DateTime<Utc> {
        "2026-08-27T21:00:00Z".parse().unwrap()
    }

    #[test]
    fn cause_d_un_enregistrement_manque() {
        let n = now();
        let m = Duration::minutes;
        let start = n - m(200);
        assert_eq!(decide_miss_cause(start, None, None), MissCause::ServerDown);
        assert_eq!(
            decide_miss_cause(start, Some(start - m(1)), None),
            MissCause::Stalled(start - m(1))
        );
        assert_eq!(
            decide_miss_cause(start, Some(n - Duration::seconds(10)), None),
            MissCause::Unknown
        );
        assert_eq!(
            decide_miss_cause(start, None, Some(vec!["Match".into()])),
            MissCause::Capacity(vec!["Match".into()])
        );
    }

    #[test]
    fn actions_de_planification() {
        let n = now();
        let m = Duration::minutes;
        assert_eq!(
            decide_recording_action(n, n - m(1), n + m(60), 0, 2),
            RecordingAction::Start
        );
        assert_eq!(
            decide_recording_action(n, n - m(1), n + m(60), 2, 2),
            RecordingAction::Wait
        );
        assert_eq!(
            decide_recording_action(n, n - m(120), n - m(5), 0, 2),
            RecordingAction::Fail
        );
        assert_eq!(
            decide_recording_action(n, n + m(30), n + m(60), 0, 2),
            RecordingAction::None
        );
        assert_eq!(
            decide_recording_action(n, n - m(1), n + m(60), 1, 2),
            RecordingAction::Start
        );
    }

    #[test]
    fn actions_orphelines() {
        let n = now();
        assert_eq!(
            decide_orphan_action(n, n + Duration::minutes(30), true),
            OrphanAction::Resume
        );
        assert_eq!(
            decide_orphan_action(n, n + Duration::minutes(30), false),
            OrphanAction::Resume
        );
        assert_eq!(
            decide_orphan_action(n, n - Duration::minutes(5), true),
            OrphanAction::Finish
        );
        assert_eq!(
            decide_orphan_action(n, n - Duration::minutes(5), false),
            OrphanAction::Fail
        );
        assert_eq!(
            decide_orphan_action(n, n + Duration::seconds(20), true),
            OrphanAction::Finish
        );
    }

    #[test]
    fn actions_apres_sortie() {
        let n = now();
        let m40 = n + Duration::minutes(40);
        assert_eq!(
            decide_post_exit_action(n, m40, 1, true),
            PostExitAction::Retry
        );
        assert_eq!(
            decide_post_exit_action(n, m40, 0, true),
            PostExitAction::Retry
        );
        // Compte IPTV à une connexion occupé pendant 13 min : les refus en
        // série ne doivent pas faire abandonner les heures restantes.
        assert_eq!(
            decide_post_exit_action(n, m40, 8, false),
            PostExitAction::Retry
        );
        assert_eq!(
            decide_post_exit_action(n, n, 0, true),
            PostExitAction::Complete
        );
        assert_eq!(
            decide_post_exit_action(n, n, 1, true),
            PostExitAction::Complete
        );
        assert_eq!(
            decide_post_exit_action(n, n, 1, false),
            PostExitAction::Fail
        );
    }

    #[test]
    fn causes_de_sortie_ffmpeg() {
        assert_eq!(
            describe_ffmpeg_exit(243),
            Some("permission refusée sur le dossier d'enregistrement")
        );
        assert_eq!(
            describe_ffmpeg_exit(8),
            Some("flux refusé par le fournisseur (erreur HTTP)")
        );
        assert_eq!(
            describe_ffmpeg_exit(-9),
            Some("FFmpeg interrompu par un signal")
        );
        assert_eq!(describe_ffmpeg_exit(1), None);
    }

    #[test]
    fn duree_de_capture() {
        let n = now();
        assert_eq!(
            capture_duration(n, n + Duration::minutes(58)),
            Duration::minutes(58)
        );
        assert_eq!(
            capture_duration(n, n - Duration::minutes(5)),
            Duration::seconds(30)
        );
    }

    #[test]
    fn delai_de_relance() {
        let s = std::time::Duration::from_secs;
        assert_eq!(ffmpeg_retry_delay(1), s(3));
        assert_eq!(ffmpeg_retry_delay(2), s(6));
        assert_eq!(ffmpeg_retry_delay(3), s(12));
        assert_eq!(ffmpeg_retry_delay(4), s(24));
        assert_eq!(ffmpeg_retry_delay(5), s(30));
        assert_eq!(ffmpeg_retry_delay(50), s(30));
        assert_eq!(ffmpeg_retry_delay(0), s(3));
    }
}
