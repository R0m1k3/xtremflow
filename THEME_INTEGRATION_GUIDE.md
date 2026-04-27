# XtremFlow Apple TV Modern Theme - Integration Guide

## Quick Start

### 1. Theme is Already Active
The new Apple TV modern theme is automatically applied in `main.dart`:

```dart
MaterialApp(
  theme: AppTheme.darkTheme,
  // Mobile variant (auto-selected based on platform)
  // darkTheme: MobileTheme.darkTheme,
)
```

### 2. Using Colors

```dart
import 'lib/core/theme/app_colors.dart';

// Primary brand color (Cyan)
Container(color: AppColors.primary)

// Text colors with hierarchy
Text('Title', style: TextStyle(color: AppColors.textPrimary))
Text('Subtitle', style: TextStyle(color: AppColors.textSecondary))

// Semantic colors
FloatingActionButton(
  backgroundColor: AppColors.success,
  child: Icon(Icons.check),
)

// Category indicators
Chip(
  label: Text('Movies'),
  backgroundColor: AppColors.movies,
)
```

### 3. Using Spacing

```dart
import 'lib/core/theme/app_theme.dart';

// Fixed spacing
Padding(
  padding: EdgeInsets.all(AppTheme.spacing16),
  child: Text('Content'),
)

// Symmetric spacing
SizedBox(
  height: AppTheme.spacing24,
)

// Mobile-safe margins
Container(
  margin: EdgeInsets.symmetric(
    horizontal: AppTheme.spacing32, // 32px on desktop
    vertical: AppTheme.spacing16,   // 16px vertical
  ),
  child: content,
)
```

### 4. Using Typography

```dart
import 'package:google_fonts/google_fonts.dart';

// Via theme (preferred)
Text(
  'Hero Title',
  style: Theme.of(context).textTheme.displayLarge,
)

// Manual override
Text(
  'Custom Text',
  style: GoogleFonts.outfit(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  ),
)

// Common styles
headline: Theme.of(context).textTheme.headlineMedium
button: Theme.of(context).textTheme.labelLarge
body: Theme.of(context).textTheme.bodyMedium
```

### 5. Core Widgets

#### GlassContainer
- Glassmorphism effect with blur + gradient
- Use for overlays, headers, premium cards

```dart
GlassContainer(
  padding: EdgeInsets.all(16),
  borderRadius: AppTheme.radiusLg,
  child: YourWidget(),
)
```

#### GlassCard
- Interactive glass card with animations
- Auto scales on hover/tap

```dart
GlassCard(
  interactive: true,
  onTap: () => handleTap(),
  child: ContentHere(),
)
```

#### ChannelCard
- Live TV channel card
- Features: Live badge, favorite button, EPG info
- Responsive sizing

```dart
ChannelCard(
  streamId: channel.id,
  name: channel.name,
  iconUrl: channel.logo,
  currentProgram: 'Breaking Bad',
  isLive: true,
  playlist: playlistConfig,
  onTap: () => playChannel(channel),
)
```

#### TvModernCard
- Content card for movies/shows
- Features: Rating, year, badge, progress bar
- Playing state indicator

```dart
TvModernCard(
  id: item.id,
  title: 'Stranger Things',
  imageUrl: 'https://...',
  rating: '8.7/10',
  year: '2024',
  badge: 'NEW',
  badgeColor: AppColors.primary,
  progress: 0.35, // 35% watched
  onPlayTap: () => playContent(item),
)
```

#### HeroCarousel
- Full-screen featured content slider
- Auto-play with manual controls

```dart
HeroCarousel(
  items: [
    HeroCarouselItem(
      id: '1',
      title: 'Breaking Bad',
      subtitle: 'Complete Series',
      imageUrl: 'https://...',
      badge: 'BINGE-WORTHY',
      onPlay: () => play(),
      onTap: () => showDetails(),
    ),
  ],
  autoPlay: true,
)
```

