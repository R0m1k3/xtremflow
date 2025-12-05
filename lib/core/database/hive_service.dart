import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/app_user.dart';
import '../models/playlist_config.dart';

class HiveService {
  static const String _usersBoxName = 'users';
  static const String _playlistsBoxName = 'playlists';
  static const String _encryptionKeyName = 'hive_encryption_key';
  
  static const _storage = FlutterSecureStorage();
  static bool _initialized = false;

  /// Initialize Hive for Web with encryption
  static Future<void> init() async {
    if (_initialized) return;

    // Initialize Hive for Web (uses IndexedDB)
    await Hive.initFlutter();

    // Generate or retrieve encryption key
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Register adapters
    Hive.registerAdapter(AppUserAdapter());
    Hive.registerAdapter(PlaylistConfigAdapter());

    // Open encrypted boxes
    await Hive.openBox<AppUser>(
      _usersBoxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    
    await Hive.openBox<PlaylistConfig>(
      _playlistsBoxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    // Seed default admin if no users exist
    await _seedDefaultAdmin();

    _initialized = true;
  }

  /// Get or create 256-bit encryption key
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    try {
      final existingKey = await _storage.read(key: _encryptionKeyName);
      
      if (existingKey != null) {
        return base64Decode(existingKey);
      }
    } catch (e) {
      // Storage might not be available in some web contexts
      // Fall back to session-based key (not persisted)
    }

    // Generate new 256-bit key
    final key = Hive.generateSecureKey();
    
    try {
      await _storage.write(
        key: _encryptionKeyName,
        value: base64Encode(key),
      );
    } catch (e) {
      // Ignore if storage fails - key will be regenerated next session
    }
    
    return key;
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
        assignedPlaylistIds: [],
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
