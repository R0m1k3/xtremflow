import '../api/api_client.dart';
import '../models/app_user.dart';

/// Service for authentication via API
class AuthApiService {
  final ApiClient _api = ApiClient();

  /// Login with username and password
  Future<AuthResult> login(String username, String password) async {
    try {
      final response = await _api.post('/api/auth/login', data: {
        'username': username,
        'password': password,
      },);

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final token = data['token'] as String;
        final userData = data['user'] as Map<String, dynamic>;
        
        _api.setToken(token);
        
        return AuthResult(
          success: true,
          user: AppUser(
            id: userData['id'] as String,
            username: userData['username'] as String,
            passwordHash: '', // Not needed for API auth
            isAdmin: userData['isAdmin'] as bool? ?? false,
            createdAt: DateTime.now(),
          ),
          token: token,
        );
      } else {
        return AuthResult(
          success: false,
          error: data['error'] as String? ?? 'Login failed',
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Network error: $e',
      );
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } finally {
      _api.clearToken();
    }
  }

  /// Get current user from token
  Future<AppUser?> getCurrentUser() async {
    _api.restoreToken();
    
    if (_api.getStoredToken() == null) {
      return null;
    }

    try {
      final response = await _api.get('/api/auth/me');
      final data = response.data as Map<String, dynamic>;
      final userData = data['user'] as Map<String, dynamic>;
      
      return AppUser(
        id: userData['id'] as String,
        username: userData['username'] as String,
        passwordHash: '',
        isAdmin: userData['isAdmin'] as bool? ?? false,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      _api.clearToken();
      return null;
    }
  }
}

/// Result of authentication attempt
class AuthResult {
  final bool success;
  final AppUser? user;
  final String? token;
  final String? error;

  AuthResult({
    required this.success,
    this.user,
    this.token,
    this.error,
  });
}