#### TvChannelGrid
- Responsive grid for channels
- Auto-adjusts columns based on screen size

```dart
TvChannelGrid(
  children: channels.map((ch) => ChannelCard(
    streamId: ch.id,
    name: ch.name,
    // ...
  )).toList(),
)

// Responsive behavior:
// >1920px: 6 columns
// >1600px: 5 columns
// >1280px: 4 columns
// >960px:  3 columns
// Else:    2 columns
```

#### TvHorizontalList
- Horizontal scrollable content list with title
- Smooth scroll animation

```dart
TvHorizontalList(
  title: 'Continue Watching',
  children: items.map((item) => TvModernCard(...)).toList(),
  itemWidth: 200,
  spacing: 16,
)
```

#### TvTopNavBar
- Premium header navigation
- Search, notifications, profile

```dart
TvTopNavBar(
  title: 'XtremFlow',
  onSearch: () => showSearch(),
  onNotifications: () => showNotifications(),
  onProfile: () => showProfile(),
  notificationCount: 3,
)
```

#### TvSideNav
- Vertical navigation menu
- Category/section navigation

```dart
TvSideNav(
  items: [
    TvNavItem(label: 'Home', icon: Icons.home),
    TvNavItem(label: 'Live', icon: Icons.tv),
    TvNavItem(label: 'Movies', icon: Icons.movie),
  ],
  selectedIndex: 0,
  onItemSelected: (idx) => _navigate(idx),
)
```

---

## Layout Patterns

### Hero Section
```dart
SizedBox(
  height: 360,
  child: Stack(
    children: [
      HeroCarousel(items: featuredItems),
      // Additional overlay elements
    ],
  ),
)
```

### Content Grid with Header
```dart
Column(
  children: [
    // Navigation
    TvTopNavBar(title: 'Browse'),
    
    // Content
    Expanded(
      child: TvChannelGrid(
        children: channelCards,
      ),
    ),
  ],
)
```

### Dual Navigation Layout
```dart
Row(
  children: [
    // Side navigation
    SizedBox(
      width: 240,
      child: TvSideNav(...),
    ),
    
    // Main content
    Expanded(
      child: SingleChildScrollView(
        child: Column(
          children: [
            HeroCarousel(...),
            TvHorizontalList(title: 'Trending', ...),
            TvHorizontalList(title: 'Recently Added', ...),
          ],
        ),
      ),
    ),
  ],
)
```

---

## Animation Patterns

### Button Hover
```dart
AnimatedScale(
  scale: _isHovered ? 1.05 : 1.0,
  duration: AppTheme.durationMd,
  curve: AppTheme.curveDefault,
  child: GestureDetector(
    onTap: onTap,
    child: YourButton(),
  ),
)
```

### Fade Transition
```dart
FadeTransition(
  opacity: animation,
  child: ContentWidget(),
)
```

### Page Transition
```dart
Navigator.push(
  context,
  PageRouteBuilder(
    transitionDuration: AppTheme.durationLg,
    pageBuilder: (_, __, ___) => NextPage(),
    transitionsBuilder: (_, anim, __, child) {
      return ScaleTransition(scale: anim, child: child);
    },
  ),
)
```

---

## Mobile Specific

### Bottom Navigation Demo
```dart
Scaffold(
  body: pages[_currentIndex],
  bottomNavigationBar: BottomNavigationBar(
    currentIndex: _currentIndex,
    onTap: (idx) => setState(() => _currentIndex = idx),
    items: [
      BottomNavigationBarItem(
        icon: Icon(Icons.home),
        label: 'Home',
      ),
      // More items...
    ],
  ),
)
```

### Responsive Grid (Mobile)
```dart
// On mobile, TvChannelGrid auto-adjusts to 2 columns
SingleChildScrollView(
  child: TvChannelGrid(
    padding: EdgeInsets.all(AppTheme.spacing16), // Mobile padding
    children: channels,
  ),
)
```

---

## Common Mistakes to Avoid

