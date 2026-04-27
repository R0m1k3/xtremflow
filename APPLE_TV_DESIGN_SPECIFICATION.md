# XtremFlow Apple TV Design Specification
## Comprehensive Assessment & Implementation Guide

---

## PART 1: CURRENT DESIGN SYSTEM ANALYSIS

### 1.1 Current Color System (app_colors.dart)

#### ✅ **What's Working Well**

**Background Palette:**
- Pure black (#000000) - OLED optimized ✓
- Surface layers (#1C1C1E, #2A2A2E, #383838) - Good hierarchy ✓
- Proper contrast against text

**Primary Accents:**
- Cyan (#00D4FF) - Primary interactive
- Mint (#00E5BB) - Secondary accent
- Red (#FF6B6B) - Soft error state
- Gold (#FFD700) - Premium/ratings

**Text Hierarchy:**
- TextPrimary (#FFFFFF) - Pure white ✓
- TextSecondary (#999999) - 60% opacity ✓
- TextTertiary (#666666) - 40% opacity ✓
- TextQuaternary (#404040) - 25% opacity ✓

**Semantic Colors:**
- Success: #34C759 (Apple green)
- Warning: #FF9500 (Apple orange)
- Error: #FF3B30 (Apple red)
- Info: #30B0C0 (Cyan variant)

**Glass Effects:**
- glassBackground: white @ 8% opacity
- glassBorder: white @ 15% opacity
- glassPremium: white @ 12% opacity

---

#### ⚠️ **What's NOT Apple TV-like**

**1. Color Vibrancy (BIGGEST ISSUE)**
- Current primary cyan (#00D4FF) is TOO BRIGHT and ELECTRIC
- Apple TV uses VERY SUBTLE accent colors, understated elegance
- Real Apple TV focus states use: soft whites, gentle grays, minimal color
- Current colors feel more like "gaming UI" than "premium streaming service"

**2. Lack of True Metal/Premium Finishing**
- No subtle grain or texture layer
- Missing true metallic highlights
- No depth separation between depth levels
- Surfaces feel flat despite glass effects

**3. Category Color Over-branding**
- Current: Live (#FF3B30), Movies (#00B4E8), Series (#00E5BB), Sports (#BF5AF0)
- Problem: Too saturated, creates visual noise
- Apple TV: Uses ONE primary accent, category distinction via typography + placement

**4. Accent Color Saturation**
```
Current:
- Primary:     #00D4FF (Saturation: 100%, Lightness: 50%)
- Secondary:   #FF6B6B (Saturation: 100%, Lightness: 57%)
- Tertiary:    #00E5BB (Saturation: 100%, Lightness: 54%)

Apple TV Ideal:
- Primary:     #00B8E6 (Saturation: ~80%, Lightness: 53%) - Slightly less vibrant
- Secondary:   #FF3B30 (Apple Red - Saturation: 90%)
- Tertiary:    #5AC8FA (Sky Blue - more refined)
```

**5. Glass Opacity Levels**
- Current: 8%, 12%, 15% - quite visible
- Apple TV glass: 6-10% - more subtle refinement
- Problem: Current glass looks too opaque, less cinematic

---

### 1.2 Current Typography System (app_theme.dart)

#### ✅ **What's Working**

**Font Stack:**
- Outfit - Headlines (modern, geometric)
- Inter - UI (clean, professional)
- Smart fallback strategy

**Type Scale:**
```
Display Large:    56px / w800 / -1.5 letter spacing
Display Medium:   48px / w700 / -1.0 letter spacing
Display Small:    36px / w700 / -0.5 letter spacing
Headline Medium:  28px / w700 / -0.3 letter spacing
Headline Small:   24px / w600
Title Large:      20px / w600
Title Medium:     16px / w600
Title Small:      14px / w600
Body Large:       16px / w400 / 1.5 line height
Body Medium:      14px / w400
Body Small:       12px / w400
Label Large:      14px / w700
Label Medium:     12px / w600
Label Small:      10px / w600
```

**Issues:**
1. Line heights too tight for TV viewing (some at 1.1 - hard to read from distance)
2. Display Large (56px) - extreme for TV interface, should be reserved for hero only
3. Missing size for smaller UI labels (8px for badges)
4. Letter-spacing on large text creates visual awkwardness at TV distances

---

### 1.3 Spacing System (app_theme.dart)

#### Current (8pt Grid)
```
spacing2:   2px
spacing4:   4px
spacing8:   8px
spacing12:  12px
spacing16:  16px
spacing20:  20px
spacing24:  24px
spacing32:  32px
spacing40:  40px
spacing48:  48px
spacing56:  56px
spacing64:  64px
```

#### ⚠️ Issue: TV Viewing Distance
- Standard TV viewing: 8-10 feet away
- Current spacing assumes ~2 feet (desktop)
- Apple TV minimum comfortable spacing: 16pt minimum
- Current 8pt gaps are INVISIBLE at TV distance

#### Recommended Adjustments:
```
Desktop/Tablet (current - good)
spacing8:   8px   (internal card spacing)
spacing16:  16px  (minimum external spacing)
spacing24:  24px  (default sections)
spacing32:  32px  (major sections)

TV (needs expansion)
spacing40:  40px  (minimum comfortable)
spacing48:  48px  (default safe area)
spacing56:  56px  (breathing room)
spacing64:  64px  (major section breaks)
```

---

### 1.4 Radius System (app_theme.dart)

#### Current
```
radiusXs:   4px
radiusSm:   8px
radiusMd:   12px
radiusLg:   16px
radiusXl:   24px
radiusXxl:  32px
radiusFull: 999px
```

#### ⚠️ Issue: Inconsistency with Apple TV
- Apple TV uses: 8px, 12px, 20px (not 24px)
- No 4px radius on Apple TV (too sharp)
- Large content cards use 16-20px, not 32px

---

### 1.5 Elevation/Shadow System (Current Implementation)

#### Current Definition
```
elevationXs:  2.0
elevationSm:  4.0
elevationMd:  8.0
elevationLg:  16.0
elevationXl:  24.0
```

#### ⚠️ **Major Issue: Too Simplistic**

Current glass shadow (from _AppThemeExtension):
```dart
BoxShadow(
  color: Colors.black.withOpacity(0.2),
  blurRadius: 20,
  spreadRadius: -5,
)
```

**Problems:**
1. Single shadow only - lacks depth
2. Blur radius too large (20pt) - fuzzy instead of crisp
3. Spread radius -5 creates weird contraction effect
4. Focus shadow is too bright (0.4 opacity) - distracting

**Apple TV Shadow Pattern:**
- Layer 1: Ambient shadow (far, soft, dark)
- Layer 2: Penumbra shadow (mid, medium, subtle)
- Layer 3: Umbra shadow (close, small, sharp)

---

### 1.6 Animation System (app_theme.dart)

#### ✅ **Working Well**
```
durationXs:     100ms
durationSm:     150ms
durationBase:   200ms
durationMd:     300ms
durationLg:     400ms
durationXl:     600ms
```

Curves:
```
curveDefault:  easeInOutCubic
curveSnappy:   fastOutSlowIn
curveSmooth:   easeOutCubic
curveBouncy:   elasticOut
```

#### ⚠️ **Issues:**
1. **No deceleration curve** - Apple TV loves `easeOutQuad` for smooth deceleration
2. **No spring animation** - Missing snappy spring curves (dampingRatio: 0.8)
3. **easeInOutCubic too aggressive** - Should be easeOutCubic for UI
4. **Missing intermediate duration**: 250ms (between 200-300)
5. **elasticOut too bouncy** - Creates visual chaos on TV

---

### 1.7 Component Styling (Current)

#### Cards (CardThemeData)
```dart
color: AppColors.surface
shape: RoundedRectangleBorder(
  borderRadius: 16px,
  border: 1px solid AppColors.border
)
```

**Issue:** No elevation effect - cards sit flat

#### Buttons (FilledButtonThemeData)
```dart
backgroundColor: AppColors.primary (#00D4FF)
padding: 24px horizontal, 12px vertical
borderRadius: 12px
```

**Issues:**
1. Padding too small for TV (44px button height minimum)
2. Radius 12px conflicts with content card radius (16px)
3. No focus indicator for remote control

#### Inputs
```dart
fillColor: AppColors.surface
borderRadius: 12px
border: 1.5px solid AppColors.border
```

**Issues:**
1. No focus/active state styling
2. Cursor invisible at TV distance
3. No clear "current field" indicator

---

## PART 2: What's NOT Apple TV-like

### 2.1 Missing Apple tvOS 18+ Characteristics

#### 1. **Insufficient Focus State Design**
**Apple TV Focus System:**
- ~60-70% of screen space dedicated to large touch targets
- Focus state: Massive scale increase (1.1x minimum), shadow glow, border highlight
- Current system: Modest scale (1.04-1.06x), insufficient visual feedback

**Why it matters for TV:**
- Users navigate with remote, not mouse
- Focus MUST be unmissable from 10 feet away
- Visual feedback delay > 200ms creates "laggy" feeling

#### 2. **Insufficient Color Hierarchy for Distance Viewing**
**Apple TV Pattern:**
- 70% neutral greys/blacks
- 25% surface variations (slight opacity shifts)
- 5% accent color used ONLY for focus states
- Current: 20% accent usage (too much noise)

#### 3. **No Cinematic Depth Separation**
**Apple TV Approach:**
- Objects in "background" are nearly invisible (opaque ~5%)
- Objects in "focus layer" are fully opaque + highlighted
- Current: All surfaces equally visible

#### 4. **Missing Micro-interaction Details**
**What Apple TV does:**
- Item tap: subtle scale (1.02x), no spring
- Item focus: scale + glow shadow (appears to float)
- Item loading: gentle pulse or spinning indicator
- Current: Basic scale sans sophistication

#### 5. **Oversaturation of Effects**
**Current issues:**
- Every card has border + shadow + gradient
- Text has too many weights in use (w400, w600, w700, w800 all common)
- Too many accent colors creating visual noise
- Glass effect on 50+ elements

**Apple TV:**
- 80% of elements use ONE style
- Accent colors reserved for interactive states only
- Glass effect used sparingly (max 5-10% of UI)

#### 6. **Lack of Content-First Design**
**Apple TV Philosophy:**
- Content images dominate
- UI is invisible until needed
- Minimal borders, overlays, decorations
- Current: UI elements compete with content

#### 7. **No Hierarchy of Attention**
**Current state:**
- All cards look equally important
- Feature cards not visually distinguished from regular cards
- Category badges fight for attention

**Apple TV:**
- Hero image occupies 40% of screen
- Related items in smaller cards (20-30% screen)
- Metadata minimized below cards
- Information architecture visible only through layout

#### 8. **Animation Sophistication Gap**
**Apple TV animations:**
```
Focus arrival:    300-400ms easeOut (decelerate as approaching)
Item tap:         100-150ms easeOut with 1.02x scale
Navigation:       400-600ms easeOut with parallax
Page transition:  600ms easeOut with fade
Loading:          smooth loop, no janky "bounce"
```

**Current:** Generic easeInOutCubic on all interactions

#### 9. **Missing Typography Breathing Room**
Apple TV uses:
- Large line-height (1.4-1.6) making text spacious, easy to read
- Letter-spacing only on ALL-CAPS text
- H1 (hero) size: 44-56px (current correct)
- H2 (section): 24-28px (current correct)
- Body: 14-16pt line-height 1.5+ (current: 1.5, could be 1.6)

#### 10. **No Seasonal/Content-Specific Theming**
Apple TV adapts colors based on featured content blend. Current: Static colors.

---

### 2.2 Technical Gaps

#### Missing React Patterns
1. **No focus context provider** - hard to manage focus state without it
2. **No animated page transitions** - feels abrupt
3. **No parallax scrolling** - flatness on large screens
4. **No responsive scaling** - doesn't adjust for viewing distance

#### Missing Accessibility Features
1. **No motion preferences** - some users need reduced motion
2. **No high-contrast mode** - current colors fail WCAG AAA on TV
3. **No text scaling** - users with vision impairment can't zoom

---

## PART 3: Apple tvOS 18+ Modern Design Standards

### 3.1 Design Philosophy

**Core Tenets:**
1. **Content First** - UI is invisible servant to content
2. **Cinematic Staging** - Treat UI like film cinematography
3. **Intentional Simplicity** - Every element must justify its existence
4. **Premium Materiality** - Surfaces feel substantial and crafted
5. **Subtle Animation** - Motion guides, not distracts
6. **Focus-Driven UX** - Remote control is primary input

---

### 3.2 Color Palette Standards

#### **Semantic Color Mapping (NEW)**

**Primary Accent (Interactive States):**
```
Name:       Teal Blue (primary focus)
Hex:        #00A0D2  (refined from #00D4FF)
RGB:        0, 160, 210
HSL:        193°, 100%, 41%
Usage:      Focus highlights, CTA buttons, selected states
Notes:      ~20% less bright than current, more sophisticated
```

**Secondary Accent (Content Categories):**
```
Name:       Coral Red (secondary/live content)
Hex:        #FF3B30  (Apple standard)
RGB:        255, 59, 48
HSL:        4°, 100%, 59%
Usage:      Live indicators, warnings, secondary CTAs
Notes:      Slightly desaturated version for TV
```

**Tertiary Accent (Success/Premium):**
```
Name:       Mint Green (achievements, premium)
Hex:        #00D4AA  (refined from #00E5BB)
RGB:        0, 212, 170
HSL:        164°, 100%, 42%
Usage:      Success states, premium badges, highlights
Notes:      Slightly desaturated, more elegant
```

#### **Neutral Palette (NEW - TV Optimized)**

**Blacks (OLED Optimized):**
```
Pure Black (base):          #000000
Deep Black (slight lift):   #0A0A0A
```

**Greys (Sophisticated Progression):**
```
Grey Level 1 (darkest):     #1A1A1A  (new: slightly above pure black)
Grey Level 2:               #2A2A2A  (cards, surface)
Grey Level 3:               #3A3A3A  (hover states)
Grey Level 4:               #4A4A4A  (disabled, secondary)
Grey Level 5:               #666666  (secondary text)
Grey Level 6:               #888888  (tertiary text)
White (primary text):       #FFFFFF
```

**Why different from current:**
- Current uses #FF3B30 (red) for too many states
- New palette uses greys for 80% of UI, color for 5-10% focus states only

#### **Semantic Status Colors (Refined, Apple Standard):**

```
Success:     #34C759  (Apple green - unchanged, perfect)
Caution:     #FF9500  (Apple orange - unchanged, perfect)
Error:       #FF3B30  (Apple red - unchanged, perfect)  
Info:        #32ADE6  (Apple blue - refined from #30B0C0)
Focused:     #FFFFFF  (pure white - for max clarity)
```

#### **Category Colors (SIMPLIFIED - TV Focused):**

**Old way (6 category colors):**
```
Live:        #FF3B30  
Movies:      #00B4E8
Series:      #00E5BB
Sports:      #BF5AF0
News:        #FFC300
Music:       #FF2D55
Problem: Creates 6-color UI chaos
```

**New way (Typography + Layout only):**
```
All categories use: Single accent color (#00A0D2)
Distinction via:
- Badge text ("LIVE", "NEW SERIES")
- Position in grid (featured gets larger treatment)
- Content image blend (extract primary color from poster)
```

#### **Glass Effects (Refined):**

```
Glass Background (base):     rgba(255, 255, 255, 0.06)  (6% opacity - refined from 8%)
Glass Border:                rgba(255, 255, 255, 0.12)  (12% opacity - refined from 15%)
Glass Premium:               rgba(255, 255, 255, 0.10)  (10% opacity)
Frosted (strong glass):      rgba(255, 255, 255, 0.08) + blur(20) + saturation(120%)
```

**Why change:**
- 8% was too visible, creates "plastic" feel
- 6% achieves true premium glass appearance
- Reduced opacity makes background content readable

---

### 3.3 Typography Hierarchy (COMPLETE REDESIGN)

#### **Font Selection**

**Headlines:** SF Pro Display (fallback: Outfit)
- Geometric, spacious letterforms
- Perfect for TV display
- Excellent hinting at large sizes

**Body/UI:** SF Pro Text (fallback: Inter)
- Optimized for smaller sizes
- Excellent legibility at distance
- Professional appearance

**Monospace:** Menlo (fallback: Courier Prime)
- Code, timestamps, tech specs

#### **Complete Type Scale (for TV viewing)**

```
HERO / Display Large
  Size:           64px
  Weight:         800 (Bold)
  Line Height:    1.2  (77px)
  Letter Space:   -2.0px
  Usage:          Title screen, movie hero
  Example Font:   SF Pro Display

XLARGE / Display Medium
  Size:           56px
  Weight:         700 (Semibold)
  Line Height:    1.15  (64px)
  Letter Space:   -1.5px
  Usage:          Page titles, featured content
  
LARGE / Display Small
  Size:           44px
  Weight:         700 (Semibold)
  Line Height:    1.2  (53px)
  Letter Space:   -1.0px
  Usage:          Section headers, card titles
  
TITLE XXL / Headline Large
  Size:           32px
  Weight:         600 (Semibold)
  Line Height:    1.25  (40px)
  Letter Space:   -0.5px
  Usage:          Subsection headers, prominent labels
  
TITLE XL / Headline Medium
  Size:           28px
  Weight:         600 (Semibold)
  Line Height:    1.3  (36px)
  Letter Space:   -0.3px
  Usage:          Card titles, strong emphasis
  
TITLE LARGE / Headline Small
  Size:           22px
  Weight:         600 (Semibold)
  Line Height:    1.4  (31px)
  Letter Space:   0px
  Usage:          Button text, labels
  
TITLE / Title Large
  Size:           18px
  Weight:         600 (Semibold)
  Line Height:    1.4  (25px)
  Letter Space:   0px
  Usage:          Prominent UI elements
  
LABEL / Title Medium
  Size:           16px
  Weight:         600 (Semibold)
  Line Height:    1.5  (24px)
  Letter Space:   0px
  Usage:          Navigation, buttons, inputs
  
BODY LARGE / Body Large
  Size:           16px
  Weight:         400 (Regular)
  Line Height:    1.6  (26px)
  Letter Space:   0.2px
  Usage:          Primary content text, descriptions
  
BODY MEDIUM / Body Medium
  Size:           14px
  Weight:         400 (Regular)
  Line Height:    1.6  (22px)
  Letter Space:   0.2px
  Usage:          Secondary content, metadata
  
BODY SMALL / Body Small
  Size:           12px
  Weight:         400 (Regular)
  Line Height:    1.5  (18px)
  Letter Space:   0.15px
  Usage:          Tertiary text, timestamps, specs
  
CAPTION LARGE / Label Large
  Size:           12px
  Weight:         500 (Medium)
  Line Height:    1.4  (17px)
  Letter Space:   0.3px
  Usage:          Badge text, tabs, secondary labels
  
CAPTION SMALL / Label Small
  Size:           11px
  Weight:         500 (Medium)
  Line Height:    1.4  (15px)
  Letter Space:   0.3px
  Usage:          Small badges, tertiary labels
  
MICRO / Label XSmall (NEW)
  Size:           10px
  Weight:         600 (Semibold)
  Line Height:    1.2  (12px)
  Letter Space:   0.5px
  Usage:          Tiny badges, version numbers
```

#### **Key Improvements Over Current:**

| Metric | Current | New | Benefit |
|--------|---------|-----|---------|
| Display Large | 56px | 64px | Better hero presence |
| Body Line Height | 1.5 | 1.6 | More breathing space |
| Spacing | -1.5 to -0.5 | -2.0 to 0 | Refined hierarchy |
| Font Weights | 4 types | 3 types | Simpler, cleaner |
| Minimum Body | 12px | 10px | Flexibility for small UI |
| Letter Spacing | Random | Systematic | Professional, consistent |

---

### 3.4 Spacing System (TV-First)

#### **Interactive Spacing Grid (12pt base on TV)**

```
Compact (internal element spacing):
  xs:       4px   (icon padding)
  sm:       8px   (button padding, internal card gaps)
  md:       12px  (default padding, between elements)

Normal (standard spacing):
  lg:       16px  (standard card padding)
  xl:       20px  (section gap)
  2xl:      24px  (section padding)
  3xl:      32px  (major section padding)

Comfortable (breathing room):
  4xl:      40px  (section separation on TV)
  5xl:      48px  (hero bottom padding, card grid gap)
  6xl:      56px  (page top/bottom safe area)
  7xl:      64px  (major layout break)

Large Scale (TV safe areas):
  8xl:      80px  (page margins on 4K)
  9xl:      96px  (hero section bottom padding)
```

#### **Responsive Scaling (for different screen sizes)**

```
Mobile (portrait):
  Base padding:    16px
  Section gap:     12px
  Grid gap:        12px
  Min button height: 44px

Tablet (landscape):
  Base padding:    24px
  Section gap:     20px
  Grid gap:        16px
  Min button height: 48px

Desktop (27"+):
  Base padding:    32px
  Section gap:     24px
  Grid gap:        20px
  Min button height: 48px

TV (55"+):
  Base padding:    48px
  Section gap:     32px
  Grid gap:        24px
  Min button height: 56px
```

---

### 3.5 Elevation & Shadow System (Cinematic)

#### **Apple TV Multi-Layer Shadow (Depth System)**

**Level 1 - Flat (No Shadow)**
```
Usage: Background layers, disabled states
Shadows: None
```

**Level 2 - Ambient (Subtle, far-field)**
```
Box-shadow 1:
  Color:        rgba(0, 0, 0, 0.08)
  Blur radius:  6px
  Spread:       0px
  Offset:       0px, 2px
Note: Indicates presence, minimal depth
```

**Level 3 - Card (Standard, TV default)**
```
Box-shadow 1 (ambient):
  Color:        rgba(0, 0, 0, 0.12)
  Blur radius:  8px
  Spread:       0px
  Offset:       0px, 4px

Box-shadow 2 (subtle detail):
  Color:        rgba(0, 0, 0, 0.06)
  Blur radius:  2px
  Spread:       0px
  Offset:       0px, 1px

Combined: Depth with sophistication
```

**Level 4 - Elevated (Focused elements, hover)**
```
Box-shadow 1 (ambient):
  Color:        rgba(0, 0, 0, 0.20)
  Blur radius:  12px
  Spread:       0px
  Offset:       0px, 8px

Box-shadow 2 (penumbra):
  Color:        rgba(0, 0, 0, 0.10)
  Blur radius:  4px
  Spread:       0px
  Offset:       0px, 2px

Box-shadow 3 (focus glow - when selected):
  Color:        rgba(0, 160, 210, 0.20)  [Teal primary]
  Blur radius:  16px
  Spread:       0px
  Offset:       0px, 0px

Combined: Floating effect, appears to float 16px off surface
```

**Level 5 - Lifted (Modals, critical content)**
```
Box-shadow 1 (ambient):
  Color:        rgba(0, 0, 0, 0.25)
  Blur radius:  16px
  Spread:       0px
  Offset:       0px, 12px

Box-shadow 2 (penumbra):
  Color:        rgba(0, 0, 0, 0.15)
  Blur radius:  6px
  Spread:       0px
  Offset:       0px, 4px

Box-shadow 3 (umbra):
  Color:        rgba(0, 0, 0, 0.08)
  Blur radius:  2px
  Spread:       0px
  Offset:       0px, 1px

Combined: Extreme depth for modals, overlays
```

#### **Focus State Shadow (for interactive elements)**

**When element receives focus (remote/keyboard):**
```
Box-shadow 1 (glow effect):
  Color:        rgba(0, 160, 210, 0.30)    [Teal primary, 30% opacity]
  Blur radius:  20px
  Spread:       2px
  Offset:       0px, 0px

Creates: Glowing, "floating" effect that appears to hover above surface
Animation: Fade in over 150ms easeOut, fade out over 200ms easeInOut
```

#### **Summary Table**

| Level | Usage | Primary Shadow | Accent Shadow | Glow |
|-------|-------|-----------------|--------------|------|
| 1 | Background, Disabled | None | None | None |
| 2 | Base surfaces | 0.08 @ 6px blur | - | - |
| 3 | Cards, Containers | 0.12 @ 8px + 0.06 @ 2px | Yes | Optional |
| 4 | Hover/Focus | 0.20 @ 12px + 0.10 @ 4px | Yes | #00A0D2 20px |
| 5 | Modals, Overlays | 0.25 @ 16px + 0.15 @ 6px + detail | Yes | Optional |

---

### 3.6 Animation System (Cinematic Timing)

#### **Core Duration (Orchestration)**

```
Entrance timing:    300-400ms
Interaction:        150-200ms
Navigation:         600-800ms
Transition:         1000-1200ms

Device/Input Correlation:
- Touch: instant (0ms) → 150ms feedback
- Remote: 300ms input lag → 150ms animation = 450ms felt
- Keyboard: 0ms → 150ms minimum animation
```

#### **Duration Scale (Complete)**

```
50ms:   MICRO   - Icon rotation, minimal state change
100ms:  XS      - Accessibility required minimum
150ms:  SM      - Button tap, quick response
200ms:  BASE    - Standard UI change, focus movement
300ms:  MD      - Card hover, scroll deceleration
400ms:  LG      - Page focus change, moderate navigation
600ms:  XL      - Full page transition, entrance animation
800ms:  XXL     - Modal entrance, major layout shift
```

#### **Curve Specifications (Apple TV Patterns)**

**Entrance (Deceleration - starts fast, ends slow):**
```
Name:       easeOutQuad (or fastOutSlowIn)
Bezier:     cubic-bezier(0.25, 0.46, 0.45, 0.94)
Timing:     300-600ms
Usage:      Page load, item entrance, scroll arrival
Feel:       Objects smoothly arrive, natural deceleration
Example:    Hero image fades and scales in
```

**Interaction (Quick response - symmetrical):**
```
Name:       easeInOutQuad (or easeInOutCubic)
Bezier:     cubic-bezier(0.42, 0, 0.58, 1)
Timing:     150-200ms
Usage:      Button press, item tap, quick transitions
Feel:       Responsive, snappy, purposeful
Example:    Card scales 1.02x on focus
```

**Navigation (Deceleration with precision):**
```
Name:       easeOutCubic
Bezier:     cubic-bezier(0.215, 0.61, 0.355, 1)
Timing:     400-600ms
Usage:      Focus movement, carousel slide, page change
Feel:       Smooth travel, confident landing
Example:    Focus ring travels to next item
```

**Spring Micro-interactions (Bounce):**
```
Name:       cubicBezier w/ spring
Bezier:     cubic-bezier(0.175, 0.885, 0.32, 1.275)
Timing:     250-350ms
Damping:    0.75
Usage:      Like/favorite button, achievement unlock
Feel:       Celebratory, satisfying feedback
Example:    Heart icon springs up on favorite tap
```

**Loading (Smooth loop):**
```
Name:       linear
Timing:     1000ms (one full rotation)
Usage:      Loading spinner, buffering indicator
Feel:       Consistent, predictable
Note:       Never use easeInOut for rotating loaders - jittery
```

#### **Animation Composition (Sequences)**

**Focus Arrival (Remote Control):**
```
Timeline:
0ms:        Item becomes focused (input event)
0-50ms:     Border color changes (fast)
0-150ms:    Scale 1.0 → 1.05 (easeInOutQuad)
0-200ms: Scale 1.05 → 1.04 (easeOutQuad - settle)
100-200ms:  Shadow color changes to accent (easeOut)
150-300ms:  Shadow blur increases (easeOut)

Result: Smooth, confident arrival with no overshoot
```

**Tap Feedback (Button):**
```
Timeline:
0ms:        Tap detected
0-50ms:     Scale 1.0 → 0.98 (instant)
50-100ms:   Scale 0.98 → 1.0 (easeOutQuad)
0-80ms:     Opacity 1.0 → 0.9 → 1.0 (easeOut)

Result: Tactile feedback without spring bounce
```

**Page Transition:**
```
Timeline:
0-200ms:    Fade out current page (easeInQuad)
200-600ms:  Scale current → 0.95 (easeOutQuad)
200-600ms:  Fade in new page + scale 1.0 (easeOutQuad)
400-800ms:  Focus moves to target item (nested animation)

Result: Cinematic flow, parallax effect
```

### 3.7 Component Specifications

#### **Buttons (Complete)**

**Primary Button (Main CTA)**
```
Size:
  Height:       56px (TV comfortable)
  Padding:      24px horizontal, 12px vertical
  Target size:  min 56px × 56px (touch target)

Normal state:
  Background:   #00A0D2 (teal primary)
  Foreground:   #FFFFFF (white)
  Border:       none
  Shadow:       Level 2 (subtle)
  Radius:       12px

Hover state (mouse):
  Background:   #0092BC (darker teal, -15% lightness)
  Scale:        1.02x
  Shadow:       Level 3 (elevated)
  Duration:     200ms easeOut

Focus state (remote/keyboard):
  Background:   #00A0D2 (unchanged)
  Foreground:   #FFFFFF
  Border:       2px solid #FFFFFF
  Shadow:       Level 4 + glow (teal)
  Scale:        1.05x
  Duration:     150ms easeOut

Pressed state:
  Scale:        0.98x
  Duration:     100ms easeOut
  Duration:     100ms easeOut

Disabled state:
  Background:   #4A4A4A (neutral grey)
  Foreground:   #888888 (dimmed text)
  Opacity:      0.6
  Cursor:       not-allowed
```

**Secondary Button (Alternative CTA)**
```
Size:       Same as primary (56px min)
Normal:
  Background:   #2A2A2A (surface variant)
  Foreground:   #FFFFFF
  Border:       1px solid #3A3A3A
  
Hover:
  Background:   #3A3A3A
  Border:       1px solid #4A4A4A

Focus:
  Foreground:   #FFFFFF
  Border:       2px solid #00A0D2 (accent)
  Glow:         Teal (#00A0D2) 16px
```

**Text Button (Tertiary)**
```
Normal:
  Foreground:   #00A0D2 (accent)
  Background:   transparent

Hover:
  Foreground:   #0092BC (darker teal)
  Background:   rgba(0, 160, 210, 0.08)
  
Focus:
  Foreground:   #00A0D2
  Background:   rgba(0, 160, 210, 0.12)
  Border:       2px solid #FFFFFF underneath text
```

---

#### **Cards (Complete)**

**Content Card (Movie, Show, Live)**

```
Container:
  Size:         Width varies, 2:3 aspect ratio (poster)
  Background:   #1A1A1A (deep grey)
  Border:       none (image-only clean look)
  Radius:       12px
  Shadow:       Level 2 (subtle)

Normal state:
  Scale:        1.0x
  Overlay:      none
  
Hover state:
  Scale:        1.04x
  Shadow:       Level 3 (elevated)
  Overlay:      rgba(0, 0, 0, 0.15) fade in 200ms
  
Focus state:
  Scale:        1.06x
  Shadow:       Level 4 + glow
  Overlay:      rgba(0, 0, 0, 0.25)
  Border:       2px solid #00A0D2
  
Active/Selected:
  Badge:        "PLAYING" or checkmark
  Border:       3px solid #00A0D2
  Glow:         #00A0D2, 20px blur
```

**Info Card (Channel, Provider)**

```
Container:
  Background:   #1A1A1A with 1px border #3A3A3A
  Padding:      16px
  Radius:       12px
  Shadow:       Level 2

Content:
  Title:        18px, w600, white
  Subtitle:     14px, w400, grey
  Badge:        Optional (12px, accent color)

Hover:
  Background:   #2A2A2A
  Scale:        1.02x
  Shadow:       Level 3

Focus:
  Border:       2px solid #00A0D2
  Glow:         20px teal

Active:
  Backend:      #00A0D2 10% opacity
  Border:       2px solid #00A0D2
```

---

#### **Input Fields (Forms, Search)**

```
Normal state:
  Background:   #1A1A1A
  Border:       1px solid #3A3A3A
  Text color:   #FFFFFF
  Placeholder:  #666666
  Height:       48px (comfortable for remote)
  Padding:      12px horizontal, 12px vertical
  Radius:       12px

Hover state (mouse):
  Background:   #2A2A2A
  Border:       1px solid #4A4A4A

Focus state (keyboard/remote):
  Background:   #1A1A1A
  Border:       2px solid #00A0D2
  Shadow:       glow, teal, 12px
  Cursor:       (visible text input cursor)

Error state:
  Border:       2px solid #FF3B30
  Shadow:       glow, red, 12px
  Helper text:  red, 12px

Success state:
  Border:       1px solid #34C759
  Helper text:  green, 12px

Disabled state:
  Background:   #2A2A2A
  Opacity:      0.5
  Cursor:       not-allowed
```

---

#### **Navigation (Focus-Driven)**

**Top Navigation Bar**
```
Height:       64px (including padding)
Background:   rgba(26, 26, 26, 0.95) with glass blur
Padding:      16px horizontal, 8px vertical
Items:        Spaced 48px apart (TV comfortable)

Logo/Title:   32px, w700, white, SF Pro Display
Actions:      Icon + text labels (20px icons, 14px labels)

Focus state:  
  Icon:       Glow with accent color
  Border:     2px solid white underneath text
  Scale:      1.1x
  Duration:   150ms easeOut
```

**Side Navigation (if needed)**
```
Width:        280px (4K TV comfortable)
Background:   #0A0A0A deep grey
Padding:      24px

Items:
  Height:     56px (large touch targets)
  Margin:     12px vertical
  Text:       18px, w600
  Icon:       24px, aligned left
  
Normal:
  Color:      #999999 (secondary text)
  Background: transparent

Focus:
  Color:      #FFFFFF
  Background: #00A0D2 10% opacity
  Border left: 3px solid #00A0D2
  Scale:      1.02x
```

**Grid Cards (Channel List, Content Grid)**
```
Per Row (responsive):
  4K TV (55"+):   5-6 items per row
  Full HD TV:     4 items per row
  Tablet:         3 items per row
  Mobile:         2 items per row

Spacing:
  Horizontal:     24px gap
  Vertical:       24px gap
  Page padding:   48px all sides (TV)

Card size (TV):
  Width:          aspect ratio 1:1 or 16:9
  Height:         auto or fixed
  Min size:       200×200px

Focus behavior:
  Focus cycle:    Horizontal first, wrap to next row
  Auto-scroll:    Keep focused item centered
  Focus zone:     Don't scale > 1.08x (prevent overlap)
```

---

### 3.8 Glass Morphism Specifications

#### **Premium Glass Effect (Advanced)**

**Usage Rules:**
- Max 5-10% of screen use glass
- Never on primary content
- Only on: Navigation, overlays, modals
- Avoid nested glass (glass inside glass)

**Glass Container Definition:**

```
Base:
  Backdrop Filter:   Blur(15px)
  Opacity:           6% white overlay
  Border:            1px solid white @ 12% opacity
  
Gradient overlay:
  Start:             rgba(255, 255, 255, 0.08) top-left
  End:               rgba(255, 255, 255, 0.04) bottom-right
  
Shadow:
  Shadow 1 (ambient):
    Color:           rgba(0, 0, 0, 0.15)
    Blur:            12px
    Spread:          -4px
    Offset:          0, 4px
    
  Shadow 2 (edge):
    Color:           rgba(0, 0, 0, 0.08)
    Blur:            2px
    Spread:          0px
    Offset:          0, 1px
```

**Focused Glass:**
```
When glass element receives focus:
  Blur:              20px (increase from 15)
  Opacity:           10% (increase from 6%)
  Border:            2px solid white @ 15%
  Shadow 3 (glow):   rgba(0, 160, 210, 0.2), blur 20
  Duration:          150ms easeOut
```

---

### 3.9 Theming Strategy (Systematic Approach)

**Dark Mode (Primary - for TV)**
```
Background:   #000000 pure black
Surfaces:
  Level 0:    #000000 (base)
  Level 1:    #0A0A0A (subtle lift)
  Level 2:    #1A1A1A (card surface)
  Level 3:    #2A2A2A (hover lift)
  Level 4:    #3A3A3A (disabled/secondary)

Text colors (4-tier system):
  Primary:    #FFFFFF (100% opacity)
  Secondary:  #999999 (60% opacity) = #FFFFFF @ 60%
  Tertiary:   #666666 (40% opacity) = #FFFFFF @ 40%
  Quaternary: #404040 (25% opacity) = #FFFFFF @ 25%

Accent colors:
  Primary:    #00A0D2 (teal, focus states)
  Secondary:  #FF3B30 (red, alerts)
  Tertiary:   #34C759 (green, success)
```

---

## PART 4: IMPLEMENTATION ROADMAP

### Phase 1: Color System Update (4-6 hours)

**Files to update:**
1. `lib/core/theme/app_colors.dart`
   - [ ] Update primary from #00D4FF → #00A0D2
   - [ ] Refine secondary #FF6B6B → #FF3B30
   - [ ] Update tertiary #00E5BB → #00D4AA
   - [ ] Add grey surface levels (19 new colors)
   - [ ] Remove excessive category colors
   - [ ] Update glass opacity values (8% → 6%)
   - [ ] Add new focus glow color

2. Update all theme-referencing files
   - `lib/core/theme/app_theme.dart` (color references)
   - `lib/mobile/theme/mobile_theme.dart` (color references)
   - All widget files using `AppColors.primary` etc.

**Estimated changes:**
- app_colors.dart: ~50 lines modified/added
- 15+ widget files: 1-5 line color reference updates each

---

### Phase 2: Typography System (6-8 hours)

**Files to update:**
1. `lib/core/theme/app_theme.dart`
   - [ ] Update all text styles with new sizes
   - [ ] Adjust line heights (add minimum 1.4)
   - [ ] Reduce letter-spacing on large text
   - [ ] Add new MICRO style (10px)
   - [ ] Increase Display Large from 56 → 64px

2. Create `lib/core/theme/typography_scale.dart`
   - Document all type sizes with usage examples
   - Provide mixin for easy application

**Estimated changes:**
- Text scale definitions: ~80 lines
- Widget usage updates: Scattered, find via grep

---

### Phase 3: Spacing & Layout (4-5 hours)

**Files to update:**
1. `lib/core/theme/app_theme.dart`
   - [ ] Review spacing constants (already good - minimal changes)
   - [ ] Add TV-specific spacing (80px, 96px)
   - [ ] Create responsive spacing mixin

2. Layout files - Targeted updates:
   - `lib/features/iptv/screens/home_screen.dart`
   - `lib/core/widgets/tv_channel_grid.dart`
   - `lib/features/iptv/screens/player_screen.dart`

**Key change:** Increase minimum padding from 16px → 32px for TV layouts

---

### Phase 4: Shadow & Elevation System (3-4 hours)

**Files to update:**
1. `lib/core/theme/app_theme.dart` - _AppThemeExtension
   - [ ] Redefine 5 elevation levels with multi-layer shadows
   - [ ] Create focus glow definitions
   - [ ] Add elevation utility functions

2. Create `lib/core/theme/elevation_system.dart`
   - Predefined shadow presets (Level 1-5)
   - Usage examples

3. Update all components using shadows:
   - Cards (15+ files)
   - Buttons (5+ files)
   - Navigation (3+ files)

---

### Phase 5: Animation System (5-6 hours)

**Files to update:**
1. `lib/core/theme/app_theme.dart`
   - [ ] Update animation curves
   - [ ] Add new durations (250ms)
   - [ ] Add spring curve definitions

2. Create `lib/core/animation/tv_animations.dart`
   - Predefined animation sequences
   - Focus arrival animation
   - Tap feedback animation
   - Page transitions

3. Update high-use animation files:
   - `lib/core/widgets/tv_focusable_card.dart`
   - `lib/core/widgets/hero_carousel.dart`
   - `lib/core/widgets/glass_container.dart` (scale animations)
   - Navigation widgets (focus transitions)

---

### Phase 6: Component Styling (8-10 hours)

**Primary Button Update:**
- File: `lib/core/theme/app_theme.dart` (filledButtonTheme)
- Changes:
  - Height: 44px → 56px
  - Padding: 24×12 → 28×12
  - Radius: 12px → keep
  - Focus border: Add 2px white border
  - Glow: Add on focus

**Secondary Button Update:**
- File: `lib/core/theme/app_theme.dart` (outlinedButtonTheme)
- Changes: Similar to primary
- Border styling on focus

**Card Styling:**
- File: `lib/core/theme/app_theme.dart` (cardTheme)
- Remove default border (use in component instead)
- Add default shadow (Level 2)
- Radius: 16px → 12px

**Navigation:**
- `lib/core/widgets/tv_nav_widgets.dart`
- Increase button height: 44px → 56px
- Update icon sizing
- Add focus glow

---

### Phase 7: Glass Effect Refinement (3-4 hours)

**Files to update:**
1. `lib/core/widgets/glass_container.dart`
   - Opacity: 8% → 6% (default)
   - Blur: 15px (good, keep)
   - Shadow redefinition (Level 3)
   - Add focused state with glow

2. `lib/core/widgets/glass_card.dart`
   - Update animations to match new standards
   - Add press feedback

---

### Phase 8: Verification & Testing (4-6 hours)

**Checklist:**
- [ ] All colors match specification hex codes
- [ ] Typography scales render correctly at 4K
- [ ] Animations duration/curve matches spec
- [ ] Focus states clearly visible
- [ ] Shadows render with depth
- [ ] Glass effects appear premium
- [ ] Build passes without warnings
- [ ] Visual regression testing (screenshots)

---

## PART 5: Specific Hex Code Reference

### Complete Color Palette

**Primary System:**
```
Primary Teal:        #00A0D2  (Focus, CTA, highlights)
Primary Teal Dark:   #0092BC  (Hover state)
Primary Teal Light:  #1BC4E5  (Disabled variant)
```

**Secondary System:**
```
Error Red:           #FF3B30  (Errors, alerts, live)
Error Dark:          #E62817  (Hover)
Error Light:         #FF6B6B  (Disabled variant)
```

**Success System:**
```
Success Green:       #34C759  (Success states)
Success Dark:        #2AA64D  (Hover)
Success Light:       #5AD361  (Disabled)
```

**Warning System:**
```
Warning Orange:      #FF9500  (Warnings)
Warning Dark:        #E68400  (Hover)
Warning Light:       #FFA325  (Disabled)
```

**Neutral System:**
```
Pure Black:          #000000  (Base background)
Deep Black:          #0A0A0A  (Lift 1)
Level 1 Grey:        #1A1A1A  (Card surface)
Level 2 Grey:        #2A2A2A  (Hover)
Level 3 Grey:        #3A3A3A  (Disabled)
Level 4 Grey:        #4A4A4A  (Divider)
Level 5 Grey:        #666666  (Secondary text)
Level 6 Grey:        #888888  (Tertiary text)
Level 7 White:       #FFFFFF  (Primary text)
```

**Glass System:**
```
Glass Base:          rgba(255, 255, 255, 0.06)
Glass Border:        rgba(255, 255, 255, 0.12)
Glass Premium:       rgba(255, 255, 255, 0.10)
Glass Dark:          rgba(0, 0, 0, 0.50)
```

**Text Opacity System (from white #FFFFFF):**
```
100% (Primary):      #FFFFFF  = 255, 255, 255, 1.0
80% (Emphasized):    #CCCCCC  = white @ 80%
60% (Secondary):     #999999  = white @ 60%
40% (Tertiary):      #666666  = white @ 40%
25% (Quaternary):    #404040  = white @ 25%
```

---

## PART 6: Implementation Checklist

### Pre-Implementation
- [ ] Export this specification to team
- [ ] Schedule design review (2-3 hours)
- [ ] Identify high-impact screens (home, player, channels)
- [ ] Create test plan for visual regression

### Color System (Phase 1)
- [ ] Update app_colors.dart
- [ ] Verify all color references compile
- [ ] Screenshot side-by-side comparison
- [ ] Check contrast ratios (WCAG)

### Typography (Phase 2)
- [ ] Update app_theme.dart text styles
- [ ] Test rendering at 4K resolution
- [ ] Verify line-height spacing
- [ ] Check readability at TV distance

### Layout (Phase 3)
- [ ] Update spacing usage
- [ ] Review TV layout files
- [ ] Test responsive behavior
- [ ] Verify padding on all containers

### Shadows (Phase 4)
- [ ] Define elevation system
- [ ] Update component shadows
- [ ] Test shadow depth perception
- [ ] Verify focus glow visibility

### Animations (Phase 5)
- [ ] Update animation curves
- [ ] Test animation fluidity
- [ ] Review animation timing
- [ ] Test on target device

### Components (Phase 6)
- [ ] Update button styling
- [ ] Update card styling
- [ ] Update form elements
- [ ] Update navigation

### Glass (Phase 7)
- [ ] Refine glass effects
- [ ] Test on dark backgrounds
- [ ] Verify premium appearance
- [ ] Test focus states

### Testing (Phase 8)
- [ ] Full app build
- [ ] Visual regression screenshots
- [ ] Accessibility audit
- [ ] Performance profiling
- [ ] Cross-screen testing (mobile→TV)

---

## SUMMARY

This specification provides:

1. **Current State Analysis** - Identifies what works and what doesn't
2. **Apple TV Standards** - Detailed design principles and specifications
3. **Complete Specifications** - Exact hex codes, measurements, timings
4. **Implementation Path** - Phased approach across 8 phases
5. **Reference Material** - For developers implementing changes

**Key Takeaways:**
- Current design has good foundation but needs refinement
- Primary issue: Colors too vibrant (not Apple TV sophisticated)
- Solution: Muted palette, reserved accent colors, grey-dominant UI
- Focus states must be unmissable for TV remote control
- Multi-layer shadow system creates cinematic depth
- Animation curves should be easeOut-based (deceleration)
- Spacing needs TV-aware expansion (48px minimum comfortable)
- Glass effects should be subtle (6% opacity, not 8%)

**Estimated Timeline:** 4-6 weeks for full implementation
**Team Size:** 2-3 developers (designer + 2 devs in parallel)
**Risk Level:** Low (all changes contained, fallback to current if needed)

