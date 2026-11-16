import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, {this.tooltip});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? tooltip;
}

/// Same order as the dashboard's IndexedStack: 0 Direct, 1 Films, 2 Séries,
/// 3 Enregistrements, 4 Réglages.
const _destinations = [
  _Destination('Direct', Icons.live_tv_outlined, Icons.live_tv),
  _Destination('Films', Icons.movie_outlined, Icons.movie),
  _Destination('Séries', Icons.layers_outlined, Icons.layers),
  _Destination(
    'Enreg.',
    Icons.videocam_outlined,
    Icons.videocam,
    tooltip: 'Enregistrements',
  ),
  _Destination('Réglages', Icons.settings_outlined, Icons.settings),
];

/// Phone shell (browser narrower than 768 px): the page on the ambient
/// background, a Material navigation bar at the bottom (`surface`, indicator
/// `accentFill`, see `AppTheme.darkTheme`), as in xtremobile's phone layout.
class MobileScaffold extends ConsumerWidget {
  final Widget child;
  final int currentIndex;
  final Function(int) onIndexChanged;

  const MobileScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // The ambient image is opaque: no second full-screen fill.
      backgroundColor: Colors.transparent,
      body: AmbientBackground(child: child),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onIndexChanged,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accentFill,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
                tooltip: d.tooltip,
              ),
          ],
        ),
      ),
    );
  }
}