### ❌ Don't
```dart
// Using old colors
Container(color: Color(0xFF6C63FF)) // Old purple

// Inconsistent spacing
Padding(padding: EdgeInsets.only(left: 23)) // Non-standard

// Wrong font
Text('Title', style: GoogleFonts.inter(...)) // Should be Outfit

// Manual animation
AnimationController with hardcoded Duration(milliseconds: 250)

// Missing glass effect
Card(color: AppColors.surface) // Should use GlassContainer
```

### ✅ Do
```dart
// Use theme colors
Container(color: AppColors.primary)

// Standard spacing
Padding(padding: EdgeInsets.all(AppTheme.spacing16))

// Correct typography
Text('Title', style: Theme.of(context).textTheme.headlineMedium)

// Theme animations
duration: AppTheme.durationMd
curve: AppTheme.curveDefault

// Premium widgets
GlassContainer(
  child: content,
)
```

---

## File Structure

```
lib/
├── core/
│   ├── theme/
│   │   ├── app_colors.dart          ← Colors + gradients
│   │   └── app_theme.dart           ← Typography + theme data
│   └── widgets/
│       ├── glass_container.dart     ← Glassmorphism
│       ├── hero_carousel.dart       ← Featured content slider
│       ├── tv_channel_grid.dart     ← Responsive grid
│       ├── tv_modern_card.dart      ← Content cards
│       ├── tv_nav_widgets.dart      ← Navigation widgets
│       ├── tv_focusable_card.dart   ← Focus state (legacy)
│       └── [other core widgets]
├── features/
│   └── iptv/
│       └── widgets/
│           ├── channel_card.dart    ← TV channel card
│           └── [feature widgets]
└── mobile/
    └── theme/
        └── mobile_theme.dart        ← Mobile-adapted theme

main.dart                             ← Theme applied here
DESIGN_SYSTEM.md                      ← Full documentation
```

---

## Troubleshooting

### Colors look washed out
- Ensure `scaffoldBackgroundColor: AppColors.background` is set
- Check OLED display settings (true black optimization)
- Verify contrast ratio is ≥ 4.5:1

### Animations feel jerky
- Use `AppTheme.durationMd` and `curveDefault`
- Avoid nested AnimationControllers
- Check frame rate (should be 60fps)

### Cards don't have glass effect
- Use `GlassContainer` or `GlassCard`, not plain `Container`
- Ensure `BackdropFilter` parent is not constrained
- Set `blur: 15.0` for standard effect

### Text is hard to read
- Use `textSecondary` for medium emphasis (60% grey)
- Never use `textTertiary` on dark backgrounds (insufficient contrast)
- Increase letter spacing for headings

### Layout breaks on mobile
- Use `TvChannelGrid` for automatic responsive behavior
- Test with `MediaQuery.of(context).size.width`
- Set `minimumSize` for buttons on mobile

---

## Performance Optimization

### Image Loading
```dart
// Good
CachedNetworkImage(
  imageUrl: url,
  placeholder: (context, url) => SkeletonLoader(),
  cacheManager: CacheManager.instance,
)

// Bad
Image.network(url) // No caching
```

### List Rendering
```dart
// Good
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemCard(items[index]),
)

// Bad
ListView(
  children: items.map((item) => ItemCard(item)).toList(),
) // All items rendered upfront
```

### Avoiding Jank
```dart
// Use repaint boundaries
RepaintBoundary(
  child: AnimatedCard(...),
)

// Disable shadows during scroll
if (!isScrolling) {
  boxShadow: [BoxShadow(...)]
}

// Use const constructors
const SizedBox(height: 16)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2026-03-26 | Apple TV Modern redesign, new color palette, premium widgets |
| 1.0 | 2024-XX-XX | Initial theme system |

---

## Support & Questions

For detailed documentation, see: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)
For components, check: [lib/core/widgets/](lib/core/widgets/)
For examples, see: [lib/features/iptv/](lib/features/iptv/)

**Status:** ✅ Production Ready
