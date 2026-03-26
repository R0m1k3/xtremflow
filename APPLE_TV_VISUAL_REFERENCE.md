# Apple TV Design System - Visual Reference & Component Guide

## Quick Reference: Color Palette

```
┌─────────────────────────────────────────────────────────┐
│                   PRIMARY ACCENT                        │
│                    #00A0D2                              │
│                  Teal / Sky Blue                        │
│  Used for: Focus states, CTAs, interactive highlights  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                 SECONDARY ACCENT                        │
│                    #FF3B30                              │
│                   Error Red (Apple)                     │
│  Used for: Alerts, live indicators, destructive actions│
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                  SUCCESS ACCENT                         │
│                    #34C759                              │
│                   Apple Green                           │
│  Used for: Success states, confirmations, positive UI  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│           NEUTRAL GREYS (OLED Background)              │
│                                                         │
│  #000000 ███ Pure Black (base)                         │
│  #0A0A0A ███ Deep Black (lift 1)                       │
│  #1A1A1A ███ Level 1 (card surface)                    │
│  #2A2A2A ███ Level 2 (hover)                           │
│  #3A3A3A ███ Level 3 (disabled)                        │
│  #4A4A4A ███ Level 4 (divider)                         │
│  #666666 ███ Level 5 (secondary text)                  │
│  #888888 ███ Level 6 (tertiary text)                   │
│  #FFFFFF ███ White (primary text)                      │
└─────────────────────────────────────────────────────────┘
```

---

## Component Specifications: Visual Layout

### Button Hierarchy

```
PRIMARY BUTTON
┌──────────────────────────────────────────┐
│  ▶ PLAY                                  │
│                                          │
│  Height: 56px                            │
│  Width:  Variable (min 120px)            │
│  Padding: 28px horiz, 12px vert          │
│  Background: #00A0D2 (Teal)              │
│  Text: #FFFFFF, 18px w600                │
│  Border radius: 12px                     │
│  Shadow: Level 2 (subtle)                │
└──────────────────────────────────────────┘

HOVER STATE (Mouse):
┌──────────────────────────────────────────┐
│  ▶ PLAY                                  │
│  ↑ Scale: 1.02x                          │
│  ✨ Shadow: Level 3                      │
└──────────────────────────────────────────┘

FOCUS STATE (Remote/Keyboard):
╭──────────────────────────────────────────╮ ← 2px white border
│ ┌────────────────────────────────────┐ │ ← Glow: #00A0D2
│ │  ▶ PLAY                            │ │    20px blur
│ │                                    │ │
│ │  Scale: 1.05x                      │ │
│ └────────────────────────────────────┘ │
╰──────────────────────────────────────────╯


SECONDARY BUTTON
┌──────────────────────────────────────────┐
│  + ADD TO WATCHLIST                      │
│                                          │
│  Height: 56px                            │
│  Background: #2A2A2A (grey surface)      │
│  Border: 1px solid #3A3A3A               │
│  Text: #FFFFFF, 18px w600                │
│  Shadow: Level 2                         │
└──────────────────────────────────────────┘

FOCUS STATE:
╭──────────────────────────────────────────╮
│ ┌────────────────────────────────────┐ │ ← 2px #00A0D2
│ │  + ADD TO WATCHLIST                │ │
│ │  ✨ Glow: Teal                      │ │
│ └────────────────────────────────────┘ │
╰──────────────────────────────────────────╯
```

---

### Card Components (Poster - 2:3 Ratio)

```
NORMAL STATE
┌──────────────┐
│              │
│              │ 200×300px
│ Movie Poster │ or 240×360px
│              │
│              │ Radius: 12px
└──────────────┘ Shadow: Level 2
 ▼  
TITLE
METADATA


HOVER STATE (Mouse)
╭──────────────╮
│╲            ╱│ Scale: 1.04x
│ ╲  Poster  ╱ │ Shadow: Level 3
│  ╲        ╱  │ Overlay: 15% black
│   ╲      ╱   │
│    ╲    ╱    │
│     ╲  ╱     │
│      ╲╱      │
╰──────────────╯


FOCUS STATE (Remote)
╭──────────────────╮
│┌──────────────┐ │ Border: 2px #00A0D2
││              │ │ Scale: 1.06x
││   Poster     │ │ Shadow: Level 4 + glow
││   (scaled)   │ │ Overlay: 25% black
││              │ │ ✨ Glow: #00A0D2
│└──────────────┘ │    20px blur
╰──────────────────╯

Title Style: 18px w600 white
Subtitle: 14px w400 #999999
Rating: 12px w700 #FFD700 (gold)
```

