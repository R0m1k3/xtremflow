import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

/// Utility class for secure password hashing and verification
class CryptoUtils {
  static const _uuid = Uuid();

  /// Generates a random salt using UUID v4
  static String generateSalt() {
    return _uuid.v4();
  }

  /// Hashes a password with the provided salt using SHA-256
  /// 
  /// Returns the hashed password as a hex string
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verifies a password against a stored hash
  /// 
  /// [input] The password to verify
  /// [storedHash] The complete stored hash in format "salt:hash"
  /// 
  /// Returns true if the password matches
  static bool verifyPassword(String input, String storedHash) {
    try {
      final parts = storedHash.split(':');
      if (parts.length != 2) return false;
      
      final salt = parts[0];
      final expectedHash = parts[1];
      final inputHash = hashPassword(input, salt);
      
      return inputHash == expectedHash;
    } catch (e) {
      return false;
    }
  }

  /// Creates a complete password hash in the format "salt:hash"
  /// 
  /// This is the format stored in the database
  static String createPasswordHash(String password) {
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    return '$salt:$hash';
  }
}
