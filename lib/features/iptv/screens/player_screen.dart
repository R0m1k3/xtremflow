import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../providers/xtream_provider.dart';
import '../widgets/epg_overlay.dart';
import '../../../core/models/playlist_config.dart';

/// Stream type enum for player
enum StreamType { live, vod, series }

/// Video player screen using HTML5 player with mpegts.js for TS streams
class PlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String containerExtension;
  final PlaylistConfig playlist;

  const PlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  String? _streamUrl;
  String? _errorMessage;
  late String _viewId;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'iptv-player-${widget.streamId}-${DateTime.now().millisecondsSinceEpoch}';
    _initializePlayer();
  }

  void _initializePlayer() {
    try {
      // Validate playlist before proceeding
      if (widget.playlist.dns.isEmpty || 
          widget.playlist.username.isEmpty || 
          widget.playlist.password.isEmpty) {
        throw Exception('Invalid playlist configuration: missing credentials');
      }

      final xtreamService = ref.read(xtreamServiceProvider(widget.playlist));
      
      // Explicitly ensure playlist is set (defensive programming)
      xtreamService.setPlaylist(widget.playlist);
      
      // Generate stream URL based on type
      late String streamUrl;
      switch (widget.streamType) {
        case StreamType.live:
          streamUrl = xtreamService.getLiveStreamUrl(widget.streamId);
          break;
        case StreamType.vod:
          streamUrl = xtreamService.getVodStreamUrl(
            widget.streamId,
            widget.containerExtension,
          );
          break;
        case StreamType.series:
          streamUrl = xtreamService.getSeriesStreamUrl(
            widget.streamId,
            widget.containerExtension,
          );
          break;
      }
      
      debugPrint('PlayerScreen: Initializing stream URL: $streamUrl');
      
      // Register the HTML view with an iframe pointing to our player.html
      final encodedUrl = Uri.encodeComponent(streamUrl);
      final playerUrl = 'player.html?url=$encodedUrl';
      
      // Register platform view factory
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src = playerUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow = 'autoplay; fullscreen'
            ..allowFullscreen = true;
          return iframe;
        },
      );

      setState(() {
        _streamUrl = streamUrl;
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load stream',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : !_isInitialized
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : Stack(
                  children: [
                    // HTML5 video player via iframe
                    HtmlElementView(viewType: _viewId),
                    // EPG overlay for live streams
                    if (widget.streamType == StreamType.live)
                      Positioned(
                        bottom: 80,
                        left: 0,
                        right: 0,
                        child: EpgOverlay(
                          streamId: widget.streamId,
                          playlist: widget.playlist,
                        ),
                      ),
                  ],
                ),
    );
  }
}
