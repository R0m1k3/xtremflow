import 'package:path/path.dart' as p;

/// Path validation helpers to prevent directory traversal.
class SafePath {
  /// Resolves [candidate] and returns it only if it stays inside [baseDir].
  /// Returns null when the path escapes the base directory (e.g. via `..`
  /// segments or an absolute path pointing elsewhere).
  static String? resolveWithin(String baseDir, String candidate) {
    final base = p.normalize(p.absolute(baseDir));
    final resolved = p.normalize(
      p.isAbsolute(candidate) ? candidate : p.join(base, candidate),
    );
    if (resolved == base || p.isWithin(base, resolved)) {
      return resolved;
    }
    return null;
  }
}