---

### Text Styles - Visual Scale

```
HERO / Display Large (64px)
╔════════════════════════════════════════════╗
║  Featured Now                              ║
║  Premium cinematic experiences             ║
║  w800 / Line 1.2 / Letter -2.0px           ║
╚════════════════════════════════════════════╝

XLARGE / Display Medium (56px)
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ New on XtremFlow                        ┃
┃ w700 / Line 1.15 / Letter -1.5px        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

LARGE / Display Small (44px)
╔════════════════════════════════════════════╗
║ Recommended for You                    ║
║ w700 / Line 1.2 / Letter -1.0px           ║
╚════════════════════════════════════════════╝

TITLE XXL / Headline Large (32px)
┌──────────────────────────────────────────┐
│ Sci-Fi Collection                        │
│ w600 / Line 1.25                         │
└──────────────────────────────────────────┘

TITLE XL / Headline Medium (28px)
┌──────────────────────────────────────────┐
│ Action & Adventure                       │
│ w600 / Line 1.3                          │
└──────────────────────────────────────────┘

TITLE / Title Medium (18px)
┌──────────────────────────────────────────┐
│ Play • 2h 45m • PG-13 • 8.5★             │
│ w600 / Line 1.4                          │
└──────────────────────────────────────────┘

BODY / Body Large (16px)
┌──────────────────────────────────────────┐
│ A brilliant action film about a detective│
│ uncovering a corporate conspiracy. Highly│
│ recommend for thriller fans.             │
│ w400 / Line 1.6                          │
└──────────────────────────────────────────┘

CAPTION / Label Large (12px)
┌──────────────────────────────────────────┐
│ LIVE • 1.2M WATCHING • UPDATED 2 MIN AGO │
│ w500 / Line 1.4 / Space +0.3px           │
└──────────────────────────────────────────┘
```

---

## Shadow Elevation System

```
LEVEL 1: No Shadow (Background)
┌──────────────────┐
│                  │ Flat appearance
│  Content Area    │ Used for: App background
│                  │
└──────────────────┘


LEVEL 2: Subtle Shadow (Base Cards)
┌──────────────────┐
│                  │ Shadow 1:
│  Card            │ • 8% black, 6px blur
│                  │ • 0, 2px offset
└────────┬─────────┘ Creates: Slight lift
         ╰─ ~ 2px depth


LEVEL 3: Standard Shadow (Hover/Focus Cards)
┌──────────────────┐
│                  │ Shadow 1:
│  Card            │ • 12% black, 8px blur
│  (Hover)         │ • 0, 4px offset
│                  │
└─────────┬────────┘ Shadow 2:
          ╰── ~ 4px depth
              • 6% black, 2px blur


LEVEL 4: Elevated Shadow (Focused + Glow)
    ✨ ← Glow: #00A0D2, 16-20px blur
┌──────────────────┐
│                  │ Shadow 1:
│  Card            │ • 20% black, 12px blur
│  (Active)        │ • 0, 8px offset
│                  │
└──────────┬───────┘ Shadow 2:
           ╰─ ~ 8px depth
               • 10% black, 4px blur + glow


LEVEL 5: Maximum Elevation (Modals)
        ✨✨ ← Glow ring
    ╭─────────────╮
    │ ┌─────────┐ │
    │ │  Modal  │ │ Shadow 1:
    │ │ Content │ │ • 25% black, 16px blur
    │ │         │ │ • 0, 12px offset
    │ └─────────┘ │
    ╰─────────────╯ Shadow 2 & 3: Additional layers
     ~~~~~~~~~~~~~~~~~~~ for depth
```

---

## Animation Timing Guide

```
INPUT DELAY → ANIMATION START → ANIMATION COMPLETE
│                               │
0ms          Desktop            Desktop responsive
             0ms                100ms feedback

0ms          Touch              150-200ms feedback
             Instant            (perceived 150ms)

~300ms       Remote             ~300-400ms total
             Input lag          animation + input lag
             (typical)


CURVE TYPES VISUALIZED:

easeOutQuad (Deceleration - smooth landing)
1.0 ┼━━━∿━━━━━━━━━━━━━━ → moves fast then slows
    │  ╱
0.5 ┤ ╱
    │╱
0.0 ┴────────────────────>
    0ms      300ms      600ms

easeInOutQuad (Symmetrical - UI change)
1.0 ┼━━┱─────────┲━━━━━━
    │ ╱           ╲
0.5 ┤╱             ╲
    │                ╲
0.0 ┴─────────────────>
    0ms      150ms     200ms

easeOutCubic (Smooth navigation)
1.0 ┼━┳─────────────────
    │╱
0.5 ┤
    │
0.0 ┴─────────────────>
    0ms     300ms     600ms

Spring Curve (Celebratory)
1.0 ┼━┳━━┳━━┓
    │ │  │  ╲╱╲
0.5 ┤ │  │     ╲
    │ │ ╱
0.0 ┴──╱────────>
    0ms    250-350ms
```

