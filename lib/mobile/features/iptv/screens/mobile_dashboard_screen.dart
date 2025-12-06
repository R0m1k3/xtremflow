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
    // Determine which tab to show
    Widget currentTab;
    switch (_currentIndex) {
      case 0:
        currentTab = MobileLiveTVTab(playlist: widget.playlist);
        break;
      case 1:
        currentTab = MobileMoviesTab(playlist: widget.playlist);
        break;
      case 2:
        currentTab = MobileSeriesTab(playlist: widget.playlist);
        break;
      case 3:
        currentTab = const MobileSettingsTab();
        break;
      default:
        currentTab = MobileLiveTVTab(playlist: widget.playlist);
    }

    return Theme(
      data: MobileTheme.darkTheme,
      child: MobileScaffold(
        currentIndex: _currentIndex,
        onIndexChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        child: currentTab,
      ),
    );
  }
}
