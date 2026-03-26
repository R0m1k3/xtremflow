# XtremFlow Apple TV Modern Design System

## Overview

XtremFlow has been completely redesigned with a **premium Apple TV modern aesthetic** inspired by tvOS 18+. The new design system prioritizes:

- **Sophisticated Glassmorphism** - Elegant blur effects with subtle gradients
- **Premium Color Palette** - Vibrant accents (Cyan, Mint, Red) on pure black
- **Cinematic Typography** - Bold headlines (Outfit) + refined UI text (Inter)
- **Focus-Driven Interactions** - TV-friendly hover states and animations
- **Responsive Layouts** - Seamless adaptation from web to mobile

---

## Color Palette

### Backgrounds
- **`background`** (#000000) - Pure black, OLED optimized
- **`surface`** (#1C1C1E) - Primary dark surface
- **`surfaceVariant`** (#2A2A2E) - Secondary surface for hierarchy
- **`surfaceTertiary`** (#383838) - Tertiary depth layer

### Primary Accents
- **`primary`** (#00D4FF) - Main brand color (Cyan/Sky Blue)
- **`secondary`** (#FF6B6B) - Secondary accent (Soft Red)
- **`tertiary`** (#00E5BB) - Highlight accent (Mint)
- **`accent`** - Alias for primary (for consistency)

### Semantic Colors
- **`success`** (#34C759) - Success/completed state
- **`warning`** (#FF9500) - Warning/caution state
- **`error`** (#FF3B30) - Error/danger state
- **`info`** (#30B0C0) - Information state
- **`disabled`** (#8E8E93) - Disabled/inactive state

### Text Hierarchy
- **`textPrimary`** (#FFFFFF) - Main text (white)
- **`textSecondary`** (#999999) - Secondary text (60% grey)
- **`textTertiary`** (#666666) - Tertiary text (40% grey)
- **`textQuaternary`** (#404040) - Subtle text (25% grey)

### Category Colors
- **`live`** (#FF3B30) - Live streams (red)
- **`movies`** (#00B4E8) - Movie content (blue)
- **`series`** (#00E5BB) - Series content (mint)
- **`sports`** (#BF5AF0) - Sports content (purple)
- **`news`** (#FFC300) - News content (yellow)
- **`music`** (#FF2D55) - Music content (pink)

---

## Typography

### Font Stack
1. **Outfit** (headings/display) - Bold, geometric, premium feel
2. **Inter** (UI/body) - Clean, readable, high contrast
3. Fallback to system fonts

### Sizes & Weights

| Style | Size | Weight | Usage |
|-------|------|--------|-------|
| `displayLarge` | 56px | W800 | Hero titles, billboards |
| `displayMedium` | 48px | W700 | Section headers |
| `displaySmall` | 36px | W700 | Sub-titles |
| `headlineMedium` | 28px | W700 | Card titles |
| `headlineSmall` | 24px | W600 | Smaller headings |
| `titleLarge` | 20px | W600 | Labels, emphasis |
| `titleMedium` | 16px | W600 | UI elements |
| `titleSmall` | 14px | W600 | Secondary labels |
| `bodyLarge` | 16px | W400 | Primary body text |
| `bodyMedium` | 14px | W400 | Standard body |
| `bodySmall` | 12px | W400 | Secondary text |
| `labelLarge` | 14px | W700 | Button text |

---

## Spacing System (8pt base)

```dart
spacing2 = 2.0
spacing4 = 4.0
spacing8 = 8.0
spacing12 = 12.0
spacing16 = 16.0
spacing20 = 20.0
spacing24 = 24.0
spacing32 = 32.0
spacing40 = 40.0
spacing48 = 48.0
spacing56 = 56.0
spacing64 = 64.0
```

**TV Safe Margins:** Use `spacing32` (32px) for content edges on web/desktop.
**Mobile Safe Margins:** Use `spacing16` (16px) for mobile screens.

---

## Radius System

| Token | Value | Usage |
|-------|-------|-------|
| `radiusXs` | 4px | Tiny elements, toggles |
| `radiusSm` | 8px | Badges, chips |
| `radiusMd` | 12px | Buttons, inputs |
| `radiusLg` | 16px | Cards, dialogs |
| `radiusXl` | 24px | Large containers |
| `radiusXxl` | 32px | Hero sections |
| `radiusFull` | 999px | Circles, pills |

---

## Elevation & Shadows

### Elevation Levels
```dart
elevationXs = 2.0   // Subtle lift (tooltips)
elevationSm = 4.0   // Slight elevation (cards)
elevationMd = 8.0   // Standard elevation (modals)
elevationLg = 16.0  // Prominent elevation (dialogs)
elevationXl = 24.0  // Maximum elevation (top-level modals)
```

### Shadow System
Shadows automatically scale with elevation. Premium glass effects use dual shadows for depth:
- **Primary shadow:** Larger blur, higher spread (primary depth)
- **Secondary shadow:** Smaller blur, lower spread (edge definition)

---

## Animations

### Duration
```dart
durationXs = 100ms     // Quick interactions
durationSm = 150ms     // Hover states
durationBase = 200ms   // Standard transitions
durationMd = 300ms     // UI animations
durationLg = 400ms     // Page transitions
durationXl = 600ms     // Hero animations
```

### Curves
- **`curveDefault`** (easeInOutCubic) - Standard animations
- **`curveSnappy`** (fastOutSlowIn) - Apple-like feel
- **`curveSmooth`** (easeOutCubic) - Content reveal
- **`curveBouncy`** (elasticOut) - Fun interactions

---

## Core Widgets

### `GlassContainer`
Premium glassmorphism widget with backdrop blur and gradient overlay.

```dart
GlassContainer(
  borderRadius: AppTheme.radiusLg,
  padding: EdgeInsets.all(16),
  blur: 15.0,
  opacity: 0.08,
  child: YourWidget(),
)
```

### `GlassCard`
Interactive glass card with scale animations and loading states.

```dart
GlassCard(
  interactive: true,
  onTap: () => Navigator.push(...),
  child: ContentWidget(),
)
```

### `ChannelCard`
Modern channel card with:
- Live indicator (with pulse animation)
- Favorite toggle button
- EPG information display
- Hover scale effects

```dart
ChannelCard(
  streamId: channel.id,
  name: channel.name,
  iconUrl: channel.logo,
  currentProgram: epg?.title,
  isLive: true,
  playlist: playlistConfig,
  onTap: () => playChannel(channel),
)
```

### `TvModernCard`
Premium content card for movies, shows, or other media.

```dart
TvModernCard(
  id: item.id,
  title: item.title,
  imageUrl: item.posterUrl,
  rating: '8.7',
  year: '2024',
  badge: 'NEW',
  badgeColor: AppColors.primary,
  onTap: () => showDetails(item),
  onPlayTap: () => playContent(item),
)
```

### `HeroCarousel`
Full-screen featured content carousel with auto-play.

```dart
HeroCarousel(
  items: [
    HeroCarouselItem(
      id: '1',
      title: 'Breaking Bad',
      subtitle: 'Season 5 - Now Streaming',
      imageUrl: 'https://...',
      badge: 'LIMITED TIME',
      onPlay: () => play(),
    ),
  ],
  autoPlay: true,
  autoPlayInterval: Duration(seconds: 6),
)
```

### `TvChannelGrid`
Responsive grid layout for channels with flexible columns.

```dart
TvChannelGrid(
  children: channels.map((ch) => ChannelCard(...)).toList(),
  horizontalSpacing: 20,
  verticalSpacing: 20,
)
```

### `TvHorizontalList`
Horizontal scrollable list with title and smooth scrolling.

```dart
TvHorizontalList(
  title: 'Trending Now',
  children: items.map((item) => TvModernCard(...)).toList(),
  itemWidth: 200,
  spacing: 16,
)
```

### `TvTopNavBar`
Premium top navigation with search, notifications, profile.

```dart
TvTopNavBar(
  title: 'XtremFlow',
  onSearch: () => showSearchModal(),
  onNotifications: () => showNotifications(),
  onProfile: () => showProfile(),
  notificationCount: 3,
)
```

### `TvSideNav`
Vertical navigation menu with category items.

```dart
TvSideNav(
  items: [
    TvNavItem(label: 'Home', icon: Icons.home),
    TvNavItem(label: 'Live TV', icon: Icons.tv),
    TvNavItem(label: 'Movies', icon: Icons.movie),
  ],
  selectedIndex: 0,
  onItemSelected: (index) => navigate(index),
)
```

---

## Usage Guidelines

### Color Usage
- **Primary (Cyan):** Call-to-action buttons, focus states, active indicators
- **Secondary (Red):** Alerts, favorite toggles, urgent actions
- **Tertiary (Mint):** Accent highlights, success states, featured badges
- **White/Grey text:** Maintain WCAG AA contrast ratio (4.5:1 minimum)

### Typography
- **Outfit:** Only for headings/hero text (sizes 20px and above)
- **Inter:** All UI, buttons, body text
- **Letter spacing:** Increase for larger sizes (hero titles: -1.0 to -1.5), decrease for body text

### Spacing
- **Card padding:** 16px standard, 24px for premium cards
- **List spacing:** 20px horizontal, 20px vertical between items
- **Button height:** 44px standard (48px for mobile large buttons)
- **Safe margins:** 32px for TV, 16px for mobile

### Animations
- **Hover states:** Always use 200-300ms animations
- **Page transitions:** 400-600ms for hero animations
- **Loading:** Use pulse/fade animations, not spinners when possible

### Glassmorphism
- **Blur:** 15px standard, up to 20px for premium overlays
- **Opacity:** 8-12% for background colors, 15% for borders
- **Gradient:** Always include subtle gradient + border for depth
- **Shadows:** Dual shadow system for elevation

---

## Mobile Adaptations

### Touch Targets
- **Minimum button size:** 48×48px
- **Minimum tap area:** 44×44px
- **Between buttons:** 16px spacing minimum

### Typography Scaling
- **Display text:** Reduced by 8px on mobile
- **Body text:** Standard sizes (no reduction needed)
- **Buttons:** Slightly smaller (14px vs 16px)

### Navigation
- **Bottom navigation bar** for main categories
- **Horizontal scrolling** for content grids
- **Collapsible menus** for secondary options
- **Modal dialogs** for detailed information

### Bottom Navigation
- Maximum 5 items
- Icon + label style
- Bottom safe area padding
- Glass effect with elevated background

---

## Implementation Examples

### Adding a New Feature
1. Use `TvModernCard` or `ChannelCard` base
2. Extend with custom styling if needed
3. Follow spacing/animation guidelines
4. Test hover states on desktop, tap on mobile
5. Ensure text contrast ≥ 4.5:1

### Color Customization
- Never override `AppColors` constants directly
- Use `color.withOpacity()` for transparency
- Test on OLED displays for pure black background
- Avoid colors outside the defined palette

### Custom Animations
- Always import `AppTheme.durationMd` and `curveDefault`
- Keep animations under 600ms unless loading indicator
- Use `AnimatedScale`, `FadeTransition` over custom controllers
- Test at 60fps on low-end devices

---

## Performance Tips

1. **Image Loading:** Use `CachedNetworkImage` with placeholder
2. **Scroll Performance:** Enable `repaint` boundaries on large lists
3. **Animations:** Use `SingleTickerProviderStateMixin` for complex animations
4. **Memory:** Dispose controllers in `dispose()` method
5. **Rendering:** Avoid nested `LayoutBuilders` in scrollable areas

---

## Accessibility

- **Text Contrast:** All text must meet WCAG AA (4.5:1)
- **Touch Targets:** 48×48px minimum on mobile
- **Focus States:** Always visible with 2px border or scale change
- **Semantic HTML:** Use proper widget hierarchy
- **Tooltips:** Always add for icon-only buttons

---

## Export & Integration

### Update main.dart
```dart
import 'package:flutter/material.dart';
import 'lib/core/theme/app_theme.dart';
import 'lib/mobile/theme/mobile_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XtremFlow',
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
```

### Use Across App
```dart
// Colors
Container(color: AppColors.primary)

// Spacing
Padding(padding: EdgeInsets.all(AppTheme.spacing16))

// Animations
Duration animDuration = AppTheme.durationMd;
Curve animCurve = AppTheme.curveDefault;
```

---

## Future Enhancements

- [ ] Implement animations library for transitions
- [ ] Add haptic feedback for interactions
- [ ] Create dark/light theme toggle
- [ ] Implement material motion guide (motion curves)
- [ ] Add accessibility scanner integration
- [ ] Create Storybook/documentation UI

---

**Design System Version:** 2.0 Apple TV Modern
**Last Updated:** 2026-03-26
**Status:** Production Ready ✅