---

## Navigation Focus Flow

```
TV NAVIGATION - Row/Column Grid Layout

    Item 1     Item 2     Item 3
    ┌────┐     ┌────┐     ┌────┐
    │    │     │    │     │    │
    └────┘     └────┘     └────┘

    Item 4     Item 5     Item 6
    ┌────┐  ┌─────────┐   ┌────┐
    │    │  ║ FOCUSED ║   │    │
    └────┘  ╚─ Glow ─╝    └────┘
            Scale: 1.06x
            Shadow: Level 4

    Item 7     Item 8     Item 9
    ┌────┐     ┌────┐     ┌────┐
    │    │     │    │     │    │
    └────┘     └────┘     └────┘

NAVIGATION DIRECTIONS:
↑ Up arrow      → Move to item above
↓ Down arrow    → Move to item below
← Left arrow    → Move to left item
→ Right arrow   → Move to right item
⊘ Select       → Activate focused item


FOCUS ANIMATION ON ARRIVAL:

Frame 1 (0ms):          Frame 2 (75ms):
┌────┐                  ╭─────╮
│    │ ← Approaching    │┌───┐│
└────┘                  ╰┤...│╯ ← Growing
                        │└───┘│
         Incoming →     ╰─────╯
         Scale: 1.0      Scale: 1.04

Frame 3 (150ms):        Frame 4 (200ms):
╭──────╮                ╭──────╮
│┌────┐│ ← Glow begins  │┌────┐│ ← Settled
╰┤    │╯    appearing   ╰┤    │╯    Glow visible
 │    │                  │    │
 └────┘                  └────┘
 Scale: 1.05            Scale: 1.04
                        ✨ Glow active
 Duration: 150ms        Focus complete
```

---

## Button States & Transitions

```
PRIMARY BUTTON STATE MACHINE

────────────────────────────────────────
  NORMAL STATE
────────────────────────────────────────
┌─────────────────────────────┐
│  ▶ PLAY                     │  Background: #00A0D2
│                             │  Text: #FFFFFF
│  Height: 56px              │  Scale: 1.0
│  Shadow: Level 2            │  Opacity: 1.0
└─────────────────────────────┘

        ↓ onHover / onMouseEnter (200ms easeOut)

────────────────────────────────────────
  HOVER STATE (Mouse only)
────────────────────────────────────────
┌─────────────────────────────┐
│  ▶ PLAY                     │  Background: #0092BC (15% darker)
│ (slightly larger)           │  Scale: 1.02
│                             │  Shadow: Level 3
└─────────────────────────────┘

        ↓ onFocus / onKeyDown (150ms easeOut)

────────────────────────────────────────
  FOCUS STATE (Keyboard/Remote)
────────────────────────────────────────
╭─────────────────────────────╮ ← 2px white border
│ ┌─────────────────────────┐ │
│ │  ▶ PLAY                │ │  Background: #00A0D2
│ │ (enlarged, glowing)    │ │  Border: 2px #FFFFFF
│ │                        │ │  Scale: 1.05
│ └─────────────────────────┘ │  Shadow: Level 4 + glow
╰─────────────────────────────╯

        ↓ onTap / onKeyDown (100ms)

────────────────────────────────────────
  PRESSED STATE
────────────────────────────────────────
┌─────────────────────────────┐
│  ▶ PLAY                     │  Scale: 0.98 (compressed)
│ (slightly smaller)          │  Opacity: 0.9 (feedback)
│ *haptic feedback on device* │  Duration: 100ms easeOut
└─────────────────────────────┘

        ↓ onTapEnd (150ms)

────────────────────────────────────────
  RETURN TO NORMAL
────────────────────────────────────────
```

---

## Card Hover & Focus States

