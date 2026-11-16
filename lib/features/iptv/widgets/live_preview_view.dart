// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/channel_logo.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'live_preview_controller.dart';
import 'live_widgets.dart';

/// The muted live picture of the Direct panel (web).
///
/// A single iframe (`name="xf-preview"`, viewType [_viewType]) whose `src`
/// follows [livePreviewProvider]. The iframe takes no pointer event: hover
/// and clicks stay with Flutter (the panel opens the full screen). Until the
/// player posts `preview_state: playing`, the channel logo is shown on top.
class LivePreviewView extends ConsumerStatefulWidget {
  const LivePreviewView({super.key, required this.channel});

  final Channel channel;

  @override
  ConsumerState<LivePreviewView> createState() => _LivePreviewViewState();
}

const _viewType = 'xf-live-preview';
bool _registered = false;
html.IFrameElement? _frame;
String _src = 'about:blank';

void _setSrc(String? url) {
  final next = url ?? 'about:blank';
  if (next == _src) return;
  _src = next;
  _frame?.src = next;
}

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    final frame = html.IFrameElement()
      ..name = 'xf-preview'
      ..src = _src
      ..tabIndex = -1
      ..allow = 'autoplay'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = 'none'
      ..style.background = 'transparent';
    _frame = frame;
    return frame;
  });
}

class _LivePreviewViewState extends ConsumerState<LivePreviewView> {
  final _subs = <StreamSubscription<dynamic>>[];
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);

  LivePreviewNotifier get _notifier => ref.read(livePreviewProvider.notifier);

  @override
  void initState() {
    super.initState();
    _register();
    _setSrc(ref.read(livePreviewProvider).url);
    final origin = html.window.location.origin;
    _subs.add(
      html.window.onMessage.listen((event) {
        if (event.origin != origin) return;
        final data = event.data;
        if (data is! Map || data['type'] != 'preview_state') return;
        final state = data['state'];
        if (state is String) _notifier.onPlayerMessage(state);
      }),
    );
    _subs.add(
      html.document.onVisibilityChange.listen((_) {
        if (html.document.hidden ?? false) _notifier.onHidden();
      }),
    );
    void activity(_) {
      final now = DateTime.now();
      if (now.difference(_lastActivity) < const Duration(seconds: 1)) return;
      _lastActivity = now;
      _notifier.onActivity();
    }

    _subs.add(html.window.onMouseMove.listen(activity));
    _subs.add(html.window.onKeyDown.listen(activity));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LivePreviewState>(
      livePreviewProvider,
      (_, next) => _setSrc(next.url),
    );
    final state = ref.watch(livePreviewProvider);
    final mine = state.streamId == widget.channel.streamId;
    final playing = mine && state.phase == PreviewPhase.playing;
    final unavailable = state.phase == PreviewPhase.unavailable;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const HtmlElementView(viewType: _viewType),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: playing ? 0 : 1,
              duration: AppTheme.durationNormal,
              curve: AppTheme.curveFocus,
              child: ColoredBox(
                color: AppColors.surface,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChannelLogo(
                      url: channelLogoUrl(
                        streamIcon: widget.channel.streamIcon,
                        name: widget.channel.name,
                      ),
                      name: widget.channel.name,
                      width: 160,
                      height: 100,
                      radius: 12,
                    ),
                    if (unavailable) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Aperçu indisponible',
                        style: AppTheme.body(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
