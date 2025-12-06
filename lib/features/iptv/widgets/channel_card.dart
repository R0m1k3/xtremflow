import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/favorites_provider.dart';

/// Premium channel card with Netflix-style design
/// 
/// Features:
/// - Glassmorphism background
/// - Thumbnail/logo with fallback
/// - Live badge with pulse animation
/// - EPG overlay
/// - Favorite toggle
/// - Hover/tap effects
class ChannelCard extends ConsumerStatefulWidget {
  final String streamId;
  final String name;
  final String? iconUrl;
  final String? currentProgram;
  final bool isLive;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const ChannelCard({
    super.key,
    required this.streamId,
    required this.name,
    this.iconUrl,
    this.currentProgram,
    this.isLive = true,
    this.onTap,
    this.width,
    this.height,
  });

  @override
  ConsumerState<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<ChannelCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.contains(widget.streamId);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: widget.width ?? 180,
          height: widget.height ?? 120,
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surface, // Clean flat dark surface
            border: Border.all(
              color: _isHovered
                  ? AppColors.primary
                  : AppColors.border,
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7), // Inner radius
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Channel logo/thumbnail
                _buildChannelImage(),
                
                // Gradient overlay for text readability
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.2),
                          Colors.black.withOpacity(0.9),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                
                // Live badge
                if (widget.isLive)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildLiveBadge(),
                  ),

                // Favorite Icon
                Positioned(
                  top: 0,
                  left: 0,
                  child: IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                      color: isFavorite ? AppColors.primary : Colors.white70,
                    ),
                    onPressed: () {
                      ref.read(favoritesProvider.notifier).toggleFavorite(widget.streamId);
                    },
                  ),
                ),
                
                // Channel info
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.currentProgram != null && widget.currentProgram!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.currentProgram!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelImage() {
    if (widget.iconUrl != null && widget.iconUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.iconUrl!,
        fit: BoxFit.contain, // Contain usually looks better for channel logos
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.tv,
          size: 32,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.live.withOpacity(_pulseAnimation.value),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