```
CONTENT CARD (Movie/Show Poster)

┌──────────┐
│          │ NORMAL
│ POSTER   │ Scale: 1.0
│          │ Shadow: Level 2
│          │ Border: None
└──────────┘

    ↓ onMouseEnter (200ms easeOut)

╭─────────╮
│ POSTER  │ HOVER (Mouse)
│(scaled) │ Scale: 1.04
│ ╔════╗  │ Shadow: Level 3
│ ║    ║  │ Overlay: 15% black fade-in
│ ╚════╝  │
╰─────────╯

    ↓ onFocus (150ms easeOut)

╭═════════════╮ ← 2px border #00A0D2
│┌───────────┐│
││  POSTER  ││ FOCUS (Remote)
││ (scaled) ││ Scale: 1.06
││  ✨ Glow ││ Shadow: Level 4 + glow
│└───────────┘│ Overlay: 25% black
╰═════════════╯ ✨ Teal glow, 20px blur


ON SELECTED/FAVORITE ACTION:

┌────────────────────────────┐
│                            │ Heart appears
│  LOVED INDICATOR          │ Scale: 0 → 1.15 (spring)
│  ┌────────────────────┐    │ Duration: 250ms spring
│  │ ♥ FAVORITED       │    │ Then scale back to 1.0
│  │ (floating up)      │    │
│  └────────────────────┘    │ Celebratory spring curve
│                            │
└────────────────────────────┘
```

---

## Input Field States

```
NORMAL STATE (Unfocused)
┌─────────────────────────────┐
│ Search shows, movies, people│ Background: #1A1A1A
│                             │ Border: 1px #3A3A3A
│ Height: 48px                │ Text: #FFFFFF
└─────────────────────────────┘ Placeholder: #666666

      ↓ onMouseEnter (200ms)

┌─────────────────────────────┐
│ Search shows, movies, people│ HOVER (Mouse)
│                             │ Background: #2A2A2A
│ Height: 48px                │ Border: 1px #4A4A4A
└─────────────────────────────┘

      ↓ onFocus (150ms easeOut)

╭─────────────────────────────╮
│ ┌───────────────────────────┐│ FOCUSED (Keyboard/Remote)
│ │ Search |                  ││ Border: 2px #00A0D2
│ │ ┬───────────────────────  ││ Glow: Teal, 12px blur
│ └──┴───────────────────────┘│ Cursor visible
│ ✨ Glow: #00A0D2            │ Helper text appears
╰─────────────────────────────╯

      ↓ Input detected

┌─────────────────────────────┐
│ Search: "matrix"            │ ACTIVE (User typing)
│                             │ Text color: #FFFFFF
│ Clear ✕ appears            │ Clear button available
└─────────────────────────────┘

      ↓ onError (completion)

╭─────────────────────────────╮
│ ┌───────────────────────────┐│ ERROR STATE
│ │ Search: "abcd..."         ││ Border: 2px #FF3B30
│ │                           ││ Glow: Red, 12px blur
│ │ ⚠ No results found        ││ Error message displayed
│ └───────────────────────────┘│
╰─────────────────────────────╯
```

---

## Glass Container Visual Breakdown

```
WITHOUT GLASS
┌─────────────────────────┐
│                         │ Plain surface
│  Regular Container      │ boring, no depth
│                         │
└─────────────────────────┘


WITH GLASS (6% opacity blur)
╔═════════════════════════╗  ↑ Glass blur effect
║░░░░░░░░░░░░░░░░░░░░░░░║  ↑ Content visible through
║░ Glass Container ░░░░░║  ↑ 6% white top-left gradient
║░░░░░░░░░░░░░░░░░░░░░░░║  ↓ 4% white bottom-right grad
╚═════════════════════════╝  ↓ Premium border @12% white
   ↓ Shadow Level 3


GLASS IN FOCUS
╔═════════════════════════╗ ← Brighter glass (10%)
║░░░░░░░░░░░░░░░░░░░░░░░║ ← More visible content
║░ Glass (Active) ░░░░░║ ← 2px white border added
║░░░░░░░░░░░░░░░░░░░░░░░║ ← Increased blur (20px)
╚═════════════════════════╝
   ↓ Shadow Level 4 + glow
   ✨ Teal glow ring, 20px blur
```

---

## Grid/Layout Components

