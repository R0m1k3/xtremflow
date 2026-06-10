import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Stream quality presets handled server-side by FFmpeg
/// (see bin/api/streaming_handler.dart).
enum StreamQuality {
  source('source', 'Source', 'Flux direct, zéro transcodage'),
  high('high', 'Haute', '1080p · 6-8 Mbps'),
  medium('medium', 'Moyenne', '3 Mbps'),
  low('low', 'Basse', '720p · 1.5 Mbps');

  const StreamQuality(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

/// Popup button to switch the transcoding quality of the current stream.
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
        color: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          ? AppColors.primary
                          : AppColors.textTertiary,
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
                            style: GoogleFonts.instrumentSans(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            q.description,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.instrumentSans(
                              color: AppColors.textTertiary,
                              fontSize: 11,
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
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: const Icon(
            Icons.high_quality_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
