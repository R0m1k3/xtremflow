import 'dart:convert';
import 'package:crypto/crypto.dart';

class PasswordHasher {
  /// Hash a password using SHA256 (simple implementation)
  /// Note: In production, use a proper bcrypt implementation
  static String hash(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify a password against a hash
  static bool verify(String password, String hash) {
    return PasswordHasher.hash(password) == hash;
  }
}
