import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/utils/group_label.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../utils/epg_now.dart';
import 'live_widgets.dart';

/// The player's on-screen display, « compact » version, after xtremobile's
/// `player_osd.dart` (TV layout), adapted to the web: the data come from the
/// `PlayerScreen` state (fed by the iframe's `postMessage`), the mouse and the
/// keyboard share the focus ([TVFocusable]: hovering focuses).
///
/// The video comes first: no veil over the picture. Every state is a compact
/// plate anchored at the bottom, a dark fill at 88 % with a hairline edge
/// (one draw, no gradient, no blur), so the text stays readable without
/// darkening the picture. Buttons rest as 40 px icons; the focused one lights
/// up (the app's lit card) and shows its label.
///
/// The video redraws the screen on every frame, so nothing here blurs, casts a
/// shadow, clips with a path or fades with `Opacity`. Each plate sits in its
/// own [RepaintBoundary].

// ─── Colours and helpers ───────────────────────────────────────────────────────

class OsdColors {
  OsdColors._();

  /// Plate: rgba(15, 16, 20, .88).
  static const Color plate = Color(0xE00F1014);

  /// Hairline around a plate: white at 10 %.
  static const Color plateEdge = Color(0x1AFFFFFF);

  /// Opaque panel (toast).
  static const Color panel = Color(0xFF0F1014);

  /// Resting icon button: white at 8 %.
  static const Color button = Color(0x14FFFFFF);
  static const Color separator = Color(0x24FFFFFF);

  /// Progress track (white 24 %) and the part already loaded (white 22 %).
  static const Color track = Color(0x3DFFFFFF);
  static const Color buffered = Color(0x38FFFFFF);
}

/// `38:12`, `1:02:05`: hours only past an hour.
String formatPlayerTime(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// `21:52`.
String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ─── Building blocks ───────────────────────────────────────────────────────────

/// The plate: dark fill at 88 %, hairline edge, radius 14.
class OsdPlate extends StatelessWidget {
  const OsdPlate({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 14,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: OsdColors.plate,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: OsdColors.plateEdge),
        ),
        child: child,
      ),
    );
  }
}

