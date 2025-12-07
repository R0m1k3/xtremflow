import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/digital_clock.dart';
import '../widgets/live_tv_tab.dart';
import '../widgets/movies_tab.dart';
import '../widgets/series_tab.dart';
import '../widgets/settings_tab.dart';

/// Apple TV Style Dashboard
/// 
/// Uses a floating Top Bar for navigation instead of a sidebar.
/// Content flows underneath the top bar.
class DashboardScreen extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const DashboardScreen({
    super.key,
    required this.playlist,
  });

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final List<String> _tabs = ['Live TV', 'Films', 'Séries', 'Réglages'];
  final List<IconData> _icons = [Icons.live_tv, Icons.movie, Icons.tv, Icons.settings];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Glassmorphism Top Bar
    return Scaffold(
      extendBodyBehindAppBar: true, // Content behind app bar
      backgroundColor: Colors.transparent, // Transparent to show gradient
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.6), // Subtler top shadow
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              // 1. Logo Area (Fixed Width for centering balance)
              SizedBox(
                width: 200,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildLogo(),
                ),
              ),
              
              // 2. Centered Navigation Tabs (Expanded to fill space, then Centered)
              Expanded(
                child: Center(
                  child: Container(
                    height: 50,
                    constraints: const BoxConstraints(maxWidth: 600), // Prevent taking too much space
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(4),
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.white70, // Fixed: Improved readability
                      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      tabs: List.generate(_tabs.length, (index) {
                        return Tab(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(_icons[index], size: 18),
                                const SizedBox(width: 8),
                                Text(_tabs[index]),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
              
              // 3. Search / Profile (Fixed Width for centering balance)
              SizedBox(
                width: 200,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: () {
                           // Global search trigger
                        },
                      ),
                      const SizedBox(width: 16),
                      const DigitalClock(),
                      const SizedBox(width: 16),
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.person, size: 18, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background Gradient (Apple TV Depth Effect)
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2), // Slightly above center
                radius: 1.5,
                colors: [
                  Color(0xFF2C2C2E), // Dark Grey center (Light Source)
                  Color(0xFF000000), // Pure Black edges
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          
          // Content
          TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(), // Disable swipe to avoid gesture conflicts
            children: [
              // Padding top to account for the transparent AppBar
              Padding(padding: const EdgeInsets.only(top: 80), child: LiveTVTab(playlist: widget.playlist)),
              Padding(padding: const EdgeInsets.only(top: 80), child: MoviesTab(playlist: widget.playlist)),
              Padding(padding: const EdgeInsets.only(top: 80), child: SeriesTab(playlist: widget.playlist)),
              const Padding(padding: EdgeInsets.only(top: 80), child: SettingsTab()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF43cea2), Color(0xFF185a9d)]), // Green to Blue
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xtrem',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
            ),
            Text(
              'Flow',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w300, 
                fontSize: 16, 
                color: Colors.white.withOpacity(0.8),
                height: 0.8
              ),
            ),
          ],
        ),
      ],
    );
  }
}
