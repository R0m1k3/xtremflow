import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class ChannelCard extends StatefulWidget {
  final String channelNumber;
  final String channelName;
  final String? channelLogo;
  final String? currentProgram;
  final String? programTime;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteTap;
  final bool isActive;

  const ChannelCard({
    super.key,
    required this.channelNumber,
    required this.channelName,
    this.channelLogo,
    this.currentProgram,
    this.programTime,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteTap,
    this.isActive = false,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppTheme.durationMd,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: AppTheme.curveSmooth),
    );

    if (widget.isActive) {
      _pulseController.forward();
    }
  }

  @override
  void didUpdateWidget(ChannelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.forward();
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulseController.reverse();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: widget.isActive ? _pulseAnimation : AlwaysStoppedAnimation(1.0),
          child: AnimatedContainer(
            duration: AppTheme.durationMd,
            curve: AppTheme.curveDefault,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? AppColors.primary.withOpacity(0.15)
                  : AppColors.surface,
              border: Border.all(
                color: widget.isActive
                    ? AppColors.primary
                    : (_isHovered ? AppColors.border : AppColors.border.withOpacity(0.5)),
                width: widget.isActive ? 2.5 : 1.5,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: [
                if (_isHovered || widget.isActive)
                  BoxShadow(
                    color: widget.isActive
                        ? AppColors.primary.withOpacity(0.25)
                        : AppColors.primary.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.all(AppTheme.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.channelNumber,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: AppTheme.spacingXs),
                                Text(
                                  widget.channelName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onFavoriteTap,
                            child: AnimatedScale(
                              scale: widget.isFavorite ? 1.1 : 1.0,
                              duration: AppTheme.durationXs,
                              child: Icon(
                                widget.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: widget.isFavorite
                                    ? AppColors.secondary
                                    : AppColors.textSecondary,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppTheme.spacingSm),
                      if (widget.currentProgram != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.currentProgram!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (widget.programTime != null) ...[
                              SizedBox(height: AppTheme.spacingXs),
                              Text(
                                widget.programTime!,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                if (widget.isActive)
                  Positioned(
                    top: AppTheme.spacingSm,
                    right: AppTheme.spacingSm,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
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
    );
  }
}
