import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/channel_logo.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/utils/group_label.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../providers/xtream_provider.dart';
import '../utils/epg_now.dart';

/// Pieces of the Direct tab, after xtremobile's `live_widgets.dart` (TV
/// layout), adapted to the web: mouse and keyboard share the focus
/// ([TVFocusable]), the guide comes from [epgByPlaylistProvider].

// ─── Guide ─────────────────────────────────────────────────────────────────────

/// What is on now on [channel] (short EPG, cached by the service).
EpgNow watchEpgNow(WidgetRef ref, PlaylistConfig playlist, Channel channel) {
  final entries = ref
      .watch(
        epgByPlaylistProvider(
          EpgRequestKey(playlist: playlist, streamId: channel.streamId),
        ),
      )
      .valueOrNull;
  if (entries == null) return EpgNow.empty;
  return epgNow(entries, DateTime.now());
}

/// Logo address of [channel].
String logoOf(Channel channel) =>
    channelLogoUrl(streamIcon: channel.streamIcon, name: channel.name);

// ─── Small pieces ──────────────────────────────────────────────────────────────

/// "FR| BEIN SPORTS MAX 10 FHD HEVC (EVENTS)" -> "BEIN SPORTS MAX 10": the
/// words worth reading on a logo tile.
String shortChannelName(String name) {
  var n = name.replaceFirst(RegExp(r'^\s*[A-Z]{2,3}\s*[|:\-]\s*'), '');
  n = n.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
  const tags = {
    'FHD',
    'HD',
    'UHD',
    'SD',
    '4K',
    '8K',
    'HEVC',
    'H265',
    'H.265',
    'H264',
    'HDR',
    'FULLHD',
    '50FPS',
    '60FPS',
    'MULTI-AUDIO',
    'MULTI',
    'VIP',
    'RAW',
  };
  final words = n
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !tags.contains(w.toUpperCase()))
      .toList();
  if (words.isEmpty) return name.trim();
  return words.take(4).join(' ');
}

/// A channel logo on its dark tile ([url] from `channelLogoUrl`: the server
/// finds a logo by name when the playlist has none).
/// The tile stays dark even when the row
/// is lit, so the logo keeps its own colours.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.url,
    required this.name,
    required this.width,
    required this.height,
    this.radius = 6,
    this.inset = false,
  });

  final String url;
  final String name;
  final double width;
  final double height;

  /// Sunk into a TV card rather than raised on the page.
  final bool inset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.isNotEmpty;
    // No logo: the short name (no country prefix, no quality tags). Two
    // lines on big tiles; on small ones the first word, shrunk to fit but
    // never below 11 dp (shrinking the whole name made scribbles).
    final inner = height * (1 - 2 * 0.12);
    final fallback = LayoutBuilder(
      builder: (context, box) {
        final short = shortChannelName(name);
        final twoLines = inner >= 34;
        final text = twoLines ? short : short.split(' ').first;
        var size = (inner / (twoLines ? 2 : 1) / 1.15).clamp(11.0, 14.0);
        if (!twoLines) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: AppTheme.body(fontSize: size, fontWeight: FontWeight.w600),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          if (painter.width > box.maxWidth) {
            size = (size * box.maxWidth / painter.width).clamp(11.0, size);
          }
          painter.dispose();
        }
        return Center(
          child: Text(
            text,
            maxLines: twoLines ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              fontSize: size,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        );
      },
    );
    return Container(
      width: width,
      height: height,
      decoration: AppDecorations.logoTile(radius: radius, inset: inset),
      padding: EdgeInsets.all(height * 0.12),
      child: hasUrl
          ? Image.network(
              url,
              fit: BoxFit.contain,
              cacheHeight: (height * 2).round(),
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }
}

/// The signature: a red line showing how far the programme on now has run.
class LiveLine extends StatelessWidget {
  const LiveLine({
    super.key,
    required this.progress,
    this.height = 3,
    this.lit = false,
    this.subdued = false,
  });