```
4K TV LAYOUT (55") - 5 items per row

┌────────────────────────────────────────────────────────┐
│ 48px margin                                      48px   │
│                                                     ↓   │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐ ┌────┐│
│  │        │  │        │  │        │  │        │ │    ││
│  │ Card 1 │  │ Card 2 │  │ Card 3 │  │ Card 4 │ │Card││
│  │        │  │        │  │        │  │        │ │ 5  ││
│  │(200×300)  │(200×300)  │(200×300)  │(200×300)  │(...││
│  └────────┘  └────────┘  └────────┘  └────────┘ └────┘│
│      ↓            ↓            ↓            ↓            ↓│
│      24px gap between columns ↑            Gap: 24px     │
│                                                          │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐ ┌────┐│
│  │        │  │        │  │        │  │        │ │    ││
│  │ Card 6 │  │ Card 7 │  │ Card 8 │  │ Card 9 │ │10  ││
│  │        │  │        │  │        │  │        │ │    ││
│  └────────┘  └────────┘  └────────┘  └────────┘ └────┘│
│      ↑                                                   ↑│
│      Gap: 24px between rows ↑                     ↑48px │
│                                                          │
└────────────────────────────────────────────────────────┘

KEY MEASUREMENTS:
• Page horizontal padding: 48px
• Card width: 200px (varies per layout)
• Card aspect: 2:3 (poster) or 16:9 (landscape)
• Horizontal gap: 24px
• Vertical gap: 24px
• Item height: Auto (based on aspect)

RESPONSIVE BREAKPOINTS:
- 4K TV (55"): 5 items, 48px padding
- Full HD TV: 4 items, 32px padding
- Tablet: 3 items, 24px padding
- Mobile: 2 items, 16px padding
```

---

## Focus Navigation Tree

```
HOME SCREEN NAVIGATION

    HEADER
    ┌─────────────────────────────────┐
    │ [⊗] XtremFlow   🔍  🔔  👤     │
    └──────────────┬────────────────┘
                   │
        ┌──────────┘
        ↓
    HERO CAROUSEL
    ╭─────────────────────────────╮
    │                             │
    │    FEATURED CONTENT         │
    │    [Play] [+ Watchlist]     │
    │                             │
    ╰──────────┬──────────────────╯
               │
        ┌──────┘
        ↓
    SECTION 1: Recommended
    ┌────┐ ┌────┐ ┌────┐ ┌────┐
    │    │ │    │ │    │ │    │  ← Focus can be on any card
    └────┘ └────┘ └────┘ └────┘
         ↓        ↓        ↓        ↓
    [Play] [Add] [Play] [Add]  ← Card actions appear on focus

        ↓ (scroll down)

    SECTION 2: Trending
    ┌────┐ ┌────┐ ┌────┐
    │    │ │    │ │    │
    └────┘ └────┘ └────┘

        ↓ (scroll down)

    SECTION 3: Channels
    ┌─────────┐ ┌─────────┐
    │ CHANNEL │ │ CHANNEL │
    │    1    │ │    2    │
    └─────────┘ └─────────┘


FOCUS PRIORITY (tvOS standard):
1. Header navigation icons (top row)
2. Hero carousel (main content area)
3. Current section cards (left-to-right, top-to-bottom)
4. Next sections below (auto-scroll into view)
5. Return to top: "Up" arrow loops to header
```

---

## Accessibility Considerations

```
CONTRAST REQUIREMENTS (WCAG AAA for TV)

Text on Teal (#00A0D2):
#FFFFFF (white): 11.3:1 ✓ EXCEEDS AAA
#000000 (black): 7.4:1  ✓ MEETS AAA

Text on Dark Grey (#1A1A1A):
#FFFFFF (white): 15.5:1 ✓ EXCEEDS AAA
#CCCCCC (light): 7.2:1  ✓ MEETS AAA

Text on Black (#000000):
#FFFFFF (white): 21:1   ✓ EXCEEDS AAA

Minimum text sizes for TV (10 feet):
• Body text (14px+): ✓ Readable at distance
• Labels (12px):    ✓ Readable at 8-10 feet
• Captions (10px):  ✓ Barely readable at 10 feet
• Micro (9px and below): ✗ NOT recommended for TV


FOCUS INDICATOR REQUIREMENTS
• Size: minimum 4px border
• Color: High contrast (#FFFFFF or #00A0D2 on dark)
• Visibility: At least 3px separation from content
• Animation: 150-200ms entrance duration
• Persistence: Clear until focus moves


MOTION PREFERENCES
• Respect prefers-reduced-motion CSS media query
• Provide instant state change as fallback
• Critical: Don't disable all animations (impacts usability)
• Solution: Reduce duration (600ms → 200ms) instead of removing
```

