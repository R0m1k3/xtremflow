import '../api/api_client.dart';
import '../models/app_user.dart';

/// Service for user management via API (Admin only)
class UserApiService {
  final ApiClient _api = ApiClient();

  /// Get all users (Admin only)
  Future<List<AppUser>> getAllUsers() async {
    try {
      _api.restoreToken();
      final response = await _api.get('/api/users');
      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final usersData = data['users'] as List;
        return usersData.map((u) => AppUser(
          id: u['id'] as String,
          username: u['username'] as String,
          passwordHash: '',
          isAdmin: u['isAdmin'] as bool? ?? false,
          createdAt: DateTime.tryParse(u['createdAt'] ?? '') ?? DateTime.now(),
        ),).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }

  /// Create a new user (Admin only)
  Future<UserResult> createUser({
    required String username,
    required String password,
    bool isAdmin = false,
  }) async {
    try {
      _api.restoreToken();
      final response = await _api.post('/api/users', data: {
        'username': username,
        'password': password,
        'isAdmin': isAdmin,
      },);

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final userData = data['user'] as Map<String, dynamic>;
        return UserResult(
          success: true,
          user: AppUser(
            id: userData['id'] as String,
            username: userData['username'] as String,
            passwordHash: '',
            isAdmin: userData['isAdmin'] as bool? ?? false,
            createdAt: DateTime.now(),
          ),
        );
      }
      return UserResult(
        success: false,
        error: data['error'] as String? ?? 'Failed to create user',
      );
    } catch (e) {
      return UserResult(success: false, error: 'Network error: $e');
    }
  }

  /// Update user password (Admin only)
  Future<UserResult> updatePassword({
    required String userId,
    required String newPassword,
  }) async {
    try {
      _api.restoreToken();
      final response = await _api.put('/api/users/$userId/password', data: {
        'password': newPassword,
      },);

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        return UserResult(success: true);
      }
      return UserResult(
        success: false,
        error: data['error'] as String? ?? 'Failed to update password',
      );
    } catch (e) {
      return UserResult(success: false, error: 'Network error: $e');
    }
  }

  /// Delete a user (Admin only)
  Future<UserResult> deleteUser(String userId) async {
    try {
      _api.restoreToken();
      final response = await _api.delete('/api/users/$userId');

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        return UserResult(success: true);
      }
      return UserResult(
        success: false,
        error: data['error'] as String? ?? 'Failed to delete user',
      );
    } catch (e) {
      return UserResult(success: false, error: 'Network error: $e');
    }
  }

  /// Toggle admin status (Admin only)
  Future<UserResult> toggleAdmin(String userId, bool isAdmin) async {
    try {
      _api.restoreToken();
      final response = await _api.put('/api/users/$userId', data: {
        'isAdmin': isAdmin,
      },);

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        return UserResult(success: true);
      }
      return UserResult(
        success: false,
        error: data['error'] as String? ?? 'Failed to update user',
      );
    } catch (e) {
      return UserResult(success: false, error: 'Network error: $e');
    }
  }
}

/// Result of user operation
class UserResult {
  final bool success;
  final AppUser? user;
  final String? error;

  UserResult({
    required this.success,
    this.user,
    this.error,
  });
}
