import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/xtream_provider.dart';
import '../screens/playlist_selection_screen.dart';

/// Nomme l'IPTV active et permet d'en changer sans quitter l'onglet courant.
///
/// Rien à l'écran ne disait sur quelle IPTV on travaillait : guide,
/// enregistrements et Auto NBA appartiennent pourtant à une playlist précise,
/// et deux playlists affichant le même contenu passaient pour un défaut du
/// filtrage alors que la sélection elle-même était invisible.
///
/// Écrit comme `QualitySelectorButton`, l'autre sélecteur du projet : même
/// `PopupMenuButton` sous un `Tooltip`, même surface, même forme, mêmes
/// marques de sélection.
class PlaylistSelectorButton extends ConsumerWidget {
  /// IPTV active, telle que l'écran la connaît déjà.
  final PlaylistConfig current;

  const PlaylistSelectorButton({super.key, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La liste peut n'être pas encore chargée : le menu se réduit alors à
    // l'IPTV courante, qui reste nommée.
    final playlists =
        ref.watch(playlistsProvider).valueOrNull ?? <PlaylistConfig>[current];

    return Tooltip(
      message: 'IPTV : ${current.name}',
      child: PopupMenuButton<PlaylistConfig>(
        initialValue: current,
        color: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // Le menu s'ouvre à la même abscisse que celui du profil, juste en
        // dessous. Son `Offset(56, -12)` est mesuré depuis un avatar de 40
        // centré dans le rail de 80, soit 20 + 56. Ce déclencheur-ci est large
        // de 64, donc centré à 8 : il faut 68 pour retomber au même endroit.
        offset: const Offset(68, -12),
        onSelected: (playlist) {
          if (playlist.id == current.id) return;
          selectPlaylist(ref, playlist);
        },
        itemBuilder: (context) => playlists
            .map(
              (playlist) => PopupMenuItem<PlaylistConfig>(
                value: playlist,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      playlist.id == current.id
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 18,
                      color: playlist.id == current.id
                          ? AppColors.primary
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        playlist.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.karla(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.playlist_play,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            // Le nom tient sous l'icône : c'est lui l'information, le reste
            // n'est que la poignée pour en changer.
            SizedBox(
              width: 64,
              child: Text(
                current.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.karla(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
