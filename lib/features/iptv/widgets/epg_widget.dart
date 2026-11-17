import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/playlist_config.dart';
import '../providers/xtream_provider.dart';
import '../models/xtream_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';

class EPGWidget extends ConsumerStatefulWidget {
  final String channelId;
  final PlaylistConfig playlist;

  const EPGWidget({super.key, required this.channelId, required this.playlist});

  @override
  ConsumerState<EPGWidget> createState() => _EPGWidgetState();
}

class _EPGWidgetState extends ConsumerState<EPGWidget> {
  ShortEPG? _epg;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEPG();
  }

  Future<void> _loadEPG() async {
    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final epg = await service.getShortEPG(widget.channelId);

      if (mounted) {
        setState(() {
          _epg = epg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Chargement du guide…',
              style: AppTheme.body(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (_epg == null ||
        (_epg!.nowPlaying == null && _epg!.nextPlaying == null)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const GlassDecoration(radius: 10, halo: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Now Playing
          if (_epg!.nowPlaying != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'En direct',
                    style: AppTheme.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _epg!.nowPlaying!,
                    style: AppTheme.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Progress bar
            if (_epg!.progress != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _epg!.progress!.clamp(0.0, 1.0),
                  backgroundColor: AppColors.track,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.live,
                  ),
                  minHeight: 3,
                ),
              ),
            ],
          ],

          // Next Playing
          if (_epg!.nextPlaying != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.upcoming,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ensuite : ${_epg!.nextPlaying}',
                    style: AppTheme.body(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
