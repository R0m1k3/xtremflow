import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive_layout.dart';
import '../widgets/live_tv_tab.dart';
import '../widgets/movies_tab.dart';
import '../widgets/series_tab.dart';
import '../widgets/settings_tab.dart';

/// Main dashboard with responsive navigation (Rail for desktop, Bar for mobile)
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

  late final List<Widget> _tabs;

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.live_tv_outlined),
      selectedIcon: Icon(Icons.live_tv),
      label: 'TV Live',
    ),
    NavigationDestination(
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie),
      label: 'Films',
    ),
    NavigationDestination(
      icon: Icon(Icons.tv_outlined),
      selectedIcon: Icon(Icons.tv),
      label: 'Séries',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Paramètres',
    ),
  ];

  static const List<NavigationRailDestination> _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.live_tv_outlined),
      selectedIcon: Icon(Icons.live_tv),
      label: Text('TV Live'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie),
      label: Text('Films'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.tv_outlined),
      selectedIcon: Icon(Icons.tv),
      label: Text('Séries'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Paramètres'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = [
      LiveTVTab(playlist: widget.playlist),
      MoviesTab(playlist: widget.playlist),
      SeriesTab(playlist: widget.playlist),
      const SettingsTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    return Scaffold(
      appBar: _buildAppBar(),
      body: isDesktop
          ? _buildDesktopLayout()
          : _buildMobileLayout(),
      bottomNavigationBar: isDesktop ? null : _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          // Logo
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.live_tv,
              color: Colors.black,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'XtremFlow',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.playlist.name,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Search button
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            // TODO: Global search
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Navigation Rail
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          extended: true,
          minExtendedWidth: 180,
          leading: const SizedBox(height: AppTheme.spacing16),
          destinations: _railDestinations,
        ),
        // Divider
        const VerticalDivider(thickness: 1, width: 1),
        // Content
        Expanded(
          child: AnimatedSwitcher(
            duration: AppTheme.durationNormal,
            child: _tabs[_selectedIndex],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return AnimatedSwitcher(
      duration: AppTheme.durationNormal,
      child: _tabs[_selectedIndex],
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      destinations: _destinations,
    );
  }
}
