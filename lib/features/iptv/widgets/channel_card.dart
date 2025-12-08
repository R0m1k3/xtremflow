import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/favorites_provider.dart';
import '../../../core/models/playlist_config.dart';
import '../../iptv/providers/xtream_provider.dart';

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
  
  // EPG State
  String? _epgNow;
  bool _epgLoaded = false;


  @override
  void initState() {
    super.initState();
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
