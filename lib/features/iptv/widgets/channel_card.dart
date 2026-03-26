import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../providers/favorites_provider.dart';
import '../../../core/models/playlist_config.dart';
import '../../iptv/providers/xtream_provider.dart';

/// Modern Apple TV Channel Card
/// 
/// Features:
/// - Live indicator with pulse animation
/// - Favorite button with smooth interaction
/// - EPG information display
/// - Focus-aware scaling
/// - Smooth image loading with skeleton loading
class ChannelCard extends ConsumerStatefulWidget {
  final String streamId;
  final String name;
  final String? iconUrl;
  final String? currentProgram;
  final bool isLive;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final PlaylistConfig playlist;

  const ChannelCard({
    super.key,
    required this.streamId,
    required this.name,
    required this.playlist,
    this.iconUrl,
    this.currentProgram,
    this.isLive = true,
    this.onTap,
    this.width = 200,
    this.height = 120,
  });

  @override
  ConsumerState<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<ChannelCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool? _epgLoaded;
  String? _epgNow;

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for live indicator
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _epgLoaded = false;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = ref.watch(favoritesProvider).contains(widget.streamId);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.08 : 1.0,
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
                // ============ BACKGROUND IMAGE ============
                _buildChannelImage(),

                // ============ GRADIENT OVERLAY ============
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(_isHovered ? 0.7 : 0.5),
                      ],
                    ),
                  ),
                ),

                // ============ CONTENT ============
                Positioned(
                  left: AppTheme.spacing12,
                  right: AppTheme.spacing12,
                  bottom: AppTheme.spacing12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Channel name
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      if (widget.currentProgram != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.currentProgram!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ============ TOP INDICATORS ============
                Positioned(
                  top: AppTheme.spacing12,
                  left: AppTheme.spacing12,
                  right: AppTheme.spacing12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Live indicator
                      if (widget.isLive) _buildLiveIndicator(),

                      // Favorite button
                      _buildFavoriteButton(isFavorite),
                    ],
                  ),
                ),

                // ============ FOCUS STATE ============
                if (_isHovered)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      border: Border.all(
                        color: AppColors.primary,
                        width: 2,
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

  /// Build channel image with skeleton loading
  Widget _buildChannelImage() {
    if (widget.iconUrl == null || widget.iconUrl!.isEmpty) {
      return Container(
        color: AppColors.surface,
        child: Center(
          child: Icon(
            Icons.tv,
            color: AppColors.textSecondary,
            size: 48,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.iconUrl!,
      fit: BoxFit.cover,
      placeholder: (context, url) => _buildImageSkeleton(),
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

  /// Skeleton loader for images
  Widget _buildImageSkeleton() {
    return Container(
      color: AppColors.shimmer,
      child: const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ),
    );
  }

  /// Build animated live indicator
  Widget _buildLiveIndicator() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.live,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'LIVE',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build favorite button with interaction
  Widget _buildFavoriteButton(bool isFavorite) {
    return GestureDetector(
      onTap: () {
        ref.read(favoritesProvider.notifier).toggle(widget.streamId);
      },
      child: AnimatedScale(
        scale: isFavorite ? 1.0 : 0.9,
        duration: AppTheme.durationSm,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(
              color: isFavorite ? AppColors.secondary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? AppColors.secondary : AppColors.textSecondary,
            size: 18,
          ),
        ),
      ),
    );
  }
}
    _pulseController = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    // Fetch EPG immediately when card is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchEpg();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchEpg() async {
    if (_epgLoaded) return;
    
    try {
      // Don't modify state if unmounted
      if (!mounted) return;

      final service = ref.read(xtreamServiceProvider(widget.playlist));
      // We use the short EPG endpoint for quick access
      final entries = await service.getShortEpg(widget.streamId);
      
      if (mounted && entries.isNotEmpty) {
        final now = DateTime.now();
        // Find current program
        final current = entries.firstWhere(
          (e) {
             try {
               final start = DateTime.parse(e.start);
               final end = DateTime.parse(e.end);
               return now.isAfter(start) && now.isBefore(end);
             } catch (_) {
               return false; 
             }
          },
          orElse: () => entries.first,
        );
        
        setState(() {
          _epgNow = current.title;
          _epgLoaded = true;
        });
      }
    } catch (_) {
      // Fail silently
      if (mounted) setState(() => _epgLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.contains(widget.streamId);

    // Dynamic sizing based on hover
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
      },
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The Image Card (Scales)
            AnimatedScale(
              scale: _isHovered ? 1.05 : 1.0,
              duration: AppTheme.durationFast,
              curve: AppTheme.curveDefault,
              child: AnimatedContainer(
                duration: AppTheme.durationFast,
                width: widget.width ?? 180,
                height: widget.height ?? 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  color: AppColors.surface, // Fallback color
                  // Thick white border on focus (tvOS style)
                  border: Border.all(
                    color: _isHovered ? AppColors.focusColor : Colors.transparent,
                    width: _isHovered ? 3 : 0,
                  ),
                  // Deep shadow on focus
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                            spreadRadius: 2,
                          ),
                        ]
                      : [
                           BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                      ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd - (_isHovered ? 2 : 0)), // Adjust inner radius
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. Background Image / Logo - EDGE TO EDGE
                      _buildChannelImage(),
                      
                      // 2. Gradient Overlay (Subtle)
                      if (_isHovered)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),

                      // 3. Live Badge (Top Right)
                      if (widget.isLive)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.live,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ),

                      // 4. Favorite Icon (Top Left)
                      if (_isHovered || isFavorite)
                        Positioned(
                          top: 5,
                          left: 5,
                          child: GestureDetector(
                            onTap: () => ref.read(favoritesProvider.notifier).toggleFavorite(widget.streamId),
                            child: Icon(
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: isFavorite ? AppColors.live : Colors.white.withOpacity(0.7), 
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Text separates from card (Classic tvOS look)
            SizedBox(
              width: widget.width ?? 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    widget.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isHovered ? AppColors.focusColor : AppColors.textSecondary,
                      fontWeight: _isHovered ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if ((widget.currentProgram != null || _epgNow != null)) ...[
                    const SizedBox(height: 2),
                    Text(
                      _epgNow ?? widget.currentProgram ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelImage() {
    if (widget.iconUrl != null && widget.iconUrl!.isNotEmpty) {
      return Container(
        color: Colors.white, // Logos usually look best on white/light grey
        child: CachedNetworkImage(
          imageUrl: widget.iconUrl!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) => _buildPlaceholder(),
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: Icon(Icons.tv, color: AppColors.textTertiary),
      ),
    );
  }
}
