import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';

/// Apple TV Modern Content Card
/// 
/// Premium card for displaying movies, shows, or other content with:
/// - Poster image with skeleton loading
/// - Title and metadata
/// - Rating/score display
/// - Interactive hover states
/// - Context menu support
class TvModernCard extends StatefulWidget {
  final String id;
  final String title;
  final String? imageUrl;
  final String? rating;
  final String? year;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;
  final VoidCallback? onPlayTap;
  final VoidCallback? onMoreTap;
  final bool isWatching;
  final double? progress;

  const TvModernCard({
    super.key,
    required this.id,
    required this.title,
    this.imageUrl,
    this.rating,
    this.year,
    this.badge,
    this.badgeColor,
    this.onTap,
    this.onPlayTap,
    this.onMoreTap,
    this.isWatching = false,
    this.progress,
  });

  @override
  State<TvModernCard> createState() => _TvModernCardState();
}

class _TvModernCardState extends State<TvModernCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTheme.durationMd,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ============ POSTER IMAGE ============
            AnimatedScale(
              scale: _isHovered ? 1.06 : 1.0,
              duration: AppTheme.durationMd,
              curve: AppTheme.curveDefault,
              child: GlassCard(
                borderRadius: AppTheme.radiusLg,
                padding: EdgeInsets.zero,
                interactive: true,
                onTap: widget.onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Poster image
                    _buildPosterImage(),

                    // Overlay
                    if (_isHovered)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),

                    // Badge
                    if (widget.badge != null)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.badgeColor ?? AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.badge!,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                    // Progress indicator (if watching)
                    if (widget.isWatching && widget.progress != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(AppTheme.radiusLg),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(AppTheme.radiusLg),
                            ),
                            child: LinearProgressIndicator(
                              value: widget.progress,
                              backgroundColor: AppColors.surfaceVariant,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.primary,
                              ),
                              minHeight: 3,
                            ),
                          ),
                        ),
                      ),

                    // Action buttons (on hover)
                    if (_isHovered && (widget.onPlayTap != null || widget.onMoreTap != null))
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.onPlayTap != null)
                              _buildActionButton(
                                icon: Icons.play_arrow,
                                label: 'Play',
                                onTap: widget.onPlayTap!,
                              ),
                            if (widget.onPlayTap != null && widget.onMoreTap != null)
                              const SizedBox(width: 16),
                            if (widget.onMoreTap != null)
                              _buildActionButton(
                                icon: Icons.info_outline,
                                label: 'Info',
                                onTap: widget.onMoreTap!,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ============ METADATA ============
            // Title
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),

            // Rating & Year
            if (widget.rating != null || widget.year != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (widget.rating != null) ...[
                    Icon(
                      Icons.star,
                      size: 14,
                      color: AppColors.ratingGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.rating!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (widget.rating != null && widget.year != null)
                    const SizedBox(width: 12),
                  if (widget.year != null)
                    Text(
                      widget.year!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPosterImage() {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return Container(
        color: AppColors.surface,
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: AppColors.textSecondary,
            size: 48,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl!,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: AppColors.shimmer,
        child: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: AppColors.surface,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: AppColors.textSecondary,
            size: 48,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
