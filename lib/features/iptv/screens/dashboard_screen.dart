import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/authed_http.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../core/widgets/side_rail.dart';
import '../widgets/live_tv_tab.dart';
import '../widgets/movies_tab.dart';
import '../widgets/series_tab.dart';
import '../widgets/settings_tab.dart';
import '../widgets/recordings_tab.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const DashboardScreen({super.key, required this.playlist});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  /// Focus scope of the tabs: the rail's right arrow comes back here.
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'content');

  @override
  void dispose() {
    _contentScope.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Toutes les requêtes /api/* de ce tableau de bord visent cette IPTV.
    AuthedHttp.usePlaylist(widget.playlist.id, json: widget.playlist.toJson());
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AmbientBackground(
            child: Padding(
              // Fixed inset: the rail unfolds over the content.
              padding: const EdgeInsets.only(left: SideRail.collapsedWidth),
              child: FocusScope(
                node: _contentScope,
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    LiveTVTab(playlist: widget.playlist),
                    MoviesTab(playlist: widget.playlist),
                    SeriesTab(playlist: widget.playlist),
                    RecordingsTab(playlist: widget.playlist),
                    const SettingsTab(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SideRail(
              index: _selectedIndex,
              onSelect: _select,
              playlist: widget.playlist,
              onFocusContent: () => _contentScope.requestFocus(),
            ),
          ),
        ],
      ),
    );
  }
}
