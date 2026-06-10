import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

class PasswordHasher {
  /// Cost factor 10: ~100-300ms per hash in pure Dart, acceptable for login frequency.
  static const int _bcryptRounds = 10;

  /// Legacy hashes are unsalted SHA-256 hex digests (64 hex chars).
  static final RegExp _legacyPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Hash a password using bcrypt (salt embedded in the result).
  static String hash(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: _bcryptRounds));
  }

  /// Verify a password against a stored hash.
  /// Supports legacy unsalted SHA-256 hashes for accounts created before
  /// the bcrypt migration; those are rehashed lazily on successful login.
  static bool verify(String password, String hash) {
    if (isLegacy(hash)) {
      final digest = sha256.convert(utf8.encode(password)).toString();
      return digest == hash;
    }
    try {
      return BCrypt.checkpw(password, hash);
    } catch (_) {
      // Malformed hash (neither legacy SHA-256 nor valid bcrypt)
      return false;
    }
  }

  /// True if the stored hash uses the legacy unsalted SHA-256 scheme.
  static bool isLegacy(String hash) => _legacyPattern.hasMatch(hash);
}
