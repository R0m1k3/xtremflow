import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/playlist.dart';
import '../models/session.dart' as models;
import '../models/recording.dart';
import '../utils/password_hasher.dart';

class AppDatabase {
  late final Database _db;
  final _uuid = const Uuid();

  /// Initialize database and create tables
  Future<void> init() async {
    const dbPath = '/app/data/xtremflow.db';

    // Ensure data directory exists
    final dir = Directory('/app/data');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _db = sqlite3.open(dbPath);

    await _createTables();
    print('Database initialized: $dbPath');
  }

  /// Create database tables
  Future<void> _createTables() async {
    // Users table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        is_admin INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Playlists table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        server_url TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        dns TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // Sessions table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        token TEXT UNIQUE NOT NULL,
        expires_at TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // User Settings table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings (
        user_id TEXT PRIMARY KEY,
        settings_json TEXT NOT NULL,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // TV Recordings table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS tv_recordings (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        stream_url TEXT NOT NULL,
        title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'scheduled',
        file_path TEXT,
        error_reason TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // Season Passes table (enregistrements répétés intelligents)
    _db.execute('''
      CREATE TABLE IF NOT EXISTS season_passes (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        show_title TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        stream_url TEXT NOT NULL,
        enabled INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // Indexes
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_playlists_user ON playlists(user_id)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recordings_status ON tv_recordings(status)',
    );
  }

  /// Seed default admin user if no users exist
  Future<void> seedAdmin() async {
    final result = _db.select('SELECT COUNT(*) as count FROM users');
    final count = result.first['count'] as int;

    if (count == 0) {
      final adminId = _uuid.v4();
      final passwordHash = PasswordHasher.hash('admin');

      _db.execute(
        '''
        INSERT INTO users (id, username, password_hash, is_admin)
        VALUES (?, ?, ?, 1)
      ''',
        [adminId, 'admin', passwordHash],
      );

      print('Default admin user created (username: admin, password: admin)');
    }
  }

  // ==================== Users ====================

  /// Find user by username
  User? findUserByUsername(String username) {
    final result = _db.select(
      'SELECT * FROM users WHERE username = ?',
      [username],
    );

    if (result.isEmpty) return null;
    return User.fromMap(result.first);
  }

  /// Find user by ID
  User? findUserById(String userId) {
    final result = _db.select(
      'SELECT * FROM users WHERE id = ?',
      [userId],
    );

    if (result.isEmpty) return null;
    return User.fromMap(result.first);
  }

  /// Verify user credentials
  User? verifyCredentials(String username, String password) {
    final result = _db.select(
      'SELECT * FROM users WHERE username = ?',
      [username],
    );

    if (result.isEmpty) return null;

    final passwordHash = result.first['password_hash'] as String;
    if (!PasswordHasher.verify(password, passwordHash)) {
      return null;
    }

    return User.fromMap(result.first);
  }

  /// Create new user
  User createUser(String username, String password, {bool isAdmin = false}) {
    final userId = _uuid.v4();
    final passwordHash = PasswordHasher.hash(password);

    _db.execute(
      '''
      INSERT INTO users (id, username, password_hash, is_admin)
      VALUES (?, ?, ?, ?)
    ''',
      [userId, username, passwordHash, isAdmin ? 1 : 0],
    );

    return User(
      id: userId,
      username: username,
      isAdmin: isAdmin,
      createdAt: DateTime.now(),
    );
  }

  /// Get all users
  List<User> getAllUsers() {
    final result = _db.select('SELECT * FROM users ORDER BY username ASC');
    return result.map((row) => User.fromMap(row)).toList();
  }

  /// Update user password
  void updateUserPassword(String userId, String newPassword) {
    final passwordHash = PasswordHasher.hash(newPassword);
    _db.execute(
      'UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
      [passwordHash, userId],
    );
  }

  /// Update user administration status
  void updateUserAdminStatus(String userId, bool isAdmin) {
    _db.execute(
      'UPDATE users SET is_admin = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
      [isAdmin ? 1 : 0, userId],
    );
  }

  /// Delete user
  void deleteUser(String userId) {
    _db.execute('DELETE FROM users WHERE id = ?', [userId]);
  }

  // ==================== Sessions ====================

  /// Create new session
  models.Session createSession(String userId, {Duration? duration}) {
    final sessionId = _uuid.v4();
    final token = _uuid.v4();
    final expiresAt = DateTime.now().add(duration ?? const Duration(days: 7));

    _db.execute(
      '''
      INSERT INTO sessions (id, user_id, token, expires_at)
      VALUES (?, ?, ?, ?)
    ''',
      [sessionId, userId, token, expiresAt.toIso8601String()],
    );

    return models.Session(
      id: sessionId,
      userId: userId,
      token: token,
      expiresAt: expiresAt,
      createdAt: DateTime.now(),
    );
  }

  /// Find session by token
  models.Session? findSessionByToken(String token) {
    final result = _db.select(
      'SELECT * FROM sessions WHERE token = ?',
      [token],
    );

    if (result.isEmpty) return null;

    final session = models.Session.fromMap(result.first);

    // Check if expired
    if (session.isExpired) {
      deleteSession(token);
      return null;
    }

    return session;
  }

  /// Delete session (logout)
  void deleteSession(String token) {
    _db.execute('DELETE FROM sessions WHERE token = ?', [token]);
  }

  /// Clean expired sessions
  void cleanExpiredSessions() {
    _db.execute(
      'DELETE FROM sessions WHERE expires_at < ?',
      [DateTime.now().toIso8601String()],
    );
  }

  // ==================== Playlists ====================

  /// Get all playlists for a user
  List<Playlist> getPlaylists(String userId) {
    final result = _db.select(
      'SELECT * FROM playlists WHERE user_id = ? ORDER BY created_at DESC',
      [userId],
    );

    return result.map((row) => Playlist.fromMap(row)).toList();
  }

  /// Get playlist by ID
  Playlist? getPlaylistById(String playlistId) {
    final result = _db.select(
      'SELECT * FROM playlists WHERE id = ?',
      [playlistId],
    );

    if (result.isEmpty) return null;
    return Playlist.fromMap(result.first);
  }

  /// Create new playlist
  Playlist createPlaylist({
    required String userId,
    required String name,
    required String serverUrl,
    required String username,
    required String password,
    String? dns,
  }) {
    final playlistId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    _db.execute(
      '''
      INSERT INTO playlists (id, user_id, name, server_url, username, password, dns, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [playlistId, userId, name, serverUrl, username, password, dns, now, now],
    );

    return Playlist(
      id: playlistId,
      userId: userId,
      name: name,
      serverUrl: serverUrl,
      username: username,
      password: password,
      dns: dns,
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
  }

  /// Update playlist
  Playlist updatePlaylist({
    required String playlistId,
    required String name,
    required String serverUrl,
    required String username,
    required String password,
    String? dns,
  }) {
    final now = DateTime.now().toIso8601String();

    _db.execute(
      '''
      UPDATE playlists 
      SET name = ?, server_url = ?, username = ?, password = ?, dns = ?, updated_at = ?
      WHERE id = ?
    ''',
      [name, serverUrl, username, password, dns, now, playlistId],
    );

    return getPlaylistById(playlistId)!;
  }

  /// Delete playlist
  void deletePlaylist(String playlistId) {
    _db.execute('DELETE FROM playlists WHERE id = ?', [playlistId]);
  }

  // ==================== User Settings ====================

  /// Get user settings as JSON string
  String? getUserSettings(String userId) {
    final result = _db.select(
      'SELECT settings_json FROM user_settings WHERE user_id = ?',
      [userId],
    );

    if (result.isEmpty) return null;
    return result.first['settings_json'] as String;
  }

  /// Update user settings
  void updateUserSettings(String userId, String settingsJson) {
    final now = DateTime.now().toIso8601String();

    // UPSERT (Insert or Replace)
    _db.execute(
      '''
      INSERT INTO user_settings (user_id, settings_json, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        settings_json = excluded.settings_json,
        updated_at = excluded.updated_at
    ''',
      [userId, settingsJson, now],
    );
  }

  /// Check if NVIDIA GPU is enabled in any user's settings
  /// This is a server-wide setting that applies to all streaming
  bool isNvidiaGpuEnabled() {
    try {
      // Check all user settings for enable_nvidia_gpu
      final result = _db.select(
        'SELECT settings_json FROM user_settings ORDER BY updated_at DESC LIMIT 1',
      );

      if (result.isEmpty) {
        print('[GPU] No user settings found in database');
        return false;
      }

      final settingsJson = result.first['settings_json'] as String;
      print('[GPU] Settings found: $settingsJson');

      // Parse JSON properly to check the setting
      // Handle both "enable_nvidia_gpu":true and "enable_nvidia_gpu": true
      final RegExp gpuRegex =
          RegExp(r'"enable_nvidia_gpu"\s*:\s*true', caseSensitive: false);
      final isEnabled = gpuRegex.hasMatch(settingsJson);

      print('[GPU] NVIDIA GPU enabled: $isEnabled');
      return isEnabled;
    } catch (e) {
      print('[GPU] Error checking GPU setting: $e');
    }
    return false;
  }

  // ==================== TV Recordings ====================

  /// Créer un nouvel enregistrement
  Recording createRecording({
    required String userId,
    required String channelId,
    required String streamUrl,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) {
    final recordingId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    _db.execute(
      '''
      INSERT INTO tv_recordings (id, user_id, channel_id, stream_url, title, start_time, end_time, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        recordingId,
        userId,
        channelId,
        streamUrl,
        title,
        startTime.toIso8601String(),
        endTime.toIso8601String(),
        now,
        now,
      ],
    );

    return Recording(
      id: recordingId,
      userId: userId,
      channelId: channelId,
      streamUrl: streamUrl,
      title: title,
      startTime: startTime,
      endTime: endTime,
      status: 'scheduled',
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
  }

  /// Lister tous les enregistrements (pour le Scheduler et l'admin)
  List<Recording> getAllRecordings() {
    final result =
        _db.select('SELECT * FROM tv_recordings ORDER BY start_time ASC');
    return result.map((row) => Recording.fromMap(row)).toList();
  }

  /// Lister les enregistrements d'un utilisateur spécifique
  List<Recording> getUserRecordings(String userId) {
    final result = _db.select(
      'SELECT * FROM tv_recordings WHERE user_id = ? ORDER BY start_time ASC',
      [userId],
    );
    return result.map((row) => Recording.fromMap(row)).toList();
  }

  /// Récupérer un enregistrement par ID
  Recording? getRecordingById(String id) {
    final result = _db.select('SELECT * FROM tv_recordings WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Recording.fromMap(result.first);
  }

  /// Mettre à jour le statut et éventuellement le chemin d'un enregistrement
  void updateRecordingStatus(String id, String status,
      {String? filePath, String? errorReason}) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      '''
      UPDATE tv_recordings 
      SET status = ?, file_path = COALESCE(?, file_path), error_reason = COALESCE(?, error_reason), updated_at = ?
      WHERE id = ?
    ''',
      [status, filePath, errorReason, now, id],
    );
  }

  /// Supprimer un enregistrement depuis la BDD (ne supprime pas le fichier)
  void deleteRecording(String id) {
    _db.execute('DELETE FROM tv_recordings WHERE id = ?', [id]);
  }

  // ==================== Season Passes ====================

  /// Créer un Season Pass (enregistrement répété par titre d'émission)
  Map<String, dynamic> createSeasonPass({
    required String userId,
    required String showTitle,
    required String channelId,
    required String streamUrl,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'INSERT INTO season_passes (id, user_id, show_title, channel_id, stream_url, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [id, userId, showTitle, channelId, streamUrl, now],
    );
    return {
      'id': id,
      'user_id': userId,
      'show_title': showTitle,
      'channel_id': channelId,
      'stream_url': streamUrl,
      'enabled': 1,
      'created_at': now
    };
  }

  /// Lister tous les Season Passes
  List<Map<String, dynamic>> getAllSeasonPasses() {
    final result = _db.select(
        'SELECT * FROM season_passes WHERE enabled = 1 ORDER BY created_at DESC');
    return result.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Supprimer un Season Pass
  void deleteSeasonPass(String id) {
    _db.execute('DELETE FROM season_passes WHERE id = ?', [id]);
  }

  /// Vérifier si un enregistrement existe déjà pour ce titre (déduplication)
  /// Retourne true si un enregistrement non-échoué avec ce titre existe pour cetteémission programméeà la même heure
  bool existsRecordingForEpisode(String title, DateTime startTime) {
    // Normaliser le titre pour la comparaison (insensible casse, sans espaces doubles)
    final result = _db.select(
      '''SELECT COUNT(*) as cnt FROM tv_recordings 
         WHERE LOWER(title) = LOWER(?) 
         AND start_time = ?
         AND status NOT IN ('failed')''',
      [title, startTime.toUtc().toIso8601String()],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// Close database connection
  void close() {
    _db.dispose();
  }
}