---

## Implementation Quick Start

### Update app_colors.dart
```dart
// Primary
static const Color primary = Color(0xFF00A0D2); // ← Changed from #00D4FF
static const Color primaryDark = Color(0xFF0092BC);
static const Color primaryLight = Color(0xFF1BC4E5);

// Grey levels (keep existing, add if missing)
static const Color surfaceLevel1 = Color(0xFF1A1A1A);
static const Color surfaceLevel2 = Color(0xFF2A2A2A);
static const Color surfaceLevel3 = Color(0xFF3A3A3A);

// Remove these or deprecate:
// static const Color categoryMovies = Color(0xFF00B4E8); // Too many colors!
```

### Update app_theme.dart - Text styles
```dart
displayLarge: GoogleFonts.outfit(
  fontSize: 64, // ← Increased from 56
  fontWeight: FontWeight.w800,
  letterSpacing: -2.0, // ← More negative
  height: 1.2, // ← Tighter for large text
  color: AppColors.textPrimary,
),

bodyLarge: GoogleFonts.inter(
  fontSize: 16,
  fontWeight: FontWeight.w400,
  letterSpacing: 0.2,
  height: 1.6, // ← Increased from 1.5 for breathing room
  color: AppColors.textSecondary,
),
```

### Update shadow system
```dart
static List<BoxShadow> get shadowLevel2 => [
  BoxShadow(
    color: Colors.black.withOpacity(0.08),
    blurRadius: 6,
    offset: const Offset(0, 2),
  ),
];

static List<BoxShadow> get shadowLevel4 => [
  BoxShadow(
    color: Colors.black.withOpacity(0.20),
    blurRadius: 12,
    offset: const Offset(0, 8),
  ),
  BoxShadow(
    color: AppColors.primary.withOpacity(0.20),
    blurRadius: 16,
    spreadRadius: 0,
  ),
];
```

---

## Testing Checklist

```
VISUAL REGRESSION TESTING

□ Colors
  □ Primary accent (#00A0D2) on all interactive elements
  □ Text colors match 4-tier system
  □ Grey levels visible and distinct
  □ Glass effects appear premium (not plastic)

□ Typography
  □ Display Large (64px) legible on 4K TV
  □ Body text at 16px readable at 10 feet
  □ Line heights create breathing room
  □ No text cutoff at screen edges

□ Spacing
  □ 48px minimum padding on TV layouts
  □ 24px gaps between grid items
  □ 12-16px internal card padding

□ Shadows
  □ Level 2 (cards): Subtle, barely visible
  □ Level 3 (hover): Visible elevation
  □ Level 4 (focus): Clear floating effect
  □ No crushed blacks on OLED

□ Animation
  □ Focus arrival: 150ms, smooth (no jank)
  □ Hover: 200ms easeOut
  □ Tap feedback: 100ms compressed, instant release

□ Accessibility
  □ Focus indicator visible at 10 feet
  □ All text meets WCAG AAA contrast
  □ Motion preferences respected
  □ Remote control navigation works smoothly

□ Cross-device
  □ Mobile layout uses 16px padding (OK)
  □ Tablet scales appropriately
  □ TV layout fully optimized (48px padding)
  □ No layout shift on focus changes
```

---

## Troubleshooting Common Issues

```
ISSUE: Colors look too dull on screen vs specification
SOLUTION: Check color profile (sRGB vs wide gamut), adjust brightness

ISSUE: Focus glow not visible at distance
SOLUTION: Increase blur radius (20px → 24px), increase opacity (20% → 25%)

ISSUE: Text too small at TV distance
SOLUTION: Increase font sizes by 2-4px, ensure minimum 14px body

ISSUE: Animations feel laggy despite correct timing
SOLUTION: Check frame rate (aim for 60fps), reduce animation duration

ISSUE: Cards feel cramped
SOLUTION: Increase spacing from 16px → 20-24px, increase card padding

ISSUE: Glass containers look plasticky
SOLUTION: Reduce opacity (8% → 6%), ensure blur is crisp (15px)

ISSUE: Focus state not clear enough
SOLUTION: Add border (2px white), increase glow radius, scale up (1.06x)

ISSUE: Buttons too small for remote navigation
SOLUTION: Increase height to min 56px, increase hit target to 60×60px

ISSUE: Shadow appears crushed on dark backgrounds
SOLUTION: Use lighter black opacity (0.15 instead of 0.25) or adjust blur
```