  final double progress;
  final double height;

  /// In a list: one bar per row, so each one quieter.
  final bool subdued;

  /// On a lit (focused) surface the track lightens.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          color: lit
              ? AppColors.liveOnLight
              : subdued
              ? AppColors.live.withValues(alpha: .7)
              : AppColors.live,
          backgroundColor: lit ? AppColors.focusTrack : AppColors.track,
          minHeight: height,
        ),
      ),
    );
  }
}

/// `Tous les groupes  125`: label in primary, count quieter.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.count, this.fontSize = 18});

  final String title;
  final int? count;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: title),
          if (count != null)
            TextSpan(
              text: '  $count',
              style: AppTheme.body(
                fontSize: fontSize - 2,
                color: AppColors.textMuted,
                fontFeatures: AppTheme.tabular,
              ),
            ),
        ],
      ),
      style: AppTheme.body(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }
}

// ─── Groups ────────────────────────────────────────────────────────────────────

/// Star of a group card: pins or unpins the group. Shown when the card is
/// lit or the group is already pinned.
class _PinStar extends StatelessWidget {
  const _PinStar({
    required this.pinned,
    required this.lit,
    required this.onPressed,
  });

  final bool pinned;
  final bool lit;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!pinned && !lit) return const SizedBox(width: 28, height: 28);
    final color = lit
        ? (pinned ? AppColors.accentOnLight : AppColors.onFocusMuted)
        : AppColors.accent;
    return Tooltip(
      message: pinned ? 'Retirer des favoris' : 'Ajouter aux favoris',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              pinned ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 20,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Group card of the « Tous les groupes » grid: name, country, channel count,
/// and the star that pins it to « Favoris ». Lit when focused or hovered.
/// Keyboard: a long press on Entrée pins or unpins.
class TvGroupCard extends StatelessWidget {
  const TvGroupCard({
    super.key,
    required this.label,
    required this.count,
    required this.pinned,
    required this.onPressed,
    required this.onTogglePin,
    this.autofocus = false,
  });

  final GroupLabel label;
  final int count;
  final bool pinned;
  final VoidCallback onPressed;
  final VoidCallback onTogglePin;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      scale: 1.03,
      borderRadius: BorderRadius.circular(12),
      onPressed: onPressed,
      onLongPress: onTogglePin,
      longPressDuration: const Duration(milliseconds: 700),
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final country =
              label.country != null &&
                  label.country!.toLowerCase() != label.name.toLowerCase()
              ? label.country
              : null;
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: AppDecorations.tvCard(lit: lit, radius: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: lit
                              ? AppColors.onFocus
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (country != null) country,
                          '$count chaînes',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 13.5,
                          color: lit
                              ? AppColors.onFocusMuted
                              : AppColors.textSecondary,
                          fontFeatures: AppTheme.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                _PinStar(pinned: pinned, lit: lit, onPressed: onTogglePin),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Card of the « Favoris » row: a pinned group, or « Chaînes favorites »
/// ([icon] set, no star).
class FavoriteGroupCard extends StatelessWidget {
  const FavoriteGroupCard({
    super.key,
    required this.category,
    required this.onPressed,
    this.onTogglePin,
    this.icon,
    this.autofocus = false,
  });

  /// Category name as given by the playlist (`FR | Sport`) and its size.
  final ({String name, int count}) category;
  final VoidCallback onPressed;
  final VoidCallback? onTogglePin;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final label = icon == null
        ? GroupLabel.parse(category.name)
        : GroupLabel(name: category.name);
    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      scale: 1.03,
      borderRadius: BorderRadius.circular(14),
      onPressed: onPressed,
      onLongPress: onTogglePin,
      longPressDuration: const Duration(milliseconds: 700),
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            decoration: AppDecorations.tvCard(lit: lit),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 24,
                    color: lit ? AppColors.accentOnLight : AppColors.accent,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: lit
                              ? AppColors.onFocus
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label.meta(channelCount: category.count),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 14,
                          color: lit
                              ? AppColors.onFocusMuted
                              : AppColors.textSecondary,
                          fontFeatures: AppTheme.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTogglePin != null)
                  _PinStar(pinned: true, lit: lit, onPressed: onTogglePin!),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Channels ──────────────────────────────────────────────────────────────────

/// One channel: number, logo, full name (2 lines at most), programme on now
/// with its times and the live line. Lit when focused or hovered.
class ChannelRow extends ConsumerWidget {
  const ChannelRow({
    super.key,
    required this.playlist,
    required this.channel,
    required this.number,
    required this.onPressed,
    required this.isFavorite,
    this.onFocus,
    this.focusNode,
    this.autofocus = false,
  });

  final PlaylistConfig playlist;
  final Channel channel;

  /// Rank in the list shown, from 1.
  final int number;
  final VoidCallback onPressed;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final bool isFavorite;
  final bool autofocus;

  static const double height = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = watchEpgNow(ref, playlist, channel);
    final current = now.current;

    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      focusNode: focusNode,
      scale: 1.0,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      onFocus: onFocus,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final primary = lit ? AppColors.onFocus : AppColors.textPrimary;
          final secondary = lit
              ? AppColors.onFocusMuted
              : AppColors.textSecondary;
          final muted = lit ? AppColors.onFocusMuted : AppColors.textMuted;
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: GlassDecoration(
              lit: lit ? 1 : 0,
              radius: 10,
              bare: true,
              halo: false,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '$number',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: AppTheme.body(
                      fontSize: 14,
                      color: muted,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ChannelLogo(
                  url: logoOf(channel),
                  name: channel.name,
                  width: 64,
                  height: 40,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.name,
                              maxLines: current == null ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(
                                fontSize: 16,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                                color: primary,
                              ),
                            ),
                          ),
                          if (isFavorite)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: lit
                                    ? AppColors.accentOnLight
                                    : AppColors.accent,
                              ),
                            ),
                          if (now.timeRange != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(
                                now.timeRange!,
                                style: AppTheme.body(
                                  fontSize: 14,
                                  color: secondary,
                                  fontFeatures: AppTheme.tabular,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (current != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(fontSize: 14, color: secondary),
                        ),
                        if (now.progress != null) ...[
                          const SizedBox(height: 6),
                          LiveLine(
                            progress: now.progress!,
                            lit: lit,
                            height: lit ? 3 : 2,
                            subdued: !lit,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Right-hand panel of the channel list: the preview (or the big logo),
/// number and full name, programme, times, time left, progress, next.
class NowPanel extends ConsumerWidget {
  const NowPanel({
    super.key,
    required this.playlist,
    required this.channel,
    required this.number,
    required this.isFavorite,
    required this.onFullScreen,
    required this.onToggleFavorite,
    required this.onRecord,
    this.preview,
  });

  final PlaylistConfig playlist;
  final Channel? channel;
  final int number;
  final bool isFavorite;
  final VoidCallback onFullScreen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRecord;

  /// Live picture shown on top; without it, the big logo is shown.
  final Widget? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = channel;
    if (c == null) {
      return Container(
        decoration: AppDecorations.tvCard(lit: false, radius: 16),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'Survolez une chaîne pour voir ce qui passe',
          textAlign: TextAlign.center,
          style: AppTheme.body(fontSize: 15, color: AppColors.textMuted),
        ),
      );
    }
    final now = watchEpgNow(ref, playlist, c);

    final top = AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onFullScreen,
            child:
                preview ??
                ColoredBox(
                  color: AppColors.surface,
                  child: Center(
                    child: ChannelLogo(
                      url: logoOf(c),
                      name: c.name,
                      width: 160,
                      height: 100,
                      radius: 12,
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    return Container(
      decoration: AppDecorations.tvCard(lit: false, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$number  ',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontFeatures: AppTheme.tabular,
                          ),
                        ),
                        TextSpan(text: c.name),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) =>
                          _NowProgramme(now: now, height: box.maxHeight),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PanelButton(
                        icon: Icons.fullscreen_rounded,
                        label: 'Plein écran',
                        primary: true,
                        onPressed: onFullScreen,
                      ),
                      PanelButton(
                        icon: isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: isFavorite ? 'Favori' : 'Ajouter aux favoris',
                        onPressed: onToggleFavorite,
                      ),
                      PanelButton(
                        icon: Icons.fiber_manual_record_outlined,
                        label: 'Enregistrer',
                        onPressed: onRecord,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill button of the panels: graphite at rest, lit when focused.
class PanelButton extends StatelessWidget {
  const PanelButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      scale: 1.0,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final ink = lit
              ? AppColors.onFocus
              : primary
              ? AppColors.accent
              : AppColors.textPrimary;
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: lit ? AppColors.focusTop : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: ink),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTheme.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Title, times, progress, « À suivre » and description of the programme,
/// fitted to [height] in whole lines (nothing cut half-way).
class _NowProgramme extends StatelessWidget {
  const _NowProgramme({required this.now, required this.height});

  final EpgNow now;
  final double height;

  static const _titleSize = 18.0, _lineHeight = 1.25;
  static const _smallSize = 14.5;
  static const _descSize = 14.5, _descHeight = 1.45;

  @override
  Widget build(BuildContext context) {
    final current = now.current;
    final titleLine = _titleSize * _lineHeight;
    final titleStyle = AppTheme.body(
      fontSize: _titleSize,
      fontWeight: FontWeight.w500,
      height: _lineHeight,
      color: current == null ? AppColors.textSecondary : AppColors.textPrimary,
    );
    final smallStyle = AppTheme.body(
      fontSize: _smallSize,
      height: _lineHeight,
      color: AppColors.textSecondary,
      fontFeatures: AppTheme.tabular,
    );
    final next = now.next;
    final nextText = next == null
        ? null
        : 'À suivre : ${[now.nextStart, next.title].whereType<String>().join('  ')}';

    if (current == null) {
      if (height < titleLine) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pas de guide pour cette chaîne',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          if (nextText != null && height >= titleLine * 2) ...[
            const SizedBox(height: 6),
            Text(
              nextText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: smallStyle,
            ),
          ],
        ],
      );
    }

    // What fits, by priority: the title, the progress line, the times, « À
    // suivre », a second title line, then the description.
    const barBlock = 8.0 + 4;
    const smallBlock = 6 + _smallSize * _lineHeight;
    if (height < titleLine) return const SizedBox.shrink();
    var titleLines = 1;
    var left = height - titleLine;
    final showBar = now.progress != null && left >= barBlock;
    if (showBar) left -= barBlock;
    final showTimes = left >= smallBlock;
    if (showTimes) left -= smallBlock;
    final showNext = nextText != null && left >= smallBlock;
    if (showNext) left -= smallBlock;
    if (left >= titleLine) {
      titleLines = 2;
      left -= titleLine;
    }
    final descLines = current.description.isEmpty
        ? 0
        : ((left - 12) / (_descSize * _descHeight)).floor().clamp(0, 6).toInt();

    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current.title,
              maxLines: titleLines,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            if (showTimes) ...[
              const SizedBox(height: 6),
              Text(
                [
                  now.timeRange,
                  now.remainingText,
                ].whereType<String>().join(' · '),
                maxLines: 1,
                style: smallStyle,
              ),
            ],
            if (showBar) ...[
              const SizedBox(height: 8),
              LiveLine(progress: now.progress!, height: 4),
            ],
            if (showNext) ...[
              const SizedBox(height: 6),
              Text(
                nextText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: smallStyle,
              ),
            ],
            if (descLines > 0) ...[
              const SizedBox(height: 12),
              Text(
                current.description,
                maxLines: descLines,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  fontSize: _descSize,
                  height: _descHeight,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
