# CodexSwitch Design System & Aesthetic Guide

CodexSwitch is designed as a focused, lightweight, and companion utility for macOS 14+. It pairs modern macOS system materials with frosted glass surfaces, tactile responsive controls, high information density, and calm, predictable micro-interactions.

This document formalizes the design language, design tokens, visual hierarchy, interaction patterns, and product tastes followed across the codebase.

---

## 1. Design Philosophy & Aesthetic Values

### 1.1 Native macOS Fluidity with Modern Glassmorphism
- **System-Native Materials**: Uses `NSVisualEffectView` with `.underWindowBackground` and `.behindWindow` blending modes alongside SwiftUI `.ultraThinMaterial` to naturally adapt to macOS Light and Dark appearance and wallpaper tinting.
- **Translucent Layered Depth**: Elevated surfaces utilize frosted translucent cards (`Color(nsColor: .controlBackgroundColor).opacity(0.45)`) enclosed in hairline borders (`0.5pt` with `primary.opacity(0.08)`) and soft ambient shadows (`radius: 8, y: 3, opacity: 0.06`).
- **Borderless & Frameless Canvas**: Windows use `.hiddenTitleBar` with transparent title bars, unified content views, and background dragging (`isMovableByWindowBackground = true`) to feel like an integrated system widget rather than a traditional heavy desktop app.

### 1.2 Tactile & Physical Micro-Interactions
- **Interactive Feedback**: Controls compress physically on press using snappy spring physics (`scaleEffect(0.97)` on capsule buttons, `scaleEffect(0.94)` on circular action buttons).
- **Clean Focus States**: Distracting default macOS blue focus rings are eliminated (`.unfocusedControl()` / `.focusEffectDisabled()`), keeping the interface calm and deliberate while retaining full keyboard accessibility via dedicated shortcuts.
- **Hover Responsiveness**: Secondary and destructive actions stay tucked away to avoid visual noise, elegantly gliding and fading into view on card hover (`UITheme.Animations.hover`).

### 1.3 High Information Density Without Visual Clutter
- **Fixed-Width Companion Window**: A calibrated `480pt` width fits comfortably alongside other windows without dominating screen real estate.
- **Zero-Lag Instant Tooltips**: Avoids macOS's 1-2 second standard tooltip delay by rendering instant, coordinate-space aware pill tooltips clamped dynamically to the window frame.
- **Inline State Over Modals**: Profile creation, rename workflows, authentication progress, and deletion confirmations happen directly within their respective card surfaces rather than popping disruptive modal sheets.

---

## 2. Design Tokens (`UITheme`)

All visual primitives and tokens are centralized in [`App/Views/Components/UITheme.swift`](App/Views/Components/UITheme.swift).

### 2.1 Color Palette & Semantic Tints

The color system uses subdued, semantic tints calibrated for readability across both Light and Dark modes:

| Token | Hex / RGB Representation | Usage & Meaning | Background Tint |
| :--- | :--- | :--- | :--- |
| **Emerald** | `rgb(33, 196, 112)` (`#21C470`) | Active profile indicator, verified status, successful operations | `emerald.opacity(0.12)` |
| **Amber** | `rgb(245, 158, 38)` (`#F59E26`) | Warning states, unverified profiles, pending recovery journals | `amber.opacity(0.12)` |
| **Coral** | `rgb(240, 84, 79)` (`#F0544F`) | Destructive actions, error banners, critical alerts | `coral.opacity(0.12)` |
| **System Blue** | `rgb(51, 128, 250)` (`#3380FA`) | Browser auth actions, primary interactive elements | `blue.opacity(0.12)` |

#### Surface & Control Neutrals
- **Card Background**: `Color(nsColor: .controlBackgroundColor).opacity(0.45)`
- **Card Border**: `Color.primary.opacity(0.08)` (Hairline `0.5pt`)
- **Secondary Button Fill**: `Color.primary.opacity(0.06)` + `.ultraThinMaterial`
- **Secondary Button Border**: `Color.primary.opacity(0.12)` (Hairline `0.5pt`)
- **Status Dock Divider**: Linear gradient `[primary.opacity(0.02), primary.opacity(0.09), primary.opacity(0.02)]` (Height `0.5pt`)

---

### 2.2 Typography Hierarchy

CodexSwitch uses the system font family with distinct weights and rounded variants for headers and badges to balance technical precision with approachable warmth:

