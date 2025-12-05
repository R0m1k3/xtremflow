import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/models/app_user.dart';

/// Auth state
class AuthState {
  final AppUser? currentUser;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.currentUser,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get isAuthenticated => currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;

  AuthState copyWith({
    AppUser? currentUser,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      currentUser: currentUser ?? this.currentUser,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  /// Login with username and password
  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final usersBox = HiveService.usersBox;

      // Search for user by username
      final user = usersBox.values.firstWhere(
        (user) => user.username == username,
        orElse: () => throw Exception('User not found'),
      );

      // Verify password using salt-based hashing
      if (!HiveService.verifyPassword(password, user.passwordHash)) {
        throw Exception('Invalid password');
      }

      state = AuthState(currentUser: user, isLoading: false);
      return true;
    } catch (e) {
      state = AuthState(
        isLoading: false,
        errorMessage: 'Invalid username or password',
      );
      return false;
    }
  }


  /// Logout current user
  void logout() {
    state = const AuthState();
  }

  /// Get current user
  AppUser? get currentUser => state.currentUser;
}

/// Auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
