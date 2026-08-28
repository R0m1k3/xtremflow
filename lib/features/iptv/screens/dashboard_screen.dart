import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import '../widgets/live_tv_tab.dart';
import '../widgets/movies_tab.dart';
import '../widgets/series_tab.dart';
import '../widgets/settings_tab.dart';
import '../widgets/recordings_tab.dart';

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
  final List<String> _tabs = [
    'Live TV',
    'Movies',
    'Series',
    'Recordings',
    'Settings',
  ];
  final List<IconData> _icons = [
    Icons.live_tv_rounded,
    Icons.movie_rounded,
    Icons.tv_rounded,
    Icons.video_library_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fond « salle de projection » — dégradé chaud du design system.
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.backgroundGradient,
              ),
            ),
          ),

          // Faisceau du projecteur, en haut à gauche.
          // Intensité volontairement basse (8 %) : au-delà, le halo délave la
          // sidebar et les cartes en pêche et sort le rendu de la palette.
          Positioned(
            top: -300,
            left: -300,
            child: Container(
              width: 800,
              height: 800,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.glowPrimary(0.08),
                    AppColors.glowPrimary(0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Braise résiduelle en bas à droite. L'ancien halo utilisait
          // `AppColors.info` (bleu-gris) : une teinte froide dans une palette
          // entièrement chaude, d'où le rendu grisâtre.
          Positioned(
            bottom: -250,
            right: -250,
            child: Container(
              width: 700,
              height: 700,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.glowPrimary(0.06),
                    AppColors.glowPrimary(0.02),
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
                RecordingsTab(playlist: widget.playlist),
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
            // Niveau « flottant » : le niveau 1 (#181310) se confondait avec
            // le haut du dégradé de fond (#1A1310) — la barre n'existait plus
            // que par sa bordure. Le niveau 2 apporte l'arête ember et
            // l'ombre profonde qui la détachent vraiment.
            child: GlassContainer.floating(
              borderRadius: 24,
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
                            color: AppColors.glowPrimary(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.onPrimary,
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
                            // Remplissage ember (`primaryContainer`) et non
                            // `primary` : cette dernière est la teinte claire
                            // réservée au texte/icône, pas aux surfaces.
                            color: isSelected
                                ? AppColors.primaryContainer
                                    .withValues(alpha: 0.20)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: isSelected
                                ? Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.55),
                                  )
                                : null,
                          ),
                          child: Icon(
                            _icons[index],
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            size: 24,
                          ),
                        ),
                      ),
                    );
                  }),

                  const Spacer(),

                  // Profil : nom d'utilisateur + déconnexion. L'avatar était
                  // un bouton mort (onTap vide) — aucune déconnexion possible
                  // depuis le dashboard desktop.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: PopupMenuButton<String>(
                      tooltip: 'Profil',
                      color: AppColors.surfaceContainerHigh,
                      offset: const Offset(56, -12),
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          enabled: false,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ref.read(authProvider).currentUser?.username ??
                                    'Utilisateur',
                                style: const TextStyle(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(
                                Icons.logout,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Déconnexion',
                                style: TextStyle(color: AppColors.onSurface),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'logout') {
                          ref.read(authProvider.notifier).logout();
                        }
                      },
                      child: const CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        child: Icon(
                          Icons.person,
                          color: AppColors.textSecondary,
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
