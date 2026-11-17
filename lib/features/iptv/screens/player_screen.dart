import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';

import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../providers/xtream_provider.dart';
import '../providers/playback_positions_provider.dart';
import '../utils/epg_now.dart';
import '../widgets/live_widgets.dart';
import '../widgets/player_osd.dart';
import '../widgets/quality_selector_widget.dart';

import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

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
  late final String _viewIdPrefix = DateTime.now().millisecondsSinceEpoch
      .toString();
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
    _fullscreenSubscription = html.document.onFullscreenChange.listen(
      (_) => _syncFullscreenState(),
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _fullscreenSubscription?.cancel();
    _controlsTimer?.cancel();
    _keysScope.dispose();
    _listScope.dispose();
    _listCurrentFocus.dispose();
    _listScroll.dispose();
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
        final base =
            '${service.backendBaseUrl}/api/recordings/stream/'
            '$currentStreamId/playlist.m3u8';
        streamUrl = _mediaOffset > 0
            ? '$base?start=${_mediaOffset.toInt()}'
            : base;
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

      final streamTypeParam = widget.streamType == StreamType.live
          ? 'live'
          : 'vod';
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
        final seekableEnd = rawSeekable is num
            ? rawSeekable.toDouble()
            : currentTime;

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
          ref
              .read(playbackPositionsProvider.notifier)
              .savePosition(_positionKey, currentTime, duration);
        }
      } else if (type == 'seek_out_of_range') {
        // Cible hors de la zone déjà transcodée : seul un redémarrage du
        // flux à cet instant peut la servir.
        final target = (data['value'] as num?)?.toDouble();
        if (target != null) _restartAt(target);
      } else if (type == 'playback_ended') {
        setState(() => _isPlaying = false);
        ref
            .read(playbackPositionsProvider.notifier)
            .clearPosition(_positionKey);
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
        // L'aperçu du Direct (name="xf-preview") n'est jamais la cible.
        if (frame is html.IFrameElement &&
            frame.name != 'xf-preview' &&
            (frame.src?.contains('player_lite.html') == true ||
                frame.src?.contains('player.html') == true ||
                frame.src?.contains('player_mobile.html') == true)) {
          iframe = frame;
          break;
        }
      }
    }

    if (iframe != null) {
      iframe.contentWindow?.postMessage(message, html.window.location.origin);
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
    final ceiling = _totalDuration > 10 ? _totalDuration - 5 : _totalDuration;
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
    Future.delayed(const Duration(milliseconds: 150), _syncFullscreenState);
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
    final resumeAt = widget.streamType == StreamType.live
        ? null
        : _currentPosition;
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

  // ─── Overlay (plates « Salle obscure », see widgets/player_osd.dart) ──────────

  /// Chaînes du direct, typées : la liste reçue est `List<dynamic>` (elle
  /// porte aussi des films côté mobile), seule une vraie liste de chaînes
  /// alimente la liste latérale et la plaque du direct.
  late final List<Channel>? _channelList = _asChannels(widget.channels);

  static List<Channel>? _asChannels(List<dynamic>? list) {
    if (list == null || list.isEmpty) return null;
    if (list is List<Channel>) return list;
    if (list.every((c) => c is Channel)) return list.cast<Channel>();
    return null;
  }

  Channel? get _currentChannel {
    final list = _channelList;
    if (list == null || _currentIndex < 0 || _currentIndex >= list.length) {
      return null;
    }
    return list[_currentIndex];
  }

  /// Portée de focus du lecteur : reçoit tous les raccourcis clavier. Quand
  /// un bouton d'une plaque disparaît (plaques masquées), le focus revient
  /// ici et les raccourcis continuent de s'appliquer.
  final FocusScopeNode _keysScope = FocusScopeNode(debugLabel: 'player-keys');

  /// Liste des chaînes (à droite), ouverte par « Chaînes » ou la touche C.
  bool _channelListOpen = false;
  final FocusScopeNode _listScope = FocusScopeNode(debugLabel: 'player-list');
  final FocusNode _listCurrentFocus = FocusNode(debugLabel: 'player-list-cur');
  final ScrollController _listScroll = ScrollController();

  static const double _listWidth = 300;

  bool get _canListChannels =>
      widget.streamType == StreamType.live && _channelList != null;

  /// Raccourcis : ceux de [_onKeyEvent], inchangés, plus la liste des
  /// chaînes. Liste ouverte : ↑/↓ déplacent le focus dans la liste (pas de
  /// zap), Entrée zappe sur la chaîne choisie (la ligne focalisée la gère),
  /// Échap ferme la liste seulement.
  KeyEventResult _onPlayerKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_channelListOpen && event is! KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _moveInChannelList(down: key == LogicalKeyboardKey.arrowDown);
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent) {
        if (key == LogicalKeyboardKey.escape) {
          _closeChannelList();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.select) {
          // Une ligne focalisée traite Entrée elle-même ; ici aucune ne
          // l'a : on la place sur la chaîne en cours.
          _focusCurrentListRow();
          return KeyEventResult.handled;
        }
      }
    }
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.keyC &&
        _canListChannels) {
      _toggleChannelList();
      return KeyEventResult.handled;
    }
    return _onKeyEvent(node, event);
  }

  void _toggleChannelList() {
    if (_channelListOpen) {
      _closeChannelList();
      return;
    }
    setState(() => _channelListOpen = true);
    _onHover();
    // Premier temps : faire défiler jusqu'à la chaîne en cours ; second
    // temps : lui donner le focus, une fois sa ligne construite.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_channelListOpen) return;
      if (_listScroll.hasClients) {
        final position = _listScroll.position;
        final offset =
            _currentIndex * ChannelListPlate.itemExtent -
            position.viewportDimension / 2 +
            ChannelListPlate.itemExtent / 2;
        _listScroll.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusCurrentListRow(),
      );
    });
  }

  void _closeChannelList() {
    if (!_channelListOpen) return;
    // Rendre le focus à la portée du lecteur avant de retirer la liste.
    if (_listScope.hasFocus) {
      _listScope.unfocus(disposition: UnfocusDisposition.scope);
    }
    setState(() => _channelListOpen = false);
    _onHover();
  }

  void _focusCurrentListRow() {
    if (!mounted || !_channelListOpen) return;
    _listCurrentFocus.requestFocus();
  }

  void _moveInChannelList({required bool down}) {
    _onHover();
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary == _listScope || !_listScope.hasFocus) {
      _focusCurrentListRow();
      return;
    }
    primary.focusInDirection(
      down ? TraversalDirection.down : TraversalDirection.up,
    );
  }

  /// Zap depuis la liste : même chemin que [_previousChannel] /
  /// [_nextChannel] (index courant, puis relance du flux).
  void _selectChannel(int index) {
    _onHover();
    final list = _channelList;
    if (list == null || index < 0 || index >= list.length) return;
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _initializePlayer(isChannelSwitch: true);
    // La ligne de la chaîne en cours change de clé : y remettre le focus.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCurrentListRow());
  }

  /// Le pointeur quitte une plaque : le bouton survolé rend le focus au
  /// lecteur, pour qu'Espace / Entrée restent lecture / pause.
  void _releasePlateFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary == _keysScope) return;
    if (primary.enclosingScope != _keysScope) return;
    primary.unfocus(disposition: UnfocusDisposition.scope);
  }

  @override
  Widget build(BuildContext context) {
    final isLiveTV = widget.streamType == StreamType.live;
    final size = MediaQuery.sizeOf(context);
    final side = size.width < 700 ? 16.0 : 48.0;
    final bottom = size.width < 700 ? 16.0 : 32.0;
    final listOpen = _channelListOpen && _canListChannels;
    final listWidth = size.width - 2 * side < _listWidth + 200
        ? size.width - 2 * side
        : _listWidth;
    // La liste et la plaque se partagent le bas de l'écran.
    final plateRight = listOpen && size.width >= 900
        ? side + listWidth + 16
        : side;

    return FocusScope(
      node: _keysScope,
      autofocus: true,
      onKeyEvent: _onPlayerKey,
      child: Scaffold(
        backgroundColor: isLiveTV ? AppColors.background : Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video Player
            if (_isInitialized) HtmlElementView(viewType: _viewId),

            // Control overlay: catches every pointer event over the iframe
            // so that hover and clicks reach Flutter.
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
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(color: Colors.transparent),
                        ),

                        // Loading (VOD / séries / enregistrements).
                        if (!isLiveTV && _isLoading)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const OsdSpinner(size: 32),
                                // Un saut hors de la zone transcodée relance
                                // l'encodeur : quelques secondes d'attente,
                                // autant dire pourquoi.
                                if (_seekReloading) ...[
                                  const SizedBox(height: 16),
                                  PlayerToast(
                                    text:
                                        'Reprise à '
                                        '${formatPlayerTime(Duration(seconds: _currentPosition.toInt()))}…',
                                  ),
                                ],
                              ],
                            ),
                          ),

                        // Bottom plate.
                        if (_showControls)
                          Positioned(
                            left: side,
                            right: plateRight,
                            bottom: bottom,
                            child: MouseRegion(
                              onExit: (_) => _releasePlateFocus(),
                              child: GestureDetector(
                                // A click on the plate itself must not hide
                                // the controls.
                                behavior: HitTestBehavior.opaque,
                                onTap: _onHover,
                                child: isLiveTV
                                    ? _buildLivePlate()
                                    : _buildVodPlate(),
                              ),
                            ),
                          ),

                        // Channel list (live), on the right.
                        if (listOpen)
                          Positioned(
                            top: bottom,
                            bottom: bottom,
                            right: side,
                            width: listWidth,
                            child: GestureDetector(
                              // A click on the list's header must not close
                              // the controls.
                              behavior: HitTestBehavior.opaque,
                              onTap: _onHover,
                              child: FocusScope(
                                node: _listScope,
                                child: ChannelListPlate(
                                  playlist: widget.playlist,
                                  channels: _channelList!,
                                  currentIndex: _currentIndex,
                                  currentFocusNode: _listCurrentFocus,
                                  controller: _listScroll,
                                  onSelect: _selectChannel,
                                  onActivity: _onHover,
                                ),
                              ),
                            ),
                          ),
                      ],
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

  /// Buttons separated by 10 px: the lit halo stays clear of its neighbours.
  static List<Widget> _spaced(List<Widget> items) => [
    for (var i = 0; i < items.length; i++) ...[
      if (i > 0) const SizedBox(width: 10),
      items[i],
    ],
  ];

  /// Gap between two groups of buttons.
  static const Widget _groupGap = SizedBox(width: 18);

  Widget _backButton() => OsdButton(
    key: const ValueKey('osd-back'),
    icon: Icons.arrow_back_rounded,
    label: 'Retour',
    onPressed: () => Navigator.pop(context),
    onFocus: _onHover,
  );

  Widget _playPauseButton() => OsdButton(
    key: const ValueKey('osd-play'),
    icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
    label: _isPlaying ? 'Pause' : 'Lecture',
    onPressed: _togglePlayPause,
    onFocus: _onHover,
    iconSize: 22,
  );

  Widget _muteButton() => OsdButton(
    key: const ValueKey('osd-mute'),
    icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
    label: _isMuted ? 'Son · coupé' : 'Son',
    onPressed: _toggleMute,
    onFocus: _onHover,
  );

  Widget _fullscreenButton() => OsdButton(
    key: const ValueKey('osd-fullscreen'),
    icon: _isFullscreen
        ? Icons.fullscreen_exit_rounded
        : Icons.fullscreen_rounded,
    label: _isFullscreen ? 'Quitter le plein écran' : 'Plein écran',
    onPressed: _toggleFullscreen,
    onFocus: _onHover,
    iconSize: 22,
  );

  Widget _qualityButton() => QualitySelectorButton(
    current: _quality,
    onSelected: _changeQuality,
    size: 40,
  );

  /// Direct : logo, nom, programme, ligne rouge, « À suivre » et boutons.
  Widget _buildLivePlate() {
    final channel = _currentChannel;
    final streamId = channel?.streamId ?? widget.streamId;
    final hasZap = widget.channels != null && widget.channels!.length > 1;
    return Consumer(
      builder: (context, ref, _) {
        final entries = ref
            .watch(
              epgByPlaylistProvider(
                EpgRequestKey(playlist: widget.playlist, streamId: streamId),
              ),
            )
            .valueOrNull;
        final now = DateTime.now();
        final epg = entries == null ? EpgNow.empty : epgNow(entries, now);
        final info = LiveOsdInfo.fromEpg(
          number: channel == null ? '' : '${_currentIndex + 1}',
          name: channel?.name ?? widget.title,
          logoUrl: channel == null ? '' : logoOf(channel),
          epg: epg,
          now: now,
          connecting: _isLoading,
        );
        return LivePlate(
          info: info,
          actions: LayoutBuilder(
            builder: (context, box) {
              final roomy = box.maxWidth >= 640;
              // Très étroit (téléphone) : le retour système suffit.
              final narrow = box.maxWidth < 420;
              return Row(
                children: [
                  ..._spaced([
                    if (!narrow) _backButton(),
                    if (roomy && hasZap)
                      OsdButton(
                        key: const ValueKey('osd-prev'),
                        icon: Icons.skip_previous_rounded,
                        label: 'Chaîne précédente',
                        onPressed: _previousChannel,
                        onFocus: _onHover,
                        iconSize: 22,
                      ),
                    _playPauseButton(),
                    if (roomy && hasZap)
                      OsdButton(
                        key: const ValueKey('osd-next'),
                        icon: Icons.skip_next_rounded,
                        label: 'Chaîne suivante',
                        onPressed: _nextChannel,
                        onFocus: _onHover,
                        iconSize: 22,
                      ),
                  ]),
                  _groupGap,
                  ..._spaced([
                    if (_canListChannels)
                      OsdButton(
                        key: const ValueKey('osd-channels'),
                        icon: Icons.playlist_play_rounded,
                        label: _channelListOpen
                            ? 'Chaînes · ouvertes'
                            : 'Chaînes',
                        onPressed: _toggleChannelList,
                        onFocus: _onHover,
                        iconSize: 22,
                      ),
                    _muteButton(),
                    _qualityButton(),
                    _fullscreenButton(),
                  ]),
                  Expanded(
                    child:
                        !roomy ||
                            info.nextTime == null ||
                            info.nextTitle == null
                        ? const SizedBox.shrink()
                        : OsdUpNext(
                            time: info.nextTime!,
                            title: info.nextTitle!,
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Films, séries, enregistrements : titre, barre (position, durée, plage
  /// navigable), boutons.
  Widget _buildVodPlate() {
    Duration seconds(double s) =>
        Duration(milliseconds: s.isFinite && s > 0 ? (s * 1000).round() : 0);
    // 1 = durée encore inconnue (valeur initiale de [_totalDuration]).
    final known = _totalDuration > 1;
    final progress = VodProgress(
      position: seconds(_currentPosition),
      duration: known ? seconds(_totalDuration) : Duration.zero,
      buffer: known ? seconds(_seekableEnd) : Duration.zero,
    );
    // Maj enfoncée : sauts de 60 s, comme au clavier.
    double step() =>
        HardwareKeyboard.instance.isShiftPressed ? _bigStep : _smallStep;
    return VodPlate(
      title: widget.title,
      progress: progress,
      onSeekStart: _onHover,
      onSeek: (fraction) {
        setState(() => _isSeeking = true);
        _seekTo(_totalDuration * fraction);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _isSeeking = false);
        });
      },
      actions: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxWidth >= 600;
          final narrow = box.maxWidth < 420;
          return Row(
            children: [
              ..._spaced([
                if (!narrow) _backButton(),
                OsdButton(
                  key: const ValueKey('osd-back10'),
                  icon: Icons.replay_10_rounded,
                  label: '−10 s',
                  onPressed: () => _seekBy(-step()),
                  onFocus: _onHover,
                  iconSize: 22,
                ),
                _playPauseButton(),
                OsdButton(
                  key: const ValueKey('osd-fwd10'),
                  icon: Icons.forward_10_rounded,
                  label: '+10 s',
                  onPressed: () => _seekBy(step()),
                  onFocus: _onHover,
                  iconSize: 22,
                ),
              ]),
              const Spacer(),
              ..._spaced([
                if (roomy) _buildRateSelector(),
                _qualityButton(),
                _muteButton(),
                _fullscreenButton(),
              ]),
            ],
          );
        },
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
                    rate == _rate ? Icons.check_rounded : Icons.speed_rounded,
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
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: OsdColors.button,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_rounded,
                size: 18,
                color: _rate == 1.0 ? AppColors.textPrimary : AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                _formatRate(_rate),
                style: AppTheme.body(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _rate == 1.0
                      ? AppColors.textPrimary
                      : AppColors.accent,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ],
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
}
