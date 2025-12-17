/// Pure Dart model for Xtream Codes playlist configuration
/// This is a server-side copy without Hive/Equatable dependencies
class PlaylistConfig {
  final String id;
  final String name;

  /// Xtream server URL (without trailing slash)
  final String dns;

  final String username;

  /// Xtream password
  final String password;

  final DateTime createdAt;

  final bool isActive;

  const PlaylistConfig({
    required this.id,
    required this.name,
    required this.dns,
    required this.username,
    required this.password,
    required this.createdAt,
    this.isActive = true,
  });

  /// Creates a copy of this playlist with updated fields
  PlaylistConfig copyWith({
    String? id,
    String? name,
    String? dns,
    String? username,
    String? password,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return PlaylistConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      dns: dns ?? this.dns,
      username: username ?? this.username,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Generate Xtream API base URL
  String get apiBaseUrl => '$dns/player_api.php';
}
