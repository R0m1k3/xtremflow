/// Pure decision logic for the recording scheduler, extracted for testability.

enum RecordingAction {
  /// Start the recording now.
  start,

  /// Capacity reached but the window is still open: retry on a later tick.
  wait,

  /// The end time passed before the recording could start.
  fail,

  /// Not yet due — nothing to do.
  none,
}

/// Decides what to do with a scheduled recording on a scheduler tick.
RecordingAction decideRecordingAction({
  required DateTime now,
  required DateTime startTime,
  required DateTime endTime,
  required int activeCount,
  required int maxConcurrent,
}) {
  final nowUtc = now.toUtc();
  final startUtc = startTime.toUtc();
  final endUtc = endTime.toUtc();

  if (nowUtc.isAfter(endUtc)) return RecordingAction.fail;
  if (!nowUtc.isAfter(startUtc)) return RecordingAction.none;
  if (activeCount >= maxConcurrent) return RecordingAction.wait;
  return RecordingAction.start;
}

/// Ce que le planificateur doit faire d'un enregistrement resté au statut
/// « recording » en base alors qu'aucun processus FFmpeg ne lui correspond
/// (redémarrage du conteneur, crash de l'isolate…).
enum OrphanAction {
  /// La fenêtre est encore ouverte : relancer la capture.
  resume,

  /// La fenêtre est passée mais un fichier partiel existe : le conserver.
  finish,

  /// Rien d'exploitable n'a été capturé.
  fail,
}

/// Décide du sort d'un enregistrement orphelin détecté au démarrage/à un tick.
OrphanAction decideOrphanAction({
  required DateTime now,
  required DateTime endTime,
  required bool hasFile,
  Duration minRemaining = const Duration(seconds: 60),
}) {
  final remaining = endTime.toUtc().difference(now.toUtc());
  if (remaining > minRemaining) return OrphanAction.resume;
  return hasFile ? OrphanAction.finish : OrphanAction.fail;
}

/// Ce que le planificateur doit faire quand un processus FFmpeg se termine.
enum PostExitAction {
  /// La capture est allée jusqu'au bout (ou assez loin) : marquer terminé.
  complete,

  /// FFmpeg s'est arrêté trop tôt : relancer la capture sur la fin de fenêtre.
  retry,

  /// Arrêt prématuré sans rien d'exploitable.
  fail,
}

/// Nombre d'échecs FFmpeg consécutifs tolérés avant d'abandonner un
/// enregistrement dont la fenêtre est encore ouverte.
///
/// Le compteur est remis à zéro dès qu'un lancement a duré assez longtemps
/// pour être considéré sain : une coupure toutes les dix minutes ne doit pas
/// finir par épuiser le quota.
const int maxFfmpegAttempts = 30;

/// Décide de la suite à donner à la sortie d'un processus FFmpeg.
///
/// FFmpeg rend la main dès que la source se tarit : sur un flux IPTV, une
/// coupure amont à mi-parcours ne doit pas condamner l'heure restante.
PostExitAction decidePostExitAction({
  required DateTime now,
  required DateTime endTime,
  required int exitCode,
  required int consecutiveFailures,
  required bool hasFile,
  int maxAttempts = maxFfmpegAttempts,
  Duration minRemaining = const Duration(seconds: 60),
}) {
  final remaining = endTime.toUtc().difference(now.toUtc());
  if (remaining > minRemaining && consecutiveFailures + 1 < maxAttempts) {
    return PostExitAction.retry;
  }
  // `255` est le code renvoyé par FFmpeg quand on l'interrompt proprement.
  final cleanExit = exitCode == 0 || exitCode == 255;
  return (cleanExit || hasFile) ? PostExitAction.complete : PostExitAction.fail;
}

/// Durée de capture à demander à FFmpeg (`-t`).
///
/// Se base sur le temps qu'il reste jusqu'à la fin programmée, et non sur la
/// durée théorique du programme : un démarrage tardif (ou une relance après
/// coupure) ne doit pas décaler la fin de l'enregistrement.
Duration captureDuration({
  required DateTime now,
  required DateTime endTime,
  Duration minimum = const Duration(seconds: 30),
}) {
  final remaining = endTime.toUtc().difference(now.toUtc());
  return remaining < minimum ? minimum : remaining;
}

/// Délai avant relance de FFmpeg, croissant avec les échecs consécutifs.
///
/// Rouvrir la source dans la seconde se fait refuser sur les comptes limités
/// en connexions simultanées ; s'acharner à cette cadence pendant une panne
/// amont ne ferait qu'épuiser le quota de relances.
Duration ffmpegRetryDelay(int consecutiveFailures) {
  final steps = (consecutiveFailures - 1).clamp(0, 4);
  final seconds = 3 * (1 << steps);
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}
