import 'package:hive/hive.dart';

part 'playlist_config.g.dart';

@HiveType(typeId: 1)
class PlaylistConfig {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String dns; // Xtream server URL (without trailing slash)

  @HiveField(3)
  final String username;

  @HiveField(4)
  final String password; // Will be encrypted by Hive

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
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
