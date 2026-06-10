---
name: Cyber-Cinematic Glass
colors:
  surface: '#121317'
  surface-dim: '#121317'
  surface-bright: '#38393d'
  surface-container-lowest: '#0d0e12'
  surface-container-low: '#1a1b20'
  surface-container: '#1f1f24'
  surface-container-high: '#292a2e'
  surface-container-highest: '#343439'
  on-surface: '#e3e2e7'
  on-surface-variant: '#c1c6d7'
  inverse-surface: '#e3e2e7'
  inverse-on-surface: '#2f3035'
  outline: '#8b90a0'
  outline-variant: '#414755'
  surface-tint: '#adc6ff'
  primary: '#adc6ff'
  on-primary: '#002e69'
  primary-container: '#4b8eff'
  on-primary-container: '#00285c'
  inverse-primary: '#005bc1'
  secondary: '#c6c5cf'
  on-secondary: '#2f3037'
  secondary-container: '#4a4b53'
  on-secondary-container: '#bcbbc4'
  tertiary: '#c6c6c7'
  on-tertiary: '#2f3131'
  tertiary-container: '#909191'
  on-tertiary-container: '#282a2a'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d8e2ff'
  primary-fixed-dim: '#adc6ff'
  on-primary-fixed: '#001a41'
  on-primary-fixed-variant: '#004493'
  secondary-fixed: '#e3e1eb'
  secondary-fixed-dim: '#c6c5cf'
  on-secondary-fixed: '#1a1b22'
  on-secondary-fixed-variant: '#46464e'
  tertiary-fixed: '#e2e2e2'
  tertiary-fixed-dim: '#c6c6c7'
  on-tertiary-fixed: '#1a1c1c'
  on-tertiary-fixed-variant: '#454747'
  background: '#121317'
  on-background: '#e3e2e7'
  surface-variant: '#343439'
typography:
  headline-xl:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '500'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.2'
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 48px
  xl: 80px
  gutter: 24px
  margin: 32px
---

## Brand & Style

The design system is built for a high-performance media environment where immersion is paramount. It targets power users who value speed, technical precision, and a premium aesthetic. The style is a sophisticated blend of **Glassmorphism** and **Futuristic Minimalism**. 

The UI should feel like a high-tech command center—unobtrusive when consuming content but sharp and responsive during management tasks. By utilizing deep-space charcoals and translucent layers, the system creates a sense of infinite depth. The emotional response should be one of "effortless control" and "high-fidelity quality," achieved through high-contrast accents against an ultra-dark backdrop.

## Colors

The palette is optimized for OLED displays and low-light environments. The primary color is a vibrant neon blue, used sparingly for critical actions and active states to guide the eye without causing fatigue. 

The background hierarchy uses `#0F1014` for the base canvas and `#181920` for elevated surfaces and containers. Grays are used exclusively for metadata and inactive iconography, ensuring they recede behind primary content. Accent gradients should transition from the primary blue into a deep cyan to simulate a "glowing" light source within the interface.

## Typography

This design system utilizes a dual-font strategy to balance technical aesthetics with readability. **Space Grotesk** is used for headlines and hero sections to provide a sharp, geometric, and futuristic "tech" feel. Its distinctive letterforms reinforce the platform's advanced capabilities.

**Inter** is employed for all functional UI elements, body text, and labels. Its neutral, systematic nature ensures that dense media metadata remains legible at small sizes. All labels should be treated with a slight tracking increase to enhance clarity against dark backgrounds.

## Layout & Spacing

The layout philosophy follows a **12-column fluid grid** for desktop, transitioning to a flexible single-column layout for mobile. A strict 8px rhythmic system ensures visual consistency across all components.

Spacing is used to create "visual islands," grouping related media controls while leaving generous margins around content to maintain a premium, airy feel. Components should utilize dynamic padding that scales based on the container size, ensuring the interface never feels cramped, even when managing large libraries.

## Elevation & Depth

Depth in this design system is achieved through **Glassmorphism** and layering rather than traditional drop shadows. Surfaces are defined by three distinct tiers:

1.  **Base (Level 0):** Pure `#0F1014` background.
2.  **Surface (Level 1):** Translucent layers with a `backdrop-filter: blur(20px)` and a 1px border at 10% white opacity.
3.  **Floating (Level 2):** High-blur containers with a subtle inner glow (1px, top-left) in the primary accent color at 20% opacity.

Shadows, when used, are extra-diffused and tinted with the primary blue or charcoal to maintain the "light-from-within" aesthetic.

## Shapes

The design system employs a **Rounded** shape language to soften the futuristic edge and make the platform feel more approachable. 

- **Cards and Modals:** Use `rounded-xl` (1.5rem) to emphasize the glass container effect.
- **Buttons and Inputs:** Use `rounded-lg` (1rem) for a modern, tactile feel.
- **Media Thumbnails:** Use a consistent 0.5rem radius to prevent the UI from feeling too sharp or aggressive.

## Components

### Buttons
Primary buttons use a solid gradient of `#007AFF` to a slightly lighter cyan, featuring a subtle outer glow on hover. Secondary buttons should be "Ghost" style with a 1px border and a glass background.

### Cards
Media cards are the core component. They must feature a dark semi-transparent overlay at the bottom for metadata, utilizing the backdrop-blur effect. On hover, the border opacity should increase from 10% to 40%.

### Input Fields
Inputs are dark-filled containers (`#181920`) with a 1px border that glows blue upon focus. Placeholder text should be a soft gray to maintain low visual noise.

### Chips & Badges
Used for genres or status indicators. They should be pill-shaped with a low-opacity background tint of the primary color and high-contrast white text.

### Progress Bars
Streaming progress bars use the primary accent color with a subtle neon glow effect (`box-shadow`). The "track" behind the progress should be a dark charcoal with 50% opacity.

### Navigation Sidebar
A vertical glass panel on the left with a constant backdrop blur. Active states are indicated by a vertical blue "light bar" on the left edge of the menu item.