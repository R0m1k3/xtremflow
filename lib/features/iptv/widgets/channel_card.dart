import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/favorites_provider.dart';

/// Apple TV Style Channel Card
/// 
/// "Pop-out" effect on focus:
/// - Scales up (1.0 -> 1.1)
/// - Throws a large soft shadow
/// - Adds a thick white border (Focus Ring)
/// - Title is typically BELOW the card in tvOS, but we'll overlay it subtly or keep below.
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
  // late Animation<double> _pulseAnimation; // Unused for now, focus is static

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 1000)
    )..repeat(reverse: true);
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

    // Dynamic sizing based on hover. 
    // In valid tvOS, the layout reserves space, so we scale the content but not the layout bounds to avoid reflow.
    // However, simplest way here is just Transform.scale.
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
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
                      
                      // 2. Subtle Gradient (Always visible to make white logos pop on white background? No, black bg handling)
                      // Only show gradient if we have text to show ON the card, but for tvOS text is often below.
                      // Let's keep text overlay for now as requested "Minimalist" often implies overlays.
                      if (_isHovered)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
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
            // Only show text prominently if hovered? Or always?
            // "Minimalist" -> Always show but keep it subtle. White when focused.
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
                  if (widget.currentProgram != null && _isHovered) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.currentProgram!,
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
