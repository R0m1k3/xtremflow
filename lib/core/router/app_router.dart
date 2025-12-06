import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/iptv/screens/playlist_selection_screen.dart';
import '../../features/iptv/screens/dashboard_screen.dart';
import '../../features/admin/screens/admin_panel.dart';
import '../models/playlist_config.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: RouterRefreshNotifier(ref),
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login';

      // Wait for initial auth check to complete
      if (!authState.isInitialized) {
        return null;
      }

      // Redirect to login if not authenticated
      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      // Redirect to playlists if already logged in and trying to access login
      if (isLoggedIn && isLoginRoute) {
        return '/playlists';
      }

      // Admin guard for /admin route
      if (state.matchedLocation == '/admin' && !authState.isAdmin) {
        return '/playlists';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/playlists',
        builder: (context, state) => const PlaylistSelectionScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          final playlist = state.extra as PlaylistConfig?;
          if (playlist == null) {
            // Redirect back if no playlist provided
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.go('/playlists');
            });
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return DashboardScreen(playlist: playlist);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminPanel(),
      ),
    ],
  );
});

/// Notifier that triggers router refresh when auth state changes
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(this._ref) {
    _ref.listen(authProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref _ref;
}
