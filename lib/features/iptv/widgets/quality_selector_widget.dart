import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Stream quality presets handled server-side by FFmpeg
/// (see bin/api/streaming_handler.dart).
enum StreamQuality {
  source('source', 'Source', 'Flux direct, zéro transcodage'),
  high('high', 'Haute', '1080p · 6-8 Mbit/s'),
  medium('medium', 'Moyenne', '3 Mbit/s'),
  low('low', 'Basse', '720p · 1,5 Mbit/s');

  const StreamQuality(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

/// Bouton (menu) qui change la qualité de transcodage du flux en cours.
class QualitySelectorButton extends StatelessWidget {
  final StreamQuality current;
  final ValueChanged<StreamQuality> onSelected;
  final double size;

  const QualitySelectorButton({
    super.key,
    required this.current,
    required this.onSelected,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Qualité : ${current.label}',
      child: PopupMenuButton<StreamQuality>(
        initialValue: current,
        color: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.hairline),
        ),
        onSelected: onSelected,
        itemBuilder: (context) => StreamQuality.values
            .map(
              (q) => PopupMenuItem<StreamQuality>(
                value: q,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      q == current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 18,
                      color: q == current
                          ? AppColors.accent
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            q.label,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: q == current
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            q.description,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          // Over the video: a dark disc keeps the icon legible on a bright
          // picture (the translucent glass would not).
          decoration: BoxDecoration(
            color: AppColors.rail.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline),
          ),
          child: const Icon(
            Icons.high_quality_rounded,
            color: AppColors.textPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
