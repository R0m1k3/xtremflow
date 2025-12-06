import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/models/app_user.dart';

/// Auth state
class AuthState {
  final AppUser? currentUser;
  final bool isLoading;
  final String? errorMessage;
  final bool isInitialized;

  const AuthState({
    this.currentUser,
    this.isLoading = false,
    this.errorMessage,
    this.isInitialized = false,
  });

  bool get isAuthenticated => currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;

  AuthState copyWith({
    AppUser? currentUser,
    bool? isLoading,
    String? errorMessage,
    bool? isInitialized,
    bool clearUser = false,
  }) {
    return AuthState(
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// Auth notifier using API
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApiService _authService = AuthApiService();

  AuthNotifier() : super(const AuthState()) {
    // Auto-check for existing session
    checkSession();
  }

  /// Check if there's an existing valid session
  Future<void> checkSession() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        state = AuthState(
          currentUser: user,
          isLoading: false,
          isInitialized: true,
        );
      } else {
        state = const AuthState(isInitialized: true);
      }
    } catch (e) {
      state = const AuthState(isInitialized: true);
    }
  }

  /// Login with username and password
  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final result = await _authService.login(username, password);

      if (result.success && result.user != null) {
        state = AuthState(
          currentUser: result.user,
          isLoading: false,
          isInitialized: true,
        );
        return true;
      } else {
        state = AuthState(
          isLoading: false,
          isInitialized: true,
          errorMessage: result.error ?? 'Login failed',
        );
        return false;
      }
    } catch (e) {
      state = AuthState(
        isLoading: false,
        isInitialized: true,
        errorMessage: 'Network error: $e',
      );
      return false;
    }
  }

  /// Logout current user
  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(isInitialized: true);
  }

  /// Get current user
  AppUser? get currentUser => state.currentUser;
}

/// Auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
