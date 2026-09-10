import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../providers/xtream_provider.dart';
import '../providers/playback_positions_provider.dart';
import '../widgets/quality_selector_widget.dart';

// ... (existing imports)
// ... (existing imports)
import '../../../core/models/playlist_config.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_colors.dart';

enum StreamType { live, vod, series, recording }

class PlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final PlaylistConfig playlist;
  final StreamType streamType;
  final String containerExtension;
  final List<dynamic>? channels;
  final double? startTime;
  final Duration? duration;

  const PlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
    this.channels,
    this.startTime,
    this.duration,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _isPlaying = true;
  bool _showControls = false;
  Timer? _controlsTimer;
  double _currentPosition = 0;
  double _totalDuration = 1;
  int _currentIndex = 0;
  bool _isInitialized = false;
  bool _isLoading = true;
  StreamSubscription? _messageSubscription;
  bool _isSeeking = false;
  late final String _viewIdPrefix =
      DateTime.now().millisecondsSinceEpoch.toString();
  String _viewId = 'iptv-player';
  bool _isMuted = false;
  bool _ignoreStatusUpdates = false;

  /// Fin de la plage réellement navigable, en temps absolu.
  ///
  /// Un enregistrement est transcodé au fil de l'eau par FFmpeg : ce qui est
  /// au-delà de ce point n'existe pas encore côté serveur. Sauter dedans
  /// suppose de relancer l'encodeur à la position visée.
  double _seekableEnd = 0;

  /// Décalage du média courant par rapport au début du contenu : un
  /// enregistrement rouvert à 45 min est transcodé *depuis* 45 min.
  double _mediaOffset = 0;

  /// Vitesse de lecture (hors direct).
  double _rate = 1.0;

  /// Un rechargement du flux à une nouvelle position est en cours : les
  /// positions remontées par l'ancienne iframe ne doivent plus rien écraser.
  bool _seekReloading = false;

  /// Incrémenté à chaque (re)création de l'iframe : deux vues de plateforme
  /// ne peuvent pas partager le même identifiant, et il faut un identifiant
  /// neuf pour que Flutter reconstruise réellement l'iframe.
  int _viewGeneration = 0;

  /// Reflète l'état plein écran du document. Le navigateur peut en sortir
  /// sans passer par notre bouton (touche Échap), d'où l'écoute de
  /// `fullscreenchange` plutôt qu'un simple booléen basculé au clic.
  bool _isFullscreen = false;
  StreamSubscription<html.Event>? _fullscreenSubscription;

  /// Server-side transcoding quality. Live TV defaults to `source`
  /// (direct MPEG-TS proxy, zero transcoding); VOD defaults to `high`.
  late StreamQuality _quality = widget.streamType == StreamType.live
      ? StreamQuality.source
      : StreamQuality.high;

  @override
  void initState() {
    super.initState();
    if (widget.channels != null) {
      _currentIndex = widget.channels!.indexWhere((c) {
        try {
          return (c.streamId ?? c.id ?? '').toString() == widget.streamId;
        } catch (_) {
          return false;
        }
      });
      if (_currentIndex == -1) _currentIndex = 0;
    }
    // Show controls at start, then auto-hide after timeout
    _showControls = true;
    _onHover(); // Start the auto-hide timer
    _initializePlayer(startTimeOverride: widget.startTime);
    _setupMessageListener();
    _fullscreenSubscription =
        html.document.onFullscreenChange.listen((_) => _syncFullscreenState());
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _fullscreenSubscription?.cancel();
    _controlsTimer?.cancel();
    super.dispose();
  }

  /// Ne teste que l'API non préfixée.
  ///
  /// Les variantes `webkitFullscreenElement` / `mozFullScreenElement` étaient
  /// lues via un cast `dynamic` : dart2js ne retombe pas sur la propriété JS
  /// pour un membre absent de la classe `Document`, il lève un
  /// `NoSuchMethodError`. Le getter échouait donc systématiquement, et le
  /// bouton plein écran ne faisait rien. L'API standard est supportée par
  /// tous les navigateurs visés.
  bool get _documentIsFullscreen => html.document.fullscreenElement != null;

  /// Clé de reprise. Les enregistrements sont préfixés : leur identifiant est
  /// un UUID stocké dans le même espace de noms que les identifiants VOD.
  String get _positionKey => widget.streamType == StreamType.recording
      ? 'rec_${widget.streamId}'
      : widget.streamId;

  /// La position peut-elle avoir un sens (barre de progression, reprise) ?
  bool get _isSeekable => widget.streamType != StreamType.live;

  void _syncFullscreenState() {
    final value = _documentIsFullscreen;
    if (mounted && value != _isFullscreen) {
      setState(() => _isFullscreen = value);
    }
  }

  Future<void> _initializePlayer({
    double? startTimeOverride,
    bool isChannelSwitch = false,
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Determine Stream ID (Initial or Current Index)
      String currentStreamId = widget.streamId;
      if (isChannelSwitch && widget.channels != null) {
        try {
          final item = widget.channels![_currentIndex];
          currentStreamId = (item.streamId ?? item.id ?? '').toString();
        } catch (_) {}
      }

      // Stable view ID for the instance to prevent iframe reload on rebuild
      // (orientation change). La génération change à chaque appel : sans
      // elle, relancer le flux à une autre position réutiliserait la même
      // vue de plateforme et l'iframe ne serait jamais reconstruite.
      _viewId =
          'iptv-player-$currentStreamId-${_quality.value}-$_viewIdPrefix-'
          '${_viewGeneration++}';

      final service = ref.read(xtreamServiceProvider(widget.playlist));
      String streamUrl = '';

      // Generate Stream URL based on type
      // NOTE: Logic is now handled by the backend routes /api/live/ and /api/vod/
      if (widget.streamType == StreamType.live) {
        streamUrl = service.getLiveStreamUrl(
          currentStreamId,
          quality: _quality.value,
        );
      } else if (widget.streamType == StreamType.vod) {
        streamUrl = service.getVodStreamUrl(
          currentStreamId,
          widget.containerExtension,
          quality: _quality.value,
        );
      } else if (widget.streamType == StreamType.series) {
        streamUrl = service.getSeriesStreamUrl(
          currentStreamId,
          widget.containerExtension,
          quality: _quality.value,
        );
      } else if (widget.streamType == StreamType.recording) {
        // FFmpeg transcode l'enregistrement séquentiellement : reprendre à
        // 45 min sans le lui dire imposerait d'attendre qu'il y arrive.
        // `?start=` lui fait démarrer l'encodage à la position demandée.
        _mediaOffset = (startTimeOverride ?? 0) > 0
            ? startTimeOverride!.floorToDouble()
            : 0;
        final base = '${service.backendBaseUrl}/api/recordings/stream/'
            '$currentStreamId/playlist.m3u8';
        streamUrl =
            _mediaOffset > 0 ? '$base?start=${_mediaOffset.toInt()}' : base;
      }

      // Store URL for Lite Player
      final isMobile = MediaQuery.of(context).size.width < 600;
      final isLiveTV = widget.streamType == StreamType.live;

      // TURBO-START: in `source` quality, Live TV on desktop uses the direct
      // MPEG-TS proxy (mpegts.js) for instant zapping with zero transcoding.
      if (isLiveTV && !isMobile && _quality == StreamQuality.source) {
        streamUrl = service.getLiveStreamUrlTs(currentStreamId);
      }

      // STABILIZATION: Lock background requests during stream init
      service.isPlaybackLoading = true;
      Future.delayed(const Duration(seconds: 10), () {
        service.isPlaybackLoading = false;
      });

      final encodedUrl = Uri.encodeComponent(streamUrl);
      // Force player choice based on stream type:
      // - Live TV: Player Lite (simple TS playback with mpegts.js)
      // - VOD/Series: Player Standard (fuller controls, HLS support)

      final streamTypeParam =
          widget.streamType == StreamType.live ? 'live' : 'vod';
      final playerFile = isMobile
          ? 'player_mobile.html'
          : (isLiveTV ? 'player_lite.html' : 'player.html');

      // Plus de cache-buster « &v=timestamp » : il forçait le re-téléchargement
      // et le re-parse de player.html à CHAQUE zap. Le serveur sert désormais
      // les .html en no-cache, la fraîcheur est garantie sans pénaliser le zap.
      var playerSrc =
          '$playerFile?url=$encodedUrl&type=$streamTypeParam&turbo=true';

      if (widget.streamType == StreamType.recording) {
        playerSrc += '&is_recording=true';
        // Le média commence à l'offset : le lecteur ré-ajoute ce décalage
        // pour exprimer position et recherches en temps absolu.
        if (_mediaOffset > 0) playerSrc += '&offset=${_mediaOffset.toInt()}';
      } else if (startTimeOverride != null && startTimeOverride > 0) {
        playerSrc += '&t=$startTimeOverride';
      }

      if (widget.duration != null) {
        playerSrc += '&duration=${widget.duration!.inSeconds}';
      }

      // Register View Factory (Only needed for Standard Player, but safe to do always or conditionally)
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        final iframe = html.IFrameElement()
          ..id = _viewId
          ..src = playerSrc
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'autoplay; fullscreen; picture-in-picture; encrypted-media';
        return iframe;
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _isPlaying = true;
          _seekReloading = false;
          // La nouvelle iframe repart d'une plage navigable vide, qui
          // grandira au rythme du transcodage.
          _seekableEnd = _mediaOffset;
          if (_mediaOffset > 0) _currentPosition = _mediaOffset;
        });

        // Force unmute on load (after a short delay to ensure iframe is ready)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          _sendMessage({'type': 'set_volume', 'value': _isMuted ? 0.0 : 1.0});
          if (_rate != 1.0) {
            _sendMessage({'type': 'set_rate', 'value': _rate});
          }
        });
      }
    } catch (e) {
      print('[PlayerScreen] Failed to load stream: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setupMessageListener() {
    _messageSubscription = html.window.onMessage.listen((event) {
      // The player iframes are same-origin; drop messages from anywhere else.
      if (event.origin != html.window.location.origin) return;
      final data = event.data;
      if (data == null) return;

      final type = data['type'];
      if (type == 'playback_position') {
        // Un rechargement à une autre position est en cours : l'ancienne
        // iframe continue d'émettre quelques instants, ne pas la laisser
        // ramener la barre en arrière.
        if (_seekReloading) return;

        final currentTime = (data['currentTime'] as num).toDouble();
        final rawDuration = (data['duration'] as num).toDouble();
        final duration = rawDuration.isFinite ? rawDuration : 0.0;
        final rawSeekable = data['seekableEnd'];
        final seekableEnd =
            rawSeekable is num ? rawSeekable.toDouble() : currentTime;

        // Only update position if user is NOT dragging the slider
        setState(() {
          if (!_isSeeking) {
            _currentPosition = currentTime;
            _totalDuration = duration > 0 ? duration : 1;
          }
          if (seekableEnd.isFinite && seekableEnd > 0) {
            _seekableEnd = seekableEnd;
          }
        });

        // Update watch history if relevant. Jamais en live : la « position »
        // d'un flux continu n'a pas de sens et polluait le stockage avec une
        // entrée bidon par chaîne zappée.
        if (currentTime > 0 && widget.streamType != StreamType.live) {
          ref.read(playbackPositionsProvider.notifier).savePosition(
                _positionKey,
                currentTime,
                duration,
              );
        }
      } else if (type == 'seek_out_of_range') {
        // Cible hors de la zone déjà transcodée : seul un redémarrage du
        // flux à cet instant peut la servir.
        final target = (data['value'] as num?)?.toDouble();
        if (target != null) _restartAt(target);
      } else if (type == 'playback_ended') {
        setState(() => _isPlaying = false);
        ref.read(playbackPositionsProvider.notifier).clearPosition(_positionKey);
      } else if (type == 'playback_status') {
        if (!_ignoreStatusUpdates) {
          setState(() => _isPlaying = data['status'] == 'playing');
        }
      } else if (type == 'user_activity') {
        _onHover();
      }
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (!_isInitialized) return;

    // Try finding by ID first
    var iframe = html.document.getElementById(_viewId) as html.IFrameElement?;

    // If not found, try finding by src pattern (fallback for Shadow DOM or ID issues)
    if (iframe == null) {
      final iframes = html.document.getElementsByTagName('iframe');
      for (final frame in iframes) {
        if (frame is html.IFrameElement &&
            (frame.src?.contains('player_lite.html') == true ||
                frame.src?.contains('player.html') == true ||
                frame.src?.contains('player_mobile.html') == true)) {
          iframe = frame;
          break;
        }
      }
    }

    if (iframe != null) {
      iframe.contentWindow
          ?.postMessage(message, html.window.location.origin);
    } else {
      print(
        '[PlayerScreen] Error: Could not find iframe to send message: $message',
      );
    }
  }

  void _onHover() {
    setState(() => _showControls = true);
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _togglePlayPause() {
    // Optimistic update to make UI responsive immediately
    setState(() => _isPlaying = !_isPlaying);

    // Ignore incoming status updates for 2 seconds to prevent fighting
    _ignoreStatusUpdates = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _ignoreStatusUpdates = false;
    });

    if (_isPlaying) {
      _sendMessage({'type': 'play'});
    } else {
      _sendMessage({'type': 'pause'});
    }
  }

  /// Recherche à un instant absolu du contenu.
  ///
  /// Le lecteur tranche lui-même : saut local s'il a la donnée, sinon il
  /// répond `seek_out_of_range` et le flux est relancé à cet instant.
  void _seekTo(double target) {
    final clamped = target.clamp(0.0, _totalDuration);
    setState(() => _currentPosition = clamped);
    _sendMessage({'type': 'seek', 'value': clamped});
    _onHover();
  }

  void _seekBy(double delta) => _seekTo(_currentPosition + delta);

  /// Relance le flux à [target] : nouvelle session de transcodage côté
  /// serveur, donc quelques secondes d'attente — réservé aux sauts que la
  /// zone déjà transcodée ne couvre pas.
  void _restartAt(double target) {
    if (!_isSeekable || _seekReloading) return;
    // Jamais tout à la fin : FFmpeg lancé au-delà de la dernière image
    // n'encoderait rien et le lecteur n'aurait qu'une erreur à afficher.
    final ceiling =
        _totalDuration > 10 ? _totalDuration - 5 : _totalDuration;
    final clamped = target.clamp(0.0, ceiling);
    if (widget.streamType != StreamType.recording) {
      // VOD/séries : le serveur ne sait pas démarrer ailleurs qu'au début,
      // on se contente du bord de la zone disponible.
      _sendMessage({'type': 'seek', 'value': _seekableEnd});
      return;
    }
    setState(() {
      _seekReloading = true;
      _currentPosition = clamped;
    });
    _initializePlayer(startTimeOverride: clamped, isChannelSwitch: true);
  }

  void _setRate(double rate) {
    setState(() => _rate = rate);
    _sendMessage({'type': 'set_rate', 'value': rate});
    _onHover();
  }

  void _toggleFullscreen() {
    try {
      if (_documentIsFullscreen) {
        html.document.exitFullscreen();
      } else {
        final element = html.document.documentElement;
        if (element != null) {
          element.requestFullscreen();
        }
      }
    } catch (e) {
      print('[PlayerScreen] Fullscreen error: $e');
      _sendMessage({'type': 'request_fullscreen'});
    }
    // `fullscreenchange` arrive de façon asynchrone : relire l'état juste
    // après l'appel évite que l'icône reste figée si l'évènement est perdu.
    Future.delayed(
      const Duration(milliseconds: 150),
      _syncFullscreenState,
    );
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _sendMessage({'type': 'set_volume', 'value': _isMuted ? 0.0 : 1.0});
  }

  void _changeQuality(StreamQuality quality) {
    if (quality == _quality) return;
    setState(() => _quality = quality);
    // Rebuild the iframe with the new quality; VOD resumes at the
    // current position, live restarts at the live edge.
    final resumeAt =
        widget.streamType == StreamType.live ? null : _currentPosition;
    // Un enregistrement redémarre à cette position côté serveur : sa zone
    // navigable repart de zéro.
    _initializePlayer(startTimeOverride: resumeAt, isChannelSwitch: true);
  }

  void _previousChannel() {
    if (widget.channels != null && widget.channels!.isNotEmpty) {
      setState(() {
        if (_currentIndex > 0) {
          _currentIndex--;
        } else {
          _currentIndex = widget.channels!.length - 1;
        }
      });
      _initializePlayer(isChannelSwitch: true);
    }
  }

  void _nextChannel() {
    if (widget.channels != null && widget.channels!.isNotEmpty) {
      setState(() {
        if (_currentIndex < widget.channels!.length - 1) {
          _currentIndex++;
        } else {
          _currentIndex = 0;
        }
      });
      _initializePlayer(isChannelSwitch: true);
    }
  }

  /// Sauts proposés par les raccourcis et les boutons.
  static const _smallStep = 10.0;
  static const _bigStep = 60.0;

  /// Vitesses de lecture proposées hors direct.
  static const _rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// Keyboard / TV remote controls:
  /// space-enter-K = play/pause, ←/→ = seek ±10 s (VOD) or zap (live),
  /// Maj+←/→ ou J/L = ±60 s, ↑/↓ = zap (live), 0-9 = saut en % du contenu,
  /// M = mute, F = plein écran, +/- = vitesse, Esc = exit player.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isLive = widget.streamType == StreamType.live;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      _onHover();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      _onHover();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      _onHover();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isLive) {
        _previousChannel();
        _onHover();
      } else {
        _seekBy(shift ? -_bigStep : -_smallStep);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isLive) {
        _nextChannel();
        _onHover();
      } else {
        _seekBy(shift ? _bigStep : _smallStep);
      }
      return KeyEventResult.handled;
    }
    if (isLive && key == LogicalKeyboardKey.arrowUp) {
      _nextChannel();
      _onHover();
      return KeyEventResult.handled;
    }
    if (isLive && key == LogicalKeyboardKey.arrowDown) {
      _previousChannel();
      _onHover();
      return KeyEventResult.handled;
    }
    if (!isLive) {
      if (key == LogicalKeyboardKey.keyJ) {
        _seekBy(-_bigStep);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        _seekBy(_bigStep);
        return KeyEventResult.handled;
      }
      // 0-9 : saut direct au dixième correspondant du contenu.
      final decile = _decileFor(key);
      if (decile != null) {
        _seekTo(_totalDuration * decile / 10);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.period) {
        _stepRate(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.comma) {
        _stepRate(-1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Touche 0-9 (rangée du haut ou pavé numérique) → dixième visé.
  /// Table non `const` : `LogicalKeyboardKey` redéfinit `==`, ce qui interdit
  /// une table constante.
  static final Map<LogicalKeyboardKey, int> _digitKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  int? _decileFor(LogicalKeyboardKey key) => _digitKeys[key];

  void _stepRate(int direction) {
    final index = _rates.indexOf(_rate);
    final next = (index < 0 ? _rates.indexOf(1.0) : index) + direction;
    if (next < 0 || next >= _rates.length) return;
    _setRate(_rates[next]);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isLiveTV = widget.streamType == StreamType.live;

    // LITE PLAYER MODE for Live TV - Simplified UI (no BackdropFilter)
    if (isLiveTV) {
      return Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video Player
            if (_isInitialized) HtmlElementView(viewType: _viewId),

            // Control Overlay (sits on top of video, catches all pointer events)
            Positioned.fill(
              child: PointerInterceptor(
                child: MouseRegion(
                  onHover: (_) => _onHover(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_showControls) {
                        setState(() => _showControls = false);
                      } else {
                        _onHover();
                      }
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Stack(
                        children: [
                          // Top Bar
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            top: _showControls ? 0 : -100,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.background.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: SafeArea(
                                bottom: false,
                                child: Row(
                                  children: [
                                    _buildSimpleIconButton(
                                      icon: Icons.arrow_back_rounded,
                                      onTap: () => Navigator.pop(context),
                                      tooltip: 'Retour',
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.channels != null
                                                ? (widget
                                                            .channels![
                                                                _currentIndex]
                                                            .name ??
                                                        widget
                                                            .channels![
                                                                _currentIndex]
                                                            .title ??
                                                        'Unknown')
                                                    .toString()
                                                : widget.title,
                                            style: GoogleFonts.fraunces(
                                              color: AppColors.textPrimary,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Live TV',
                                            style: GoogleFonts.karla(
                                              color: AppColors.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Top right mute button removed
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Unified Bottom Bar - EPG + Controls in one bar
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            bottom: _showControls
                                ? 24
                                : -150, // More offset for stacked layout
                            left: 16,
                            right: 16,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isSmallScreen =
                                    constraints.maxWidth < 600;
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isSmallScreen ? 16 : 20,
                                    vertical: isSmallScreen ? 12 : 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.background
                                            .withOpacity(0.3),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                    border: Border.all(
                                      color: AppColors.textPrimary
                                          .withOpacity(0.15),
                                    ),
                                  ),
                                  child: isSmallScreen
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // EPG Info (top in mobile)
                                            _buildInlineEpg(),
                                            const SizedBox(height: 12),
                                            const Divider(
                                              color: AppColors.onSurface06,
                                            ),
                                            const SizedBox(height: 8),
                                            // Control Buttons
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: _buildControlButtons(
                                                isSmallScreen,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            // EPG Info (left side)
                                            Expanded(
                                              child: _buildInlineEpg(),
                                            ),
                                            const SizedBox(width: 24),
                                            // Control Buttons (right side)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: _buildControlButtons(
                                                isSmallScreen,
                                              ),
                                            ),
                                          ],
                                        ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      );
    }

    // STANDARD PLAYER MODE (VOD/Series)
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isInitialized) HtmlElementView(viewType: _viewId),

          // User interaction area
          Positioned.fill(
            child: PointerInterceptor(
              child: MouseRegion(
                onHover: (_) => _onHover(),
                child: GestureDetector(
                  onTap: () {
                    if (_showControls) {
                      setState(() => _showControls = false);
                    } else {
                      _onHover();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),

          // Controls Overlay
          if (_showControls || _isLoading)
            Positioned.fill(
              child: PointerInterceptor(
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Stack(
                    children: [
                      // Top Bar
                      Positioned(
                        top: 24,
                        left: 24,
                        right: 24,
                        child: GlassContainer.glass(
                          height: 72,
                          borderRadius: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildGlassIconButton(
                                icon: Icons.arrow_back_rounded,
                                onTap: () => Navigator.pop(context),
                                tooltip: 'Retour',
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: GoogleFonts.fraunces(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Center Loading Indicator (only show when loading)
                      if (_isLoading)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                              // Un saut hors de la zone transcodée relance
                              // l'encodeur : quelques secondes d'attente,
                              // autant dire pourquoi.
                              if (_seekReloading) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Reprise à '
                                  '${_formatDuration(Duration(seconds: _currentPosition.toInt()))}…',
                                  style: GoogleFonts.karla(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Bottom Controls
                      Positioned(
                        bottom: 40,
                        left: 40,
                        right: 40,
                        child: GlassContainer.glass(
                          borderRadius: 24,
                          borderColor: AppColors.onSurface.withOpacity(0.1),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(
                                      Duration(
                                        seconds: _currentPosition.toInt(),
                                      ),
                                    ),
                                    style: GoogleFonts.karla(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 4,
                                        activeTrackColor: AppColors.primary,
                                        inactiveTrackColor:
                                            AppColors.onSurface.withOpacity(0.2),
                                        // Portion déjà transcodée : navigable
                                        // instantanément, contrairement au
                                        // reste qui redémarre l'encodeur.
                                        secondaryActiveTrackColor:
                                            AppColors.onSurface.withOpacity(0.4),
                                        thumbColor: AppColors.onSurface,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 8,
                                        ),
                                        overlayColor:
                                            AppColors.primary.withOpacity(0.2),
                                      ),
                                      child: Slider(
                                        value: _currentPosition
                                            .clamp(0.0, _totalDuration),
                                        secondaryTrackValue: _seekableEnd > 0
                                            ? _seekableEnd
                                                .clamp(0.0, _totalDuration)
                                            : null,
                                        min: 0,
                                        max: _totalDuration,
                                        onChanged: (val) => setState(
                                          () => _currentPosition = val,
                                        ),
                                        onChangeStart: (_) =>
                                            setState(() => _isSeeking = true),
                                        onChangeEnd: (val) {
                                          _seekTo(val);
                                          Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                            if (mounted) {
                                              setState(
                                                () => _isSeeking = false,
                                              );
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    _formatDuration(
                                      Duration(
                                        seconds: _totalDuration.toInt(),
                                      ),
                                    ),
                                    style: GoogleFonts.karla(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Buttons
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  // Sous 720 px, les sauts de 60 s et le
                                  // sélecteur de vitesse sortent de la barre
                                  // plutôt que de la faire déborder.
                                  final compact = constraints.maxWidth < 720;
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (!compact) ...[
                                        _buildGlassIconButton(
                                          icon: Icons.fast_rewind_rounded,
                                          onTap: () => _seekBy(-_bigStep),
                                          transparent: true,
                                          tooltip: 'Reculer de 1 min',
                                        ),
                                        const SizedBox(width: 16),
                                      ],
                                      _buildGlassIconButton(
                                        icon: Icons.replay_10_rounded,
                                        onTap: () => _seekBy(-_smallStep),
                                        transparent: true,
                                        tooltip: 'Reculer de 10 s',
                                      ),
                                      const SizedBox(width: 24),
                                      _buildGlassIconButton(
                                        icon: _isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        onTap: _togglePlayPause,
                                        size: 56,
                                        iconSize: 32,
                                        tooltip:
                                            _isPlaying ? 'Pause' : 'Lecture',
                                      ),
                                      const SizedBox(width: 24),
                                      _buildGlassIconButton(
                                        icon: Icons.forward_10_rounded,
                                        onTap: () => _seekBy(_smallStep),
                                        transparent: true,
                                        tooltip: 'Avancer de 10 s',
                                      ),
                                      if (!compact) ...[
                                        const SizedBox(width: 16),
                                        _buildGlassIconButton(
                                          icon: Icons.fast_forward_rounded,
                                          onTap: () => _seekBy(_bigStep),
                                          transparent: true,
                                          tooltip: 'Avancer de 1 min',
                                        ),
                                      ],
                                      const Spacer(),
                                      if (!compact) ...[
                                        _buildRateSelector(),
                                        const SizedBox(width: 16),
                                      ],
                                      QualitySelectorButton(
                                        current: _quality,
                                        onSelected: _changeQuality,
                                      ),
                                      const SizedBox(width: 16),
                                      _buildGlassIconButton(
                                        icon: _isMuted
                                            ? Icons.volume_off_rounded
                                            : Icons.volume_up_rounded,
                                        onTap: _toggleMute,
                                        transparent: true,
                                        tooltip: _isMuted
                                            ? 'Activer le son'
                                            : 'Couper le son',
                                      ),
                                      const SizedBox(width: 16),
                                      _buildGlassIconButton(
                                        icon: _isFullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        onTap: _toggleFullscreen,
                                        transparent: true,
                                        tooltip: _isFullscreen
                                            ? 'Quitter le plein écran'
                                            : 'Plein écran',
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  /// Sélecteur de vitesse de lecture — utile pour parcourir un
  /// enregistrement long sans sauter à l'aveugle.
  Widget _buildRateSelector() {
    return Tooltip(
      message: 'Vitesse de lecture',
      child: PopupMenuButton<double>(
        initialValue: _rate,
        onSelected: _setRate,
        color: AppColors.surfaceContainer,
        tooltip: '',
        itemBuilder: (context) => [
          for (final rate in _rates)
            PopupMenuItem<double>(
              value: rate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    rate == _rate
                        ? Icons.check_rounded
                        : Icons.speed_rounded,
                    size: 16,
                    color: rate == _rate
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatRate(rate),
                    style: TextStyle(
                      color: rate == _rate
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.onSurface.withOpacity(0.15)),
          ),
          child: Text(
            _formatRate(_rate),
            style: GoogleFonts.karla(
              color: _rate == 1.0 ? AppColors.onSurface : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// « 1× », « 1.5× » — sans décimale inutile.
  static String _formatRate(double rate) {
    final text = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toString();
    return '$text×';
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool transparent = false,
    double size = 48,
    double iconSize = 24,
    String? tooltip,
  }) {
    // Button with direct Material/InkWell - PointerInterceptor is on outer container
    final button = Material(
      color: transparent ? Colors.transparent : AppColors.onSurface.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: transparent
                ? null
                : Border.all(color: AppColors.onSurface.withOpacity(0.1)),
          ),
          child: Icon(icon, color: AppColors.onSurface, size: iconSize),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: button) : button;
  }

  List<Widget> _buildControlButtons(bool isSmallScreen) {
    final buttonSize = isSmallScreen ? 40.0 : 44.0;
    final playButtonSize = isSmallScreen ? 48.0 : 52.0;
    final spacing = isSmallScreen ? 8.0 : 16.0;

    return [
      // Previous Channel
      if (widget.channels != null && widget.channels!.length > 1)
        _buildSimpleIconButton(
          icon: Icons.skip_previous_rounded,
          onTap: _previousChannel,
          size: buttonSize,
          tooltip: 'Chaîne précédente',
        ),

      if (widget.channels != null && widget.channels!.length > 1)
        SizedBox(width: spacing),

      // Play/Pause (Large)
      _buildSimpleIconButton(
        icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        onTap: _togglePlayPause,
        size: playButtonSize,
        iconSize: isSmallScreen ? 24 : 28,
        highlighted: true,
        tooltip: _isPlaying ? 'Pause' : 'Lecture',
      ),

      if (widget.channels != null && widget.channels!.length > 1)
        SizedBox(width: spacing),

      // Next Channel
      if (widget.channels != null && widget.channels!.length > 1)
        _buildSimpleIconButton(
          icon: Icons.skip_next_rounded,
          onTap: _nextChannel,
          size: buttonSize,
          tooltip: 'Chaîne suivante',
        ),

      SizedBox(width: spacing),

      // Mute button
      _buildSimpleIconButton(
        icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        onTap: _toggleMute,
        size: buttonSize,
        tooltip: _isMuted ? 'Activer le son' : 'Couper le son',
      ),

      SizedBox(width: spacing),

      // Quality selector
      QualitySelectorButton(
        current: _quality,
        onSelected: _changeQuality,
        size: buttonSize,
      ),

      SizedBox(width: spacing),

      // Fullscreen
      _buildSimpleIconButton(
        icon: _isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        onTap: _toggleFullscreen,
        size: buttonSize,
        tooltip: _isFullscreen ? 'Quitter le plein écran' : 'Plein écran',
      ),
    ];
  }

  // Simple Icon Button for Live TV player (no BackdropFilter issues)
  Widget _buildSimpleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 48,
    double iconSize = 24,
    bool highlighted = false,
    String? tooltip,
  }) {
    final button = Material(
      color: highlighted
          ? AppColors.primary.withOpacity(0.2)
          : AppColors.onSurface.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: AppColors.primary.withOpacity(0.3),
        highlightColor: AppColors.primary.withOpacity(0.1),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted
                  ? AppColors.primary.withOpacity(0.5)
                  : AppColors.onSurface.withOpacity(0.2),
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            color: highlighted ? AppColors.primary : AppColors.onSurface,
            size: iconSize,
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: button) : button;
  }

  /// Build inline EPG info for the unified control bar
  Widget _buildInlineEpg() {
    final currentStreamId = widget.channels != null
        ? widget.channels![_currentIndex].streamId
        : widget.streamId;

    return Consumer(
      builder: (context, ref, child) {
        final epgAsync = ref.watch(
          epgByPlaylistProvider(
            EpgRequestKey(playlist: widget.playlist, streamId: currentStreamId),
          ),
        );

        return epgAsync.when(
          data: (epgEntries) {
            if (epgEntries.isEmpty) {
              // No EPG data - show channel name only
              return Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.live,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.channels != null
                          ? widget.channels![_currentIndex].name
                          : widget.title,
                      style: GoogleFonts.fraunces(
                        color: AppColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }

            // Get current program
            final now = DateTime.now();
            final currentProgram = epgEntries.firstWhere(
              (entry) {
                final start = DateTime.parse(entry.start);
                final end = DateTime.parse(entry.end);
                return now.isAfter(start) && now.isBefore(end);
              },
              orElse: () => epgEntries.first,
            );

            return Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.live,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentProgram.title,
                        style: GoogleFonts.fraunces(
                          color: AppColors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (currentProgram.description.isNotEmpty)
                        Text(
                          currentProgram.description,
                          style: GoogleFonts.karla(
                            color: AppColors.onSurface54,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.live,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.channels != null
                    ? widget.channels![_currentIndex].name
                    : widget.title,
                style: GoogleFonts.fraunces(
                  color: AppColors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          error: (_, __) => Text(
            widget.channels != null
                ? widget.channels![_currentIndex].name
                : widget.title,
            style: GoogleFonts.fraunces(
              color: AppColors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