| Style | Spec | Tracking / Weight | Intent / Placement |
| :--- | :--- | :--- | :--- |
| `appTitle` | `15pt`, Bold, `.rounded` | Tight, bold | Main window header title, FAQ title |
| `appSubtitle` | `11pt`, Regular | Regular, `.secondary` | Window subtitle / value prop, FAQ answers |
| `sectionHeader`| `11pt`, Semibold | Semibold, `.secondary` | Section headers ("PROFILES") |
| `cardTitle` | `13pt`, Semibold | Semibold, `.primary` | Profile name, FAQ questions |
| `cardSubtitle` | `11pt`, Regular | Regular, dynamic tint | Profile email/identity status |
| `badge` | `10pt`, Semibold, `.rounded` | Semibold, `.secondary` | Count pills (e.g. profile count badge) |
| `chip` | `10pt`, Medium | Medium | FAQ category filter chips |
| `micro` | `10pt`, Regular | Regular, `.tertiary` | Explanatory helper microcopy |
| `input` | `12pt`, Regular | Regular | Text fields (profile creation/renaming) |

---

### 2.3 Spacing & Layout Geometry

Spacing adheres to a strict 4pt baseline grid:

```
xs: 4pt  ──  sm: 8pt  ──  md: 12pt  ──  lg: 16pt  ──  xl: 20pt
```

- **Window Padding**: `16pt` horizontal gutters
- **Card Padding**: `16pt` horizontal, `12pt` vertical
- **Avatar Dimensions**: `38 × 38pt` with `23pt` SF Symbol glyph
- **Circular Action Buttons**: `28 × 28pt` with `12pt` SF Symbol glyph
- **Window Dimensions**:
  - Width: Exactly `480pt` (fixed-width, centered automatically)
  - Minimum Height: `380pt`
  - Default Height: `440pt`
  - Maximum Content Height: `580pt` (Window maximum: `700pt`)

---

### 2.4 Corner Radii & Shapes

- **Card Radius (`UITheme.Radius.card`)**: `20pt` continuous (`.continuous` corner style)
- **Hero Surface (`UITheme.Radius.hero`)**: `20pt` continuous
- **Small Controls (`UITheme.Radius.control`)**: `6pt` continuous
- **Chips / Pills (`UITheme.Radius.chip`)**: `4pt` continuous
- **Buttons & Indicators**: Full `Capsule()` or `Circle()`

---

### 2.5 Motion & Animation Curves

All transitions utilize custom spring curves tuned for rapid responsiveness without sluggishness:

- **Primary UI Spring**: `Animation.spring(response: 0.25, dampingFraction: 0.8)`
  - *Used for*: Accordion expansion, category switching, inline confirmations, layout reflows.
- **Physical Press**: `Animation.spring(response: 0.18, dampingFraction: 0.7)`
  - *Used for*: Button depression feedback on click.
- **Hover Dynamics**: `Animation.spring(response: 0.22, dampingFraction: 0.85)`
  - *Used for*: Fading and scaling action icons on hover.
- **Instant Tooltips**: `Animation.easeOut(duration: 0.12)` with `scale(0.95)` entry.

---

## 3. Core Component Library

### 3.1 Card Surface Modifier (`.cardSurface(radius:)`)
Encapsulates the standard frosted glass surface:
```swift
content
    .background {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(UITheme.Colors.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(UITheme.Colors.cardBorder, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
```

### 3.2 Tactile Capsule Buttons (`TactileButtonStyle`)
Pill-shaped action buttons supporting multiple variants:
- `.tactilePrimary`: High-contrast solid action button (`.primary` foreground, `windowBackgroundColor` text)
- `.tactileSecondary`: Frosted translucent button with `.ultraThinMaterial` and subtle hairline border
- `.tactileSubtle`: Minimal ghost button with light hover/press tint
- `.tactileDestructive`: Danger button tinted with Coral
- `.tactileEmerald` / `.tactileEmeraldSecondary`: Success / confirmation action styles
- `.tactileBlue`: Primary link and authentication actions

Features:
- Scales to `0.97` on press with spring feedback.
- Dynamically scales font, horizontal padding, and vertical padding based on `ControlSize` (`.mini`, `.small`, `.regular`, etc.).

### 3.3 Tactile Circular Icon Buttons (`TactileCircleButtonStyle`)
Compact `28 × 28pt` circular buttons for secondary actions (Reveal in Finder, Re-authenticate, Browser Sign-In, Delete Profile, Close FAQ):
- Circular `Circle()` shape with hairline border.
- Scales to `0.94` on click.
- Integrated instant tooltip support.

### 3.4 Instant Tooltips (`InstantTooltip`)
Provides immediate contextual feedback without OS delay:
- **Global Coordinate Tracking**: Powered by a custom `TooltipManager` observable environment and `TooltipAnchorReader`.
- **Intelligent Viewport Clamping**: Clamps position within window margins and flips above or below the target element automatically.
- **Dark Pill Styling**: Dark translucent capsule with crisp white typography (`caption2.rounded`).

### 3.5 State-Aware SF Symbol Avatar
Visual representation of profile status:
- `38 × 38pt` circular base with hierarchical SF Symbol (`person.crop.circle`).
- **Active Profile**: Bold glyph with primary foreground.
- **Unverified Profile**: Amber warning badge at bottom-right (`exclamationmark.circle.fill`).
- **In-Progress Sign-In**: Inline animated `ProgressView()` spinner.

