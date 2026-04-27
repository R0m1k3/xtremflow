import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../widgets/mobile_scaffold.dart';
import '../../../theme/mobile_theme.dart';
import '../widgets/mobile_live_tv_tab.dart';
import '../widgets/mobile_movies_tab.dart';
import '../widgets/mobile_series_tab.dart';
import '../widgets/mobile_settings_tab.dart';

class MobileDashboardScreen extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  
  const MobileDashboardScreen({
    super.key, 
    required this.playlist,
  });

  @override
  ConsumerState<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends ConsumerState<MobileDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MobileTheme.darkTheme,
      child: MobileScaffold(
        currentIndex: _currentIndex,
        onIndexChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        child: _buildActiveTab(),
      ),
    );
  }

  Widget _buildActiveTab() {
    switch (_currentIndex) {
      case 0:
        return MobileLiveTVTab(playlist: widget.playlist);
      case 1:
        return MobileMoviesTab(playlist: widget.playlist);
      case 2:
        return MobileSeriesTab(playlist: widget.playlist);
      case 3:
        return const MobileSettingsTab();
      default:
        return MobileLiveTVTab(playlist: widget.playlist);
    }
  }
}
