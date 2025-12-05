import 'package:hive/hive.dart';

part 'app_user.g.dart';

@HiveType(typeId: 0)
class AppUser {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String username;

  @HiveField(2)
  final String passwordHash; // SHA-256 hash

  @HiveField(3)
  final bool isAdmin;

  @HiveField(4)
  final List<String> assignedPlaylistIds;

  @HiveField(5)
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.isAdmin,
    required this.assignedPlaylistIds,
    required this.createdAt,
  });

  AppUser copyWith({
    String? id,
    String? username,
    String? passwordHash,
    bool? isAdmin,
    List<String>? assignedPlaylistIds,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      isAdmin: isAdmin ?? this.isAdmin,
      assignedPlaylistIds: assignedPlaylistIds ?? this.assignedPlaylistIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
