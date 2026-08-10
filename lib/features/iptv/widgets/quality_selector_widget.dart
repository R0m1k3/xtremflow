import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/adaptive_bitrate_service.dart';
import '../../../core/theme/app_colors.dart';

/// Widget for displaying and selecting video quality during playback
class QualitySelectorWidget extends ConsumerStatefulWidget {
  final QualitySelector qualitySelector;
  final VoidCallback onClose;

  const QualitySelectorWidget({
    super.key,
    required this.qualitySelector,
    required this.onClose,
  });

  @override
  ConsumerState<QualitySelectorWidget> createState() =>
      _QualitySelectorWidgetState();
}

class _QualitySelectorWidgetState extends ConsumerState<QualitySelectorWidget> {
  late List<QualityLevel> _availableQualities;
  late QualityLevel _selectedQuality;

  @override
  void initState() {
    super.initState();
    _availableQualities = QualityProfiles.getBalancedProfiles();
    _selectedQuality = widget.qualitySelector.currentQuality;
  }

  @override
  Widget build(BuildContext context) {
    final currentQuality = widget.qualitySelector.currentQuality;
    final bandwidthMbps = widget.qualitySelector.getEstimatedBandwidthMbps();

    return Dialog(
      backgroundColor: AppColors.surfaceContainer,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.onSurface24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Video Quality',
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.onSurface),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Network Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.onSurface06,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Current Bandwidth:',
                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
                  ),
                  Text(
                    '${bandwidthMbps.toStringAsFixed(1)} Mbps',
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Quality Options
          ListView.builder(
            shrinkWrap: true,
            itemCount: _availableQualities.length,
            itemBuilder: (context, index) {
              final quality = _availableQualities[index];
              final isSelected = quality == currentQuality;

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                leading: isSelected
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : const Icon(
                        Icons.radio_button_unchecked,
                        color: AppColors.onSurface24,
                      ),
                title: Text(
                  quality.label,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  '${quality.bitrateBps ~/ 1000000} Mbps',
                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                ),
                onTap: () {
                  widget.qualitySelector.setQuality(quality);
                  setState(() {
                    _selectedQuality = quality;
                  });
                },
              );
            },
          ),

          // Auto Quality Option
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.onSurface24),
                ),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                leading: const Icon(Icons.auto_awesome, color: Colors.amber),
                title: const Text(
                  'Auto Quality',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Adjusts based on network speed',
                  style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                ),
                onTap: () {
                  // Auto mode would be handled by the player
                  widget.onClose();
                },
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Floating quality indicator (minimal UI during playback)
class QualityIndicator extends ConsumerWidget {
  final QualitySelector qualitySelector;
  final VoidCallback onTap;

  const QualityIndicator({
    super.key,
    required this.qualitySelector,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = qualitySelector.currentQuality;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.baseLevel0,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.high_quality, color: AppColors.onSurface, size: 16),
            const SizedBox(width: 4),
            Text(
              quality.resolution.split('x')[1], // Show just the height
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandwidth monitor widget (for debugging/info)
class BandwidthMonitor extends ConsumerWidget {
  final QualitySelector qualitySelector;

  const BandwidthMonitor({
    super.key,
    required this.qualitySelector,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.baseLevel0,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, color: Colors.green, size: 14),
          const SizedBox(width: 4),
          Text(
            '${qualitySelector.getEstimatedBandwidthMbps().toStringAsFixed(1)} Mbps',
            style: const TextStyle(
              color: AppColors.onSurface,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