/// Button of a plate: a 40 px icon at rest; focused (keyboard or hover), the
/// lit card with its label (« Plein écran »). [alwaysLabel] for real choices
/// (error).
class OsdButton extends StatelessWidget {
  const OsdButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.focusNode,
    this.onFocus,
    this.autofocus = false,
    this.alwaysLabel = false,
    this.iconSize = 20,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final bool autofocus;
  final bool alwaysLabel;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      focusNode: focusNode,
      onFocus: onFocus,
      autofocus: autofocus,
      onPressed: onPressed,
      paintsOwnFocus: true,
      scale: 1.06,
      borderRadius: BorderRadius.circular(12),
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final showLabel = alwaysLabel || lit;
          final ink = lit ? AppColors.onFocus : AppColors.textPrimary;
          return Semantics(
            button: true,
            label: label,
            child: Container(
              height: 40,
              constraints: const BoxConstraints(minWidth: 40),
              padding: showLabel
                  ? const EdgeInsets.fromLTRB(11, 0, 14, 0)
                  : EdgeInsets.zero,
              decoration: lit
                  ? const GlassDecoration(lit: 1, radius: 12)
                  : BoxDecoration(
                      color: OsdColors.button,
                      borderRadius: BorderRadius.circular(12),
                    ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: iconSize, color: ink),
                  if (showLabel) ...[
                    const SizedBox(width: 8),
                    Text(
                      label,
                      maxLines: 1,
                      style: AppTheme.body(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: ink,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small spinner (connection, reconnection).
class OsdSpinner extends StatelessWidget {
  const OsdSpinner({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(
      strokeWidth: 2.5,
      color: AppColors.textPrimary,
      backgroundColor: Color(0x29FFFFFF),
    ),
  );
}

/// A progress line drawn in one paint: track, loaded part, played part and an
/// optional knob (lit with the blue halo when the bar has the focus).
class OsdBar extends StatelessWidget {
  const OsdBar({
    super.key,
    required this.progress,
    this.buffered,
    this.height = 3,
    this.color = AppColors.live,
    this.trackColor = OsdColors.track,
    this.knob = 0,
    this.knobLit = false,
    this.knobColor = AppColors.textPrimary,
  });

  final double progress;
  final double? buffered;
  final double height;
  final Color color;
  final Color trackColor;
  final double knob;
  final bool knobLit;
  final Color knobColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: knob > height ? knob : height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(
          progress: progress.isFinite ? progress.clamp(0.0, 1.0) : 0,
          buffered: buffered == null || !buffered!.isFinite
              ? null
              : buffered!.clamp(0.0, 1.0),
          height: height,
          color: color,
          trackColor: trackColor,
          knob: knob,
          knobLit: knobLit,
          knobColor: knobColor,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.progress,
    required this.buffered,
    required this.height,
    required this.color,
    required this.trackColor,
    required this.knob,
    required this.knobLit,
    required this.knobColor,
  });

  final double progress;
  final double? buffered;
  final double height;
  final Color color;
  final Color trackColor;
  final double knob;
  final bool knobLit;
  final Color knobColor;

  static const _halo = [(2.0, .55), (5.0, .25), (8.0, .08)];

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final r = Radius.circular(height / 2);
    RRect bar(double to) => RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - height / 2, size.width * to, height),
      r,
    );
    canvas.drawRRect(bar(1), Paint()..color = trackColor);
    final b = buffered;
    if (b != null && b > progress) {
      canvas.drawRRect(bar(b), Paint()..color = OsdColors.buffered);
    }
    if (progress > 0) canvas.drawRRect(bar(progress), Paint()..color = color);
    if (knob <= 0) return;
    final c = Offset(size.width * progress, cy);
    if (knobLit) {
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (final (out, alpha) in _halo) {
        halo.color = AppColors.accentStrong.withValues(alpha: alpha);
        canvas.drawCircle(c, knob / 2 + out - 1.5, halo);
      }
      canvas.drawCircle(c, knob / 2, Paint()..color = AppColors.focusTop);
      canvas.drawCircle(
        c,
        knob / 2 - .6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xCC8FCFFF),
      );
    } else {
      canvas.drawCircle(c, knob / 2, Paint()..color = knobColor);
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.progress != progress ||
      o.buffered != buffered ||
      o.height != height ||
      o.color != color ||
      o.trackColor != trackColor ||
      o.knob != knob ||
      o.knobLit != knobLit ||
      o.knobColor != knobColor;
}

// ─── Live ──────────────────────────────────────────────────────────────────────

/// What the live plate shows.
@immutable
class LiveOsdInfo {
  const LiveOsdInfo({
    required this.number,
    required this.name,
    required this.logoUrl,
    required this.clock,
    this.programme,
    this.timeRange,
    this.remaining,
    this.progress,
    this.connecting = false,
    this.nextTime,
    this.nextTitle,
  });

  final String number;
  final String name;
  final String logoUrl;
  final String clock;
  final String? programme;

  /// `21:00 – 22:55`.
  final String? timeRange;

  /// `encore 1 h 03`.
  final String? remaining;
  final double? progress;

  /// « Connexion… » in place of the clock.
  final bool connecting;

  /// « À suivre 22:55 Champions Club ».
  final String? nextTime;
  final String? nextTitle;

  /// Built from what is on now on the channel ([epgNow]).
  factory LiveOsdInfo.fromEpg({
    required String number,
    required String name,
    required String logoUrl,
    required EpgNow epg,
    required DateTime now,
    bool connecting = false,
  }) {
    final title = epg.current?.title.trim() ?? '';
    final hasProgramme = title.isNotEmpty;
    final nextTitle = epg.next?.title.trim() ?? '';
    final nextTime = epg.nextStart;
    return LiveOsdInfo(
      number: number,
      name: name,
      logoUrl: logoUrl,
      clock: formatClock(now),
      connecting: connecting,
      programme: hasProgramme ? title : null,
      timeRange: hasProgramme ? epg.timeRange : null,
      remaining: hasProgramme ? epg.remainingText : null,
      progress: hasProgramme ? epg.progress : null,
      nextTime: nextTitle.isEmpty ? null : nextTime,
      nextTitle: nextTitle.isEmpty || nextTime == null ? null : nextTitle,
    );
  }
}

/// Live plate: logo, number, full name, clock; programme, times; red line.
/// With [actions] it grows upwards with the row of buttons.
class LivePlate extends StatelessWidget {
  const LivePlate({super.key, required this.info, this.actions});

  final LiveOsdInfo info;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final wide = actions != null;
    final times = info.timeRange == null
        ? null
        : wide && info.remaining != null
        ? '${info.timeRange} · ${info.remaining}'
        : info.timeRange;
    return OsdPlate(
      padding: EdgeInsets.fromLTRB(10, 10, 16, wide ? 12 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChannelLogo(
                url: info.logoUrl,
                name: info.name,
                width: 72,
                height: 48,
                radius: 8,
                inset: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (info.number.isNotEmpty) ...[
                          Text(
                            info.number,
                            style: AppTheme.body(
                              fontSize: 17,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            info.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 19,
                              height: 1.16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (info.connecting)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const OsdSpinner(),
                              const SizedBox(width: 8),
                              Text(
                                'Connexion…',
                                style: AppTheme.body(
                                  fontSize: 15,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            info.clock,
                            style: AppTheme.body(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            info.programme ?? 'Pas d\'infos sur le programme',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 16,
                              height: 1.3,
                              color: info.programme == null
                                  ? AppColors.textMuted
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (times != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            times,
                            style: AppTheme.body(
                              fontSize: 15,
                              color: AppColors.textMuted,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    OsdBar(progress: info.progress ?? 0),
                  ],
                ),
              ),
            ],
          ),
          if (actions != null) ...[const SizedBox(height: 12), actions!],
        ],
      ),
    );
  }
}

/// « À suivre  22:55  Champions Club », right of the row of buttons.
class OsdUpNext extends StatelessWidget {
  const OsdUpNext({super.key, required this.time, required this.title});
  final String time;
  final String title;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.body(fontSize: 15, color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Text.rich(
        TextSpan(
          style: muted,
          children: [
            const TextSpan(text: 'À suivre  '),
            TextSpan(
              text: time,
              style: muted.copyWith(
                color: AppColors.textSecondary,
                fontFeatures: AppTheme.tabular,
              ),
            ),
            TextSpan(text: '  $title'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
      ),
    );
  }
}

/// The channel list: a floating plate on the right, the current channel
/// marked in blue, full names on up to two lines. One row every 64 px.
class ChannelListPlate extends StatelessWidget {
  const ChannelListPlate({
    super.key,
    required this.playlist,
    required this.channels,
    required this.currentIndex,
    required this.currentFocusNode,
    required this.controller,
    required this.onSelect,
    required this.onActivity,
  });

  static const double itemExtent = 64;

  final PlaylistConfig playlist;
  final List<Channel> channels;
  final int currentIndex;
  final FocusNode currentFocusNode;
  final ScrollController controller;
  final ValueChanged<int> onSelect;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    final current = channels[currentIndex.clamp(0, channels.length - 1)];
    final group = current.categoryName.trim().isEmpty
        ? null
        : GroupLabel.parse(current.categoryName);
    final groupMeta = group?.meta(channelCount: channels.length);
    final meta = groupMeta != null && groupMeta.isNotEmpty
        ? groupMeta
        : (channels.length == 1 ? '1 chaîne' : '${channels.length} chaînes');
    return OsdPlate(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    group?.name ?? 'Chaînes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      fontSize: 18,
                      height: 1.33,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  meta,
                  style: AppTheme.body(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                onActivity();
                return false;
              },
              child: ListView.builder(
                controller: controller,
                padding: EdgeInsets.zero,
                itemCount: channels.length,
                itemExtent: itemExtent,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentIndex;
                  return ChannelListRow(
                    // The external focus node only sits on the current
                    // channel; the key remounts the row when that changes
                    // (TVFocusable does not handle didUpdateWidget).
                    key: ValueKey('sidebar-ch-$index-$isCurrent'),
                    playlist: playlist,
                    channel: channels[index],
                    number: '${index + 1}',
                    isCurrent: isCurrent,
                    focusNode: isCurrent ? currentFocusNode : null,
                    onFocus: onActivity,
                    onPressed: () => onSelect(index),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of [ChannelListPlate]: number, logo, name (2 lines at most),
/// programme on now and its red line. Lit when focused, no halo.
class ChannelListRow extends ConsumerWidget {
  const ChannelListRow({
    super.key,
    required this.playlist,
    required this.channel,
    required this.number,
    required this.isCurrent,
    required this.onPressed,
    this.focusNode,
    this.onFocus,
  });

  final PlaylistConfig playlist;
  final Channel channel;
  final String number;
  final bool isCurrent;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = watchEpgNow(ref, playlist, channel);
    final title = now.current?.title.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TVFocusable(
        focusNode: focusNode,
        paintsOwnFocus: true,
        scale: 1.0,
        borderRadius: BorderRadius.circular(10),
        onFocus: onFocus,
        onPressed: onPressed,
        child: Builder(
          builder: (context) {
            final lit = TVFocusable.isFocused(context);
            final primary = lit ? AppColors.onFocus : AppColors.textPrimary;
            final secondary = lit
                ? AppColors.onFocusMuted
                : AppColors.textSecondary;
            final numberColor = isCurrent
                ? (lit ? AppColors.accentOnLight : AppColors.accent)
                : (lit ? AppColors.onFocusMuted : AppColors.textMuted);
            return DecoratedBox(
              decoration: GlassDecoration(
                lit: lit ? 1 : 0,
                radius: 10,
                bare: true,
                halo: false,
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            number,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: AppTheme.body(
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: numberColor,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ChannelLogo(
                          url: logoOf(channel),
                          name: channel.name,
                          width: 40,
                          height: 27,
                          radius: 6,
                          inset: true,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                channel.name,
                                maxLines: title.isEmpty ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.body(
                                  fontSize: 15,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                  color: primary,
                                ),
                              ),
                              if (title.isNotEmpty) ...[
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.body(
                                    fontSize: 13,
                                    height: 1.23,
                                    color: secondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                OsdBar(
                                  progress: now.progress ?? 0,
                                  height: 2,
                                  color: lit
                                      ? AppColors.liveOnLight
                                      : AppColors.live,
                                  trackColor: lit
                                      ? AppColors.focusTrack
                                      : OsdColors.track,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrent)
                    Positioned(
                      left: 0,
                      top: 19,
                      child: Container(
                        width: 3,
                        height: 24,
                        decoration: BoxDecoration(
                          color: lit
                              ? AppColors.accentOnLight
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── VOD ───────────────────────────────────────────────────────────────────────

/// Position of a film, as last reported by the player iframe.
@immutable
class VodProgress {
  const VodProgress({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
  });

  final Duration position;
  final Duration duration;

  /// Absolute position up to which the stream can be reached at once (for a
  /// recording: what is already transcoded).
  final Duration buffer;

  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : position.inMilliseconds / duration.inMilliseconds;

  double get bufferedFraction => duration.inMilliseconds <= 0
      ? 0
      : buffer.inMilliseconds / duration.inMilliseconds;

  Duration get remaining => duration - position;

  /// « fin à 22:44 », or null without a duration.
  String? endsAt([DateTime? now]) => duration <= Duration.zero
      ? null
      : 'fin à ${formatClock((now ?? DateTime.now()).add(remaining))}';

  @override
  bool operator ==(Object other) =>
      other is VodProgress &&
      other.position == position &&
      other.duration == duration &&
      other.buffer == buffer;

  @override
  int get hashCode => Object.hash(position, duration, buffer);
}

/// VOD plate: title and subtitle, « fin à 22:44 »; time, bar, time left.
/// [barLit]: the bar has the keyboard focus (6 px, lit knob). [onSeek]: the
/// bar answers the mouse (click or drag, one seek on release) with the
/// fraction aimed at. [actions]: the row of buttons.
class VodPlate extends StatelessWidget {
  const VodPlate({
    super.key,
    required this.title,
    required this.progress,
    this.subtitle,
    this.barLit = false,
    this.barWrapper,
    this.onSeek,
    this.onSeekStart,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final VodProgress progress;
  final bool barLit;

  /// Wraps the bar row (a focus handler, for instance).
  final Widget Function(Widget child)? barWrapper;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onSeekStart;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final titleStyle = AppTheme.body(
      fontSize: 18,
      height: 1.22,
      fontWeight: FontWeight.w500,
    );
    final muted = AppTheme.body(fontSize: 15, color: AppColors.textMuted);
    final endsAt = p.endsAt();
    final timeStyle = AppTheme.body(
      fontSize: 16,
      height: 1.25,
      fontWeight: barLit ? FontWeight.w500 : FontWeight.w400,
      color: barLit ? AppColors.textPrimary : AppColors.textSecondary,
      fontFeatures: AppTheme.tabular,
    );
    final Widget line = onSeek == null
        ? OsdBar(
            progress: p.fraction,
            buffered: p.bufferedFraction,
            height: barLit ? 6 : 4,
            color: AppColors.textPrimary,
            knob: barLit ? 18 : 12,
            knobLit: barLit,
          )
        : _SeekBar(
            progress: p,
            lit: barLit,
            onSeek: onSeek!,
            onSeekStart: onSeekStart,
          );
    final bar = Row(
      children: [
        Text(formatPlayerTime(p.position), style: timeStyle),
        const SizedBox(width: 14),
        Expanded(child: line),
        const SizedBox(width: 14),
        Text(
          p.duration > Duration.zero ? '−${formatPlayerTime(p.remaining)}' : '',
          style: timeStyle.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
    return OsdPlate(
      padding: EdgeInsets.fromLTRB(18, 12, 18, actions == null ? 14 : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title, style: titleStyle),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        TextSpan(text: '   $subtitle', style: muted),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (endsAt != null) ...[
                const SizedBox(width: 16),
                Text(endsAt, style: muted),
              ],
            ],
          ),
          const SizedBox(height: 12),
          barWrapper?.call(bar) ?? bar,
          if (actions != null) ...[const SizedBox(height: 12), actions!],
        ],
      ),
    );
  }
}

/// Mouse seek bar: follows the pointer while dragging, seeks once on release
/// (one seek per gesture, not one per pixel: a seek may restart the stream).
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.progress,
    required this.lit,
    required this.onSeek,
    this.onSeekStart,
  });

  final VodProgress progress;
  final bool lit;
  final ValueChanged<double> onSeek;
  final VoidCallback? onSeekStart;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;
  bool _hover = false;

  double _fractionAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _commit(double f) {
    if (widget.progress.duration > Duration.zero) widget.onSeek(f);
  }

  @override
  Widget build(BuildContext context) {
    final big = widget.lit || _hover || _drag != null;
    return LayoutBuilder(
      builder: (context, box) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _commit(_fractionAt(d.localPosition, box.maxWidth)),
          onHorizontalDragStart: (d) {
            widget.onSeekStart?.call();
            setState(() => _drag = _fractionAt(d.localPosition, box.maxWidth));
          },
          onHorizontalDragUpdate: (d) => setState(
            () => _drag = _fractionAt(d.localPosition, box.maxWidth),
          ),
          onHorizontalDragEnd: (_) {
            final f = _drag;
            setState(() => _drag = null);
            if (f != null) _commit(f);
          },
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: SizedBox(
            height: 24,
            child: Center(
              child: OsdBar(
                progress: _drag ?? widget.progress.fraction,
                buffered: widget.progress.bufferedFraction,
                height: big ? 6 : 4,
                color: AppColors.textPrimary,
                knob: big ? 16 : 12,
                knobLit: widget.lit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Error, toast ──────────────────────────────────────────────────────────────

/// Low error plate over the frozen picture: title, detail, choices.
class ErrorPlate extends StatelessWidget {
  const ErrorPlate({
    super.key,
    required this.title,
    required this.detail,
    required this.actions,
  });

  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body(
            fontSize: 18,
            height: 1.28,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              fontSize: 14,
              height: 1.36,
              color: AppColors.textMuted,
            ),
          ),
      ],
    );
    const icon = Icon(
      Icons.tv_off_outlined,
      size: 24,
      color: AppColors.textSecondary,
    );
    final buttons = <Widget>[
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        actions[i],
      ],
    ];
    return LayoutBuilder(
      builder: (context, box) {
        // Narrow windows: text above the buttons.
        if (box.maxWidth < 640) {
          return OsdPlate(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ),
          );
        }
        return OsdPlate(
          height: 68,
          padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: text),
              const SizedBox(width: 14),
              ...buttons,
            ],
          ),
        );
      },
    );
  }
}

/// Short message (« Reprise à 38:12… »).
class PlayerToast extends StatelessWidget {
  const PlayerToast({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: OsdColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
