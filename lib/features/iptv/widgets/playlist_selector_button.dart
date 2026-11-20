import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/playlist_config.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/side_rail.dart';
import '../providers/xtream_provider.dart';
import '../screens/playlist_selection_screen.dart';

/// Nomme l'IPTV active et permet d'en changer sans quitter l'onglet courant.
///
/// Guide, enregistrements et Auto NBA appartiennent à une playlist précise :
/// la barre latérale affiche donc celle qui est active (libellé « IPTV » et
/// son nom quand la barre est dépliée). Un clic ouvre la liste des IPTV.
class PlaylistSelectorButton extends ConsumerWidget {
  /// IPTV active, telle que l'écran la connaît déjà.
  final PlaylistConfig current;

  /// Barre latérale dépliée : le nom est affiché à côté de l'icône.
  final bool showLabel;

  const PlaylistSelectorButton({
    super.key,
    required this.current,
    this.showLabel = false,
  });

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    // La liste peut n'être pas encore chargée : elle se réduit alors à
    // l'IPTV courante, qui reste nommée.
    final playlists =
        ref.read(playlistsProvider).valueOrNull ?? <PlaylistConfig>[current];
    final chosen = await showAppDialog<PlaylistConfig>(
      context,
      builder: (ctx) => AppDialog(
        title: 'IPTV',
        width: 420,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in playlists) ...[
              AppDialogTile(
                icon: p.id == current.id
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                label: p.name,
                autofocus: p.id == current.id,
                onPressed: () => Navigator.of(ctx).pop(p),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (chosen == null || chosen.id == current.id) return;
    selectPlaylist(ref, chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RailItem(
      icon: Icons.playlist_play_rounded,
      label: current.name,
      sublabel: 'IPTV',
      showLabel: showLabel,
      onPressed: () => _choose(context, ref),
    );
  }
}
