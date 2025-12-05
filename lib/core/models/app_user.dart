import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'app_user.g.dart';

/// Hive model for local application users
/// 
/// Stores user credentials with hashed passwords and admin privileges
@HiveType(typeId: 0)
class AppUser extends Equatable {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String username;

  /// Password hash in format "salt:hash"
  @HiveField(2)
  final String passwordHash;

  @HiveField(3)
  final bool isAdmin;

  /// List of playlist IDs assigned to this user
  @HiveField(4)
  final List<String> assignedPlaylistIds;

  @HiveField(5)
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    this.isAdmin = false,
    this.assignedPlaylistIds = const [],
    required this.createdAt,
  });

  /// Creates a copy of this user with updated fields
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

  @override
  List<Object?> get props => [
        id,
        username,
        passwordHash,
        isAdmin,
        assignedPlaylistIds,
        createdAt,
      ];
}
