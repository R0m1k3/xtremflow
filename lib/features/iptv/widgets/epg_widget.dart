import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../providers/xtream_provider.dart';
import '../models/xtream_models.dart';

class EPGWidget extends ConsumerStatefulWidget {
  final String channelId;
  final PlaylistConfig playlist;

  const EPGWidget({
    super.key,
    required this.channelId,
    required this.playlist,
  });

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
        child: const Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            SizedBox(width: 8),
            Text('Loading EPG...', style: TextStyle(fontSize: 10)),
          ],
        ),
      );
    }

    if (_epg == null ||
        (_epg!.nowPlaying == null && _epg!.nextPlaying == null)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(4),
      ),
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
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'LIVE',
                    style: GoogleFonts.roboto(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _epg!.nowPlaying!,
                    style: GoogleFonts.roboto(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
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
                Icon(
                  Icons.upcoming,
                  size: 12,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Next: ${_epg!.nextPlaying}',
                    style: GoogleFonts.roboto(
                      fontSize: 10,
                      color: Colors.grey.shade400,
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
