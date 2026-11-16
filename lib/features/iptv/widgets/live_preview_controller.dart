import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State machine of the muted live preview of the Direct tab.
///
/// Pure Dart on purpose (no `dart:html`): it runs in `flutter test` on the
/// VM. The view (`live_preview_view.dart`) only shows [LivePreviewState.url]
/// in its iframe and forwards the browser events here.
///
/// One preview at a time: a single iframe whose `src` follows [url]. While a
/// new channel waits ([dwell]), the iframe is blank, so the previous upstream
/// connection is released before the next one is asked for (the server marks
/// preview connections as always yieldable, `turbo.ts?preview=1`).
enum PreviewPhase {
  /// Nothing shown (the iframe is blank).
  idle,

  /// A channel was reached; waiting [LivePreviewNotifier.dwell] before
  /// loading it, so that running down a list opens nothing.
  waiting,

  /// The player is loading; no picture yet.
  loading,

  /// Picture on screen.
  playing,

  /// The last attempt failed: no preview for [LivePreviewNotifier.cooldown],
  /// so as not to pile up refusals at the provider.
  unavailable,
}

class LivePreviewState {
  const LivePreviewState(this.phase, {this.streamId, this.url});

  static const idle = LivePreviewState(PreviewPhase.idle);

  final PreviewPhase phase;
  final String? streamId;

  /// Address of the iframe, `null` = `about:blank`.
  final String? url;

  @override
  String toString() => 'LivePreviewState($phase, $streamId, $url)';
}

class LivePreviewNotifier extends Notifier<LivePreviewState> {
  /// Time on a channel before its preview loads.
  static Duration dwell = const Duration(milliseconds: 350);

  /// No picture after this: the preview is given up.
  static Duration loadTimeout = const Duration(seconds: 10);

  /// No new attempt for this long after a failure.
  static Duration cooldown = const Duration(seconds: 60);

  /// No mouse or key for this long: the preview stops, so a forgotten tab
  /// does not hold the account's only connection.
  static Duration idleStop = const Duration(minutes: 3);

  Timer? _dwellTimer, _loadTimer, _cooldownTimer, _idleTimer;
  bool _enabled = true;

  @override
  LivePreviewState build() {
    ref.onDispose(_cancelAll);
    return LivePreviewState.idle;
  }

  /// URL of the preview player for the `turbo.ts` address [tsUrl].
  static String previewUrl(String tsUrl) {
    final ts = '$tsUrl${tsUrl.contains('?') ? '&' : '?'}preview=1';
    return 'player_lite.html?url=${Uri.encodeComponent(ts)}'
        '&type=live&turbo=true&preview=1';
  }

  /// The user reached a channel (hover or keyboard focus).
  void request(String streamId, String tsUrl) {
    if (!_enabled) return;
    final s = state;
    if (s.phase == PreviewPhase.unavailable) return;
    if (s.streamId == streamId && s.phase != PreviewPhase.idle) return;
    _dwellTimer?.cancel();
    _loadTimer?.cancel();
    state = LivePreviewState(PreviewPhase.waiting, streamId: streamId);
    _armIdle();
    _dwellTimer = Timer(dwell, () => _load(streamId, tsUrl));
  }

  void _load(String streamId, String tsUrl) {
    state = LivePreviewState(
      PreviewPhase.loading,
      streamId: streamId,
      url: previewUrl(tsUrl),
    );
    _loadTimer = Timer(loadTimeout, _fail);
  }

  /// `preview_state` posted by the player: `playing` or `error`.
  void onPlayerMessage(String playerState) {
    final phase = state.phase;
    if (playerState == 'playing') {
      if (phase != PreviewPhase.loading) return;
      _loadTimer?.cancel();
      state = LivePreviewState(
        PreviewPhase.playing,
        streamId: state.streamId,
        url: state.url,
      );
    } else if (playerState == 'error') {
      if (phase == PreviewPhase.loading || phase == PreviewPhase.playing) {
        _fail();
      }
    }
  }

  void _fail() {
    _dwellTimer?.cancel();
    _loadTimer?.cancel();
    _idleTimer?.cancel();
    state = LivePreviewState(
      PreviewPhase.unavailable,
      streamId: state.streamId,
    );
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(cooldown, () {
      if (state.phase == PreviewPhase.unavailable) {
        state = LivePreviewState.idle;
      }
    });
  }

  /// Leaving the Direct tab, the channel list, or opening the full screen.
  void stop() {
    _dwellTimer?.cancel();
    _loadTimer?.cancel();
    _idleTimer?.cancel();
    // A failure keeps its cooldown.
    if (state.phase == PreviewPhase.unavailable) return;
    if (state.phase != PreviewPhase.idle) state = LivePreviewState.idle;
  }

  /// The browser tab was hidden. No automatic restart when it shows again:
  /// the next hover or key makes a new [request].
  void onHidden() => stop();

  /// Mouse moved or key pressed: the [idleStop] countdown starts again.
  void onActivity() {
    if (_idleTimer != null && _idleTimer!.isActive) _armIdle();
  }

  /// Follows the « Aperçu vidéo dans le Direct » setting.
  void setEnabled(bool enabled) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    if (!enabled) stop();
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleStop, stop);
  }

  void _cancelAll() {
    _dwellTimer?.cancel();
    _loadTimer?.cancel();
    _cooldownTimer?.cancel();
    _idleTimer?.cancel();
  }
}

final livePreviewProvider =
    NotifierProvider<LivePreviewNotifier, LivePreviewState>(
      LivePreviewNotifier.new,
    );
