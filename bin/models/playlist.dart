class Playlist {
  final String id;
  final String userId;
  final String name;
  final String serverUrl;
  final String username;
  final String password;
  final String? dns;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.userId,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.dns,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      serverUrl: map['server_url'] as String,
      username: map['username'] as String,
      password: map['password'] as String,
      dns: map['dns'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'dns': dns,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'server_url': serverUrl,
      'username': username,
      'password': password,
      'dns': dns,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
