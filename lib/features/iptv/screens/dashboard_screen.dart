import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import '../../../core/widgets/digital_clock.dart';
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
          // 1. Global Atmospheric Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.3,
                  colors: [
                    Color(0xFF252525), // Center light
                    Color(0xFF000000), // Vignet
                  ],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          
          // 2. Main Content Area
          Positioned.fill(
            top: 0, // Content goes behind header
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Add padding top internally in tabs or here
                Padding(padding: const EdgeInsets.only(top: 100), child: LiveTVTab(playlist: widget.playlist)),
                Padding(padding: const EdgeInsets.only(top: 100), child: MoviesTab(playlist: widget.playlist)),
                Padding(padding: const EdgeInsets.only(top: 100), child: SeriesTab(playlist: widget.playlist)),
                const Padding(padding: EdgeInsets.only(top: 100), child: SettingsTab()),
              ],
            ),
          ),

          // 3. Floating Glass Header
          Positioned(
            top: 24, // Floating margin
            left: 24,
            right: 24,
            child: GlassContainer(
              height: 72,
              borderRadius: 100, // Pill shape
              opacity: 0.85,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  // Logo
                  _buildLogo(),
                  
                  const Spacer(),
                  
                  // Navigation Pills
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_tabs.length, (index) {
                      final isSelected = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: TvFocusableCard(
                          onTap: () => setState(() => _selectedIndex = index),
                          scaleFactor: 1.1,
                          borderRadius: 100,
                          focusColor: Colors.white,
                          child: AnimatedContainer(
                            duration: AppTheme.durationFast,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _icons[index],
                                  size: 18,
                                  color: isSelected ? Colors.black : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _tabs[index],
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? Colors.black : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  
                  const Spacer(),
                  
                  // Tools
                  Row(
                    children: [
                      _buildIconButton(Icons.search_rounded, () {}),
                      const SizedBox(width: 16),
                      const DigitalClock(), // Kept existing widget
                      const SizedBox(width: 16),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        child: const Icon(Icons.person_rounded, size: 20, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return TvFocusableCard(
      onTap: onTap,
      borderRadius: 50,
      scaleFactor: 1.15,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.white, Color(0xFFAAAAAA)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
        ),
        const SizedBox(width: 12),
        Text(
          'XtremFlow',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700, 
            fontSize: 18, 
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
