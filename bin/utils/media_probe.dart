import 'dart:io';

/// Inspection des fichiers média locaux (enregistrements) via ffprobe.
///
/// Les résultats sont mémorisés tant que le fichier ne change pas : une
/// liste d'enregistrements est rafraîchie toutes les 5 s pendant une capture,
/// et la playlist de lecture est rechargée en continu — sans cache, ffprobe
/// tournerait en boucle.
class MediaProbe {
  MediaProbe._();

  static final Map<String, _CacheEntry> _cache = {};

  /// Binaire ffprobe : l'image Docker l'installe dans `/usr/local/bin`
  /// à côté de FFmpeg ; `FFPROBE_PATH` permet de le surcharger.
  static String ffprobePath() {
    final fromEnv = Platform.environment['FFPROBE_PATH'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    if (Platform.isLinux && File('/usr/local/bin/ffprobe').existsSync()) {
      return '/usr/local/bin/ffprobe';
    }
    return 'ffprobe';
  }

  /// Durée du média en secondes, ou `null` si elle n'est pas mesurable
  /// (ffprobe absent, fichier introuvable, conteneur sans durée).
  static Future<double?> duration(String path) async {
    final value = await _probe(
      path,
      field: 'duration',
      args: const [
        '-show_entries', 'format=duration',
      ],
    );
    final seconds = double.tryParse(value ?? '');
    if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
    return seconds;
  }

  /// Codec de la première piste vidéo (`h264`, `hevc`, `mpeg2video`…),
  /// ou `null` si indéterminable.
  static Future<String?> videoCodec(String path) async {
    final value = await _probe(
      path,
      field: 'videoCodec',
      args: const [
        '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name',
      ],
    );
    return (value == null || value.isEmpty) ? null : value.toLowerCase();
  }

  /// Exécute ffprobe une fois par (fichier, champ) et mémorise le résultat
  /// tant que taille et date de modification sont inchangées.
  static Future<String?> _probe(
    String path, {
    required String field,
    required List<String> args,
  }) async {
    FileStat stat;
    try {
      stat = File(path).statSync();
      if (stat.type == FileSystemEntityType.notFound) return null;
    } catch (_) {
      return null;
    }

    final key = '$field@$path';
    final cached = _cache[key];
    if (cached != null && cached.matches(stat)) return cached.value;

    try {
      final result = await Process.run(ffprobePath(), [
        '-v', 'error',
        ...args,
        '-of', 'default=noprint_wrappers=1:nokey=1',
        path,
      ]);
      // ffprobe imprime une ligne par flux : seule la première nous intéresse.
      final output = (result.stdout as String).trim().split('\n').first.trim();
      if (output.isEmpty || output == 'N/A') return null;
      _cache[key] = _CacheEntry(stat, output);
      return output;
    } catch (_) {
      return null;
    }
  }
}

class _CacheEntry {
  final int size;
  final int mtimeMs;
  final String value;

  _CacheEntry(FileStat stat, this.value)
      : size = stat.size,
        mtimeMs = stat.modified.millisecondsSinceEpoch;

  bool matches(FileStat stat) =>
      stat.size == size &&
      stat.modified.millisecondsSinceEpoch == mtimeMs;
}
