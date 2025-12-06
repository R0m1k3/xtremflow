import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../providers/watch_history_provider.dart';
import 'player_screen.dart';

/// Series detail screen showing seasons and episodes
class SeriesDetailScreen extends ConsumerStatefulWidget {
  final Series series;
  final PlaylistConfig playlist;

  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.playlist,
  });

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  SeriesInfo? _seriesInfo;
  bool _isLoading = true;
  String? _error;
  int _selectedSeason = 1;

  @override
  void initState() {
    super.initState();
    _loadSeriesInfo();
  }

  Future<void> _loadSeriesInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final info = await service.getSeriesInfo(widget.series.seriesId);

      setState(() {
        _seriesInfo = info;
        _isLoading = false;
        // Select first available season
        if (info.episodes.isNotEmpty) {
          _selectedSeason = info.episodes.keys.first;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.series.name),
        backgroundColor: Colors.black87,
      ),
      backgroundColor: Colors.grey.shade900,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSeriesInfo,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_seriesInfo == null) return const SizedBox.shrink();

    final currentEpisodes = _seriesInfo!.episodes[_selectedSeason] ?? [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel: Series info and season selector
        SizedBox(
          width: 280,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover image
                if (_seriesInfo!.cover != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: _seriesInfo!.cover!,
                      width: 248,
                      height: 350,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 248,
                        height: 350,
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.tv, size: 64, color: Colors.white54),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                
                // Title
                Text(
                  _seriesInfo!.name,
                  style: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Rating
                if (_seriesInfo!.rating != null)
                  Row(
                    children: [
                      Icon(Icons.star, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        _seriesInfo!.rating!,
                        style: GoogleFonts.roboto(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                
                // Plot
                if (_seriesInfo!.plot != null && _seriesInfo!.plot!.isNotEmpty)
                  Text(
                    _seriesInfo!.plot!,
                    style: GoogleFonts.roboto(fontSize: 12, color: Colors.white60),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 16),
                
                // Season selector
                Text(
                  'Seasons',
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _seriesInfo!.episodes.keys.map((seasonNum) {
                    final isSelected = seasonNum == _selectedSeason;
                    return ChoiceChip(
                      label: Text('S$seasonNum'),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedSeason = seasonNum);
                        }
                      },
                      selectedColor: Colors.blue.shade700,
                      backgroundColor: Colors.grey.shade800,
                      labelStyle: GoogleFonts.roboto(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        
        // Divider
        Container(width: 1, color: Colors.grey.shade700),
        
        // Right panel: Episodes list
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Season $_selectedSeason - ${currentEpisodes.length} Episodes',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: currentEpisodes.isEmpty
                    ? Center(
                        child: Text(
                          'No episodes found',
                          style: GoogleFonts.roboto(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: currentEpisodes.length,
                        itemBuilder: (context, index) {
                          final episode = currentEpisodes[index];
                          return _buildEpisodeTile(episode);
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeTile(Episode episode) {
    final watchHistory = ref.watch(watchHistoryProvider);
    final episodeKey = WatchHistory.episodeKey(
      widget.series.seriesId,
      _selectedSeason,
      episode.episodeNum,
    );
    final isWatched = watchHistory.isEpisodeWatched(episodeKey);

    return Card(
      color: Colors.grey.shade800,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          // Mark as watched when playing
          ref.read(watchHistoryProvider.notifier).markEpisodeWatched(episodeKey);
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlayerScreen(
                streamId: episode.id,
                title: '${widget.series.name} - ${episode.title}',
                playlist: widget.playlist,
                streamType: StreamType.series,
                containerExtension: episode.containerExtension ?? 'mkv',
              ),
            ),
          );
        },
        onLongPress: () {
          // Toggle watched on long press
          ref.read(watchHistoryProvider.notifier).toggleEpisodeWatched(episodeKey);
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Episode number badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isWatched ? Colors.green : Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: isWatched
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : Text(
                          '${episode.episodeNum}',
                          style: GoogleFonts.roboto(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Episode info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isWatched ? Colors.white54 : Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (episode.durationSecs != null && episode.durationSecs! > 0)
                      Text(
                        _formatDuration(episode.durationSecs!),
                        style: GoogleFonts.roboto(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                  ],
                ),
              ),
              
              // Play icon
              Icon(
                isWatched ? Icons.replay : Icons.play_circle_outline,
                color: Colors.white70,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