### 3.6 Inline Action & Status Card (`ProfileCardView`)
- **Double-Click Inline Rename**: Double-clicking the profile title swaps text into a styled inline `TextField` with keyboard submit (`Return`) and cancel (`Esc`).
- **Hover-Revealed Quick Actions**: Finder reveal, Re-authenticate, and Delete buttons fade into view on cursor hover.
- **Inline Delete Confirmation**: Expands a contextual safety bar inside the card with explicit "Move to Trash" and "Cancel" buttons.
- **Inline Auth Progress**: Live status row showing detailed phase (`Opening browser…`, `Checking identity…`, `Sign-in verified`).

### 3.7 Status Dock (`StatusDockView`)
Bottom-pinned frosted dock:
- Displays active background operations, spinner, and status text.
- Houses contextual actions (`Open Browser`, `Check Sign-in`, `Cancel Operation`, `Open ChatGPT`, `FAQ`).
- Emits contextual banners for runtime errors (Coral) or recovery journal events (Amber).

### 3.8 Categorized FAQ Accordion (`FAQSheetView`)
- Filterable horizontal category chips (`All`, `Privacy & Security`, `Sign-In & Auth`, `Safety & Terms`, `Compatibility`, `Architecture`).
- Expandable frosted accordion cards with animated chevron toggles.

---

## 4. Interaction Patterns & UX Guidelines

### 4.1 Keyboard Shortcuts
- **Direct Switch**: `Cmd+1` through `Cmd+9` instantly trigger switching to profiles 1 through 9.
- **Inline Rename**: `Return` commits rename; `Esc` cancels and restores original name.
- **Management Window Navigation**: Accessible directly from the menu bar item or via app launch.

### 4.2 Safe & Explicit Friction
- **Live Conversation Protection**: If a live conversation writer is holding a lock, switching triggers an explicit warning modal before handoff.
- **Provisional Version Gate**: Unverified ChatGPT builds prompt for one-time explicit user acknowledgement.
- **Destructive Deletion**: Managed profile removal requires explicit confirmation and moves files safely to macOS Trash (`~/.Trash`). Adopted Profile A cannot be removed.

### 4.3 Copywriting & Tone of Voice
- **Calm, Precise, Technical**: Avoid sensationalist or ambiguous marketing terms.
- **Strict Terminology**: Follow [`CONTEXT.md`](CONTEXT.md) verbatim:
  - Use *Profile* (never *Account* or *Workspace*).
  - Use *Adopted profile* (never *Primary account* or *Original profile*).
  - Use *Managed profile* (never *Secondary account* or *Cloned profile*).
  - Use *Identity-bound profile* (never *Logged-in profile*).
  - Use *Committed profile* (never *Selected profile*).
- **Privacy Transparency**: Reinforce local-only execution, zero telemetry, opaque credential handling, and offline security.

---

## 5. Dual-Surface Integration

CodexSwitch provides a synchronized dual-surface user experience:

```
┌─────────────────────────────────────────────────────────────┐
│                      macOS Menu Bar                         │
│  [CodexSwitch 18×18 Icon]                                   │
│  ├─ Active: Personal (synthetic-03@example.invalid)                     │
│  ├─ Switch Profile ▶ [✓ Personal | Work (Cmd+2)]           │
│  ├─ Open ChatGPT / ChatGPT (Running)                        │
│  ├─ Manage Profiles… ──────────────────────────────────┐    │
│  └─ Quit CodexSwitch                                   │    │
└────────────────────────────────────────────────────────┼────┘
                                                         │
                                                         ▼
┌─────────────────────────────────────────────────────────────┐
│             CodexSwitch Management Window (480pt)           │
│  [App Icon] CodexSwitch                                     │
│             One verified ChatGPT desktop session at a time  │
│                                                             │
│  PROFILES [ 2 ]                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ (●) Personal                     [Finder][Re-auth]    │  │
│  │     synthetic-03@example.invalid             (● Active)           │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ ( ) Work                         [Finder][Re-auth][🗑] │  │
│  │     synthetic-07@example.invalid             [ Switch ]           │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ [+] New profile (e.g. Work, Research)             (+) │  │
│  └───────────────────────────────────────────────────────┘  │
│ ─────────────────────────────────────────────────────────── │
│  [FAQ]                                  [ Open ChatGPT ↗ ]  │
└─────────────────────────────────────────────────────────────┘
```

1. **Menu Bar Extra (`MenuBarView`)**: Lightweight, instant profile switching and status inspection from the system menu bar.
2. **Management Window (`SettingsView`)**: Full control over profile creation, renaming, credential re-authentication, trash removal, and architecture documentation.
