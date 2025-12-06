import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode preference options
enum AppThemeMode {
  system, // Follow system preference
  light,  // Force light mode
  dark,   // Force dark mode
}

/// Keys for SharedPreferences storage
class _ThemeKeys {
  static const String themeMode = 'app_theme_mode';
}

/// Theme state containing current mode
class ThemeState {
  final AppThemeMode appThemeMode;
  final ThemeMode themeMode;

  const ThemeState({
    this.appThemeMode = AppThemeMode.dark,
    this.themeMode = ThemeMode.dark,
  });

  ThemeState copyWith({
    AppThemeMode? appThemeMode,
    ThemeMode? themeMode,
  }) {
    return ThemeState(
      appThemeMode: appThemeMode ?? this.appThemeMode,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

/// Theme provider for managing light/dark mode with persistence
class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(const ThemeState()) {
    _loadTheme();
  }

  /// Load saved theme preference from SharedPreferences
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_ThemeKeys.themeMode);
      
      if (savedMode != null) {
        final appMode = AppThemeMode.values.firstWhere(
          (e) => e.name == savedMode,
          orElse: () => AppThemeMode.dark,
        );
        state = state.copyWith(
          appThemeMode: appMode,
          themeMode: _mapToThemeMode(appMode),
        );
      }
    } catch (e) {
      debugPrint('Error loading theme: $e');
    }
  }

  /// Set theme mode and persist to SharedPreferences
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(
      appThemeMode: mode,
      themeMode: _mapToThemeMode(mode),
    );
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ThemeKeys.themeMode, mode.name);
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
  }

  /// Quick toggle between light and dark (skip system)
  Future<void> toggleTheme() async {
    final newMode = state.appThemeMode == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
    await setThemeMode(newMode);
  }

  /// Check if currently in dark mode
  bool get isDarkMode {
    return state.themeMode == ThemeMode.dark ||
        (state.themeMode == ThemeMode.system && 
         WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
  }

  /// Map AppThemeMode to Flutter's ThemeMode
  ThemeMode _mapToThemeMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

/// Provider for theme state
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});
