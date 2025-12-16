import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/app_user.dart';
import '../models/playlist_config.dart';

class HiveService {
  static const String _usersBoxName = 'users';
  static const String _playlistsBoxName = 'playlists';

  static bool _initialized = false;
  static List<int>? _encryptionKey;

  /// Initialize Hive for Web with encryption
  static Future<void> init() async {
    if (_initialized) return;

    // Initialize Hive for Web (uses IndexedDB)
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(AppUserAdapter());
    Hive.registerAdapter(PlaylistConfigAdapter());

    // Open boxes WITHOUT encryption on Web
    // Note: On Web, IndexedDB is already isolated by origin,
    // and session-based encryption keys cause decrypt errors on reload
    await Hive.openBox<AppUser>(_usersBoxName);
    await Hive.openBox<PlaylistConfig>(_playlistsBoxName);

    // Seed default admin if no users exist
    await _seedDefaultAdmin();

    _initialized = true;
  }

  /// Get or create 256-bit encryption key (web-compatible)
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    // For web: use session-based key (regenerated each session)
    // Note: Data persists in IndexedDB but encryption key is not stored
    if (_encryptionKey != null) {
      return _encryptionKey!;
    }

    // Generate new 256-bit key
    _encryptionKey = Hive.generateSecureKey();

    return _encryptionKey!;
  }

  /// Seed default admin user (admin/admin)
  static Future<void> _seedDefaultAdmin() async {
    final usersBox = Hive.box<AppUser>(_usersBoxName);

    if (usersBox.isEmpty) {
      final adminId = const Uuid().v4();
      final passwordHash = _hashPassword('admin');

      final admin = AppUser(
        id: adminId,
        username: 'admin',
        passwordHash: passwordHash,
        isAdmin: true,
        assignedPlaylistIds: const [],
        createdAt: DateTime.now(),
      );

      await usersBox.put(adminId, admin);
    }
  }

  /// Hash password using SHA-256 with salt
  static String _hashPassword(String password) {
    // Generate a random salt using the first 16 chars of a UUID
    final salt = const Uuid().v4().substring(0, 16);
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return '$salt:${digest.toString()}';
  }

  /// Verify password against stored hash
  static bool verifyPassword(String password, String storedHash) {
    try {
      final parts = storedHash.split(':');
      if (parts.length != 2) {
        // Legacy hash without salt - fallback to direct comparison
        final legacyHash = sha256.convert(utf8.encode(password)).toString();
        return legacyHash == storedHash;
      }

      final salt = parts[0];
      final expectedHash = parts[1];
      final bytes = utf8.encode(password + salt);
      final actualHash = sha256.convert(bytes).toString();

      return actualHash == expectedHash;
    } catch (e) {
      return false;
    }
  }

  /// Public method to hash passwords (used by auth)
  static String hashPassword(String password) => _hashPassword(password);

  /// Get users box
  static Box<AppUser> get usersBox => Hive.box<AppUser>(_usersBoxName);

  /// Get playlists box
  static Box<PlaylistConfig> get playlistsBox =>
      Hive.box<PlaylistConfig>(_playlistsBoxName);

  /// Close all boxes (cleanup)
  static Future<void> dispose() async {
    await Hive.close();
    _initialized = false;
  }
}
