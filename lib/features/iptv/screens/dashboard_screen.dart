import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import '../widgets/live_tv_tab.dart';
import '../widgets/movies_tab.dart';
import '../widgets/series_tab.dart';
import '../widgets/settings_tab.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const DashboardScreen({
    super.key,
    required this.playlist,
  });

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;
  final List<String> _tabs = ['Live TV', 'Movies', 'Series', 'Settings'];
  final List<IconData> _icons = [
    Icons.live_tv_rounded,
    Icons.movie_rounded,
    Icons.tv_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cinematic Deep Space Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F1014), // Deep Space Blue-Grey
                    Color(0xFF181920), // Darker shade
                  ],
                ),
              ),
            ),
          ),

          // Ambient Glow (Subtle accent)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Main Content Area
          Positioned.fill(
            left: 100, // Leave space for sidebar
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                LiveTVTab(playlist: widget.playlist),
                MoviesTab(playlist: widget.playlist),
                SeriesTab(playlist: widget.playlist),
                const SettingsTab(),
              ],
            ),
          ),

          // 3. Vertical Glass Sidebar
          Positioned(
            left: 24,
            top: 24,
            bottom: 24,
            width: 80,
            child: GlassContainer(
              borderRadius: 24,
              opacity: 0.1,
              // blur is hardcoded in GlassContainer (15), so we don't pass it
              // border is bool, borderColor allows customization
              border: true,
              borderColor: Colors.white.withOpacity(0.1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo Icon
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Navigation Icons
                  ...List.generate(_tabs.length, (index) {
                    final isSelected = _selectedIndex == index;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: TvFocusableCard(
                        onTap: () => setState(() => _selectedIndex = index),
                        scaleFactor: 1.2,
                        borderRadius: 16,
                        focusColor: AppColors.primary,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: isSelected
                                ? Border.all(
                                    color: AppColors.primary.withOpacity(0.5),
                                  )
                                : null,
                          ),
                          child: Icon(
                            _icons[index],
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                            size: 24,
                          ),
                        ),
                      ),
                    );
                  }),

                  const Spacer(),

                  // Settings / Profile
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: TvFocusableCard(
                      onTap: () {},
                      borderRadius: 50,
                      scaleFactor: 1.1,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
