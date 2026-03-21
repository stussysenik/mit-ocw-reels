# MIT OCW Reels — Design System Redesign + OCW Scraper Integration

## Summary

Redesign all views using IBM Carbon Design palette, golden ratio (φ) spacing system, and MIT course identity-first information architecture. Integrate the live OCW scraper from `autoresearch-playground` as the content engine. Replaces the current arbitrary spacing, generic SwiftUI styling, and static seed data with a systematic, perceptually-grounded design language powered by live MIT OCW catalog data.

## Design Direction

**Minimal Editorial** — clean, restrained, content-first. Carbon's gray scale does the heavy lifting. Hairline borders over shadows. Course numbers lead the hierarchy.

## Color System — IBM Carbon Design

IBM Carbon's color tokens solve multiple problems: consistent contrast ratios, perceptual uniformity across the gray scale, accessible text-on-surface combinations, and a professional, editorial feel that matches MIT's institutional character.

### 60/30/10 Distribution

| Role | Proportion | Tokens | Hex |
|------|-----------|--------|-----|
| **Surfaces** | 60% | background, layer01, layerHover | `#F4F4F4`, `#FFFFFF`, `#E0E0E0` |
| **Text & Icons** | 30% | textPrimary, textSecondary, textPlaceholder | `#161616`, `#525252`, `#A8A8A8` |
| **Accent** | 10% | interactive | `#A31F34` (MIT Cardinal) |

### Full Token Map

```
// Surfaces (60%)
background      = #F4F4F4  // Carbon Gray 10
layer01          = #FFFFFF  // White — card/content surfaces
layerHover       = #E0E0E0  // Carbon Gray 20

// Text (30%)
textPrimary      = #161616  // Carbon Gray 100 — titles, course numbers
textSecondary    = #525252  // Carbon Gray 70 — subtitles, course names
textPlaceholder  = #A8A8A8  // Carbon Gray 40 — lecture counts, hints

// Borders
borderSubtle     = #E0E0E0  // Carbon Gray 20 — hairline dividers
borderSection    = #F4F4F4  // Carbon Gray 10 — row separators
borderStrong     = #8D8D8D  // Carbon Gray 50 — emphasis

// Labels
textLabel        = #6F6F6F  // Carbon Gray 60 — uppercase section/topic labels

// Interactive (10%)
interactive      = #A31F34  // MIT Cardinal — active tab, lecture labels
supportError     = #DA1E28  // Carbon Red 60
supportSuccess   = #198038  // Carbon Green 60
```

### Contrast Compliance (WCAG)

| Pairing | Ratio | Level |
|---------|-------|-------|
| textPrimary on layer01 | 18.1:1 | AAA |
| textSecondary on layer01 | 7.8:1 | AAA |
| textLabel on layer01 | 5.0:1 | AA |
| interactive on layer01 | 7.5:1 | AAA |
| textPlaceholder on layer01 | 2.4:1 | Decorative only |

### Key Decision: Borders Over Shadows

Carbon uses 1px solid borders (`#E0E0E0`), not drop shadows or `.material` effects. This is cleaner, more editorial, and avoids the generic iOS look. Remove all `.regularMaterial`, `.ultraThinMaterial`, and shadow modifiers.

## Spacing System — Golden Ratio (φ)

All spacing derives from two values: **x = 1em (16pt)** and **y = φ (1.618)**. This creates a mathematically harmonious scale where every gap relates to the typography.

### Spacing Scale

| Token | Formula | Value | Use |
|-------|---------|-------|-----|
| `xs` | x / 2 | 8pt | Tight inner gaps, grid anchor |
| `sm` | x / y | 10pt | Icon-to-text gaps, small gutters |
| `md` | x | 16pt | Horizontal padding, standard margins |
| `lg` | x · √y | 20pt | Section gaps, corner radii, card↔content |
| `xl` | x · y | 26pt | Major section separators, top/bottom safe margins |

### Corner Radii

| Token | Value | Use |
|-------|-------|-----|
| `card` | 20pt (x · √y) | Video player, info cards |
| `badge` | 8pt (xs) | Small badges, pills |
| `search` | 10pt (sm) | Search bar, input fields |

## Information Architecture — MIT Culture

MIT students identify courses by number, not title. "18.06" is how you say it; "Linear Algebra" is the subtitle. The course number must be the hero identifier.

### ReelView Hierarchy (top → bottom)

1. **Course number** — `6.0001` in monospace, semibold, textPrimary. Followed by dot separator and department abbreviation in textSecondary.
2. **Lecture title** — `.title3` bold, textPrimary. The main content title.
3. **Course name** — `.subheadline`, textSecondary. Full course title for context.
4. **Hairline divider** — 1px borderSubtle.
5. **Topic label** — `.caption2` uppercase, textLabel, letter-spacing 1px.

### CoursesView Row Hierarchy

1. **Course number** — monospace, semibold, textPrimary (hero).
2. **Course title** — `.body`, textPrimary.
3. **Lecture count** — `.caption2`, textPlaceholder.
4. **Chevron** — `›` in `textTertiary` (Carbon Gray 30, #C6C6C6).

### CourseReelsView Differences

- Navigation title shows course number in monospace (no duplication in card).
- "LECTURE N" label in MIT Cardinal uppercase replaces course number in card position.

## View Specifications

### DesignTokens.swift (new file)

Shared enum with all spacing, radius, and color constants. Every view references these instead of hardcoded values.

```swift
import SwiftUI

enum Spacing {
    static let xs: CGFloat = 8    // x / 2 (grid anchor)
    static let sm: CGFloat = 10   // x / y
    static let md: CGFloat = 16   // x (1em)
    static let lg: CGFloat = 20   // x · √y
    static let xl: CGFloat = 26   // x · y
}

enum Radius {
    static let card: CGFloat = 20   // x · √y
    static let badge: CGFloat = 8   // xs
    static let search: CGFloat = 10 // sm
}

enum CarbonColor {
    // Surfaces
    static let background = Color(hex: 0xF4F4F4)
    static let layer01 = Color.white
    static let layerHover = Color(hex: 0xE0E0E0)

    // Text
    static let textPrimary = Color(hex: 0x161616)
    static let textSecondary = Color(hex: 0x525252)
    static let textPlaceholder = Color(hex: 0xA8A8A8)
    static let textLabel = Color(hex: 0x6F6F6F)

    // Borders
    static let borderSubtle = Color(hex: 0xE0E0E0)
    static let borderSection = Color(hex: 0xF4F4F4)
    static let borderStrong = Color(hex: 0x8D8D8D)

    // Interactive
    static let interactive = Color(hex: 0xA31F34)  // MIT Cardinal
    static let textTertiary = Color(hex: 0xC6C6C6) // Gray 30 — chevrons

    // Support
    static let supportError = Color(hex: 0xDA1E28)
    static let supportSuccess = Color(hex: 0x198038)
}
```

### ReelView.swift

- **Background**: `CarbonColor.layer01` (white)
- **Video player**: `CarbonColor.background` fill, `Radius.card` corners, 1px `borderSubtle` border
- **Top margin**: `Spacing.xl` (26pt)
- **Video-to-metadata gap**: `Spacing.lg` (20pt)
- **Horizontal padding**: `Spacing.md` (16pt)
- **Course number**: monospaced, `.callout` weight semibold, `textPrimary`
- **Title**: `.title3` bold, `textPrimary`
- **Course name**: `.subheadline`, `textSecondary`
- **Divider**: 1px `borderSubtle`, 10pt top/bottom margin
- **Topic label**: `.caption2` uppercase, `textLabel`, letterSpacing 1pt
- **Remove**: `.regularMaterial`, `Color(.systemGroupedBackground)`, `.red.opacity(0.1)` badge

### CoursesView.swift

- **Background**: `CarbonColor.background` (Gray 10)
- **List rows**: white background, 1px `borderSection` separators
- **Section headers**: `.caption2` uppercase, `textLabel`, letterSpacing 1pt, `Spacing.sm` padding
- **Course number**: monospaced, semibold, `textPrimary` — first line, hero
- **Course title**: `.body`, `textPrimary`
- **Lecture count**: `.caption2`, `textPlaceholder`
- **Row padding**: `Spacing.sm` vertical, `Spacing.md` horizontal
- **Search bar**: `CarbonColor.layerHover` background, `Radius.search` corners

### CourseReelsView.swift

- Same reel layout as ReelView
- **Navigation title**: course number in monospace
- **Lecture number label**: "LECTURE N" in MIT Cardinal, `.caption` weight semibold, uppercase
- Course number omitted from card (already in nav)

### ContentView.swift

- **Tab bar tint**: `CarbonColor.interactive` (MIT Cardinal)
- **Keep**: `.preferredColorScheme(.light)` — Carbon tokens are light-mode only; dark mode is a future spec
- **Tab bar border**: 1px `borderSubtle` top border

### DiscoverView.swift

- **Background**: `CarbonColor.background` (replaces `Color(.systemGroupedBackground)`)
- **Loading state**: `ProgressView()` tinted `interactive`, text `.subheadline` in `textSecondary`, spacing `Spacing.md`
- **Keep**: scroll/paging behavior unchanged

### YouTubePlayerView.swift

- No visual changes needed (WKWebView content)

### Empty/Error States

- `ContentUnavailableView` in CoursesView and CourseReelsView: keep system default styling, tint SF Symbols with `interactive`
- Loading `ProgressView` in DiscoverView: tint with `interactive`

## OCW Scraper Integration

### Source

Copy from: `/Users/s3nik/Desktop/autoresearch-playground/experiments/ocw-video-scraper/swift/OCWScraper.swift`

### Architecture

The scraper is a Foundation-only Swift actor that crawls MIT OCW sitemaps and extracts YouTube video IDs from transcript filenames. It uses TaskGroup with 32-concurrent batches.

**Interface:**
```swift
actor OCWScraper {
    init(maxConcurrency: Int = 32)
    func scrapeAll() async throws -> [ScrapedLecture]
}
```

**Output:** `[ScrapedLecture]` — fields match SwiftData `Lecture` model exactly (title, youtubeId, courseNumber, courseName, department, semester, year, ocwUrl, topicName).

### Integration Strategy

Two-phase content pipeline in `MITReelsApp.swift`:
1. **Phase 1 (sync, immediate):** Keep `seed_data.json` as bundled fallback for instant content on first launch
2. **Phase 2 (async, background):** After seed, fire `OCWScraper.scrapeAll()` in a detached Task. Merge results into SwiftData with dedup by `youtubeId`

## Files to Create

| File | Purpose |
|------|---------|
| `MITReels/Design/DesignTokens.swift` | Spacing, Radius, CarbonColor enums |
| `MITReels/Design/Color+Hex.swift` | `Color(hex:)` initializer extension |
| `MITReels/Services/OCWScraper.swift` | Actor-based MIT OCW catalog scraper (copy from autoresearch) |

## Files to Modify

| File | Key Changes |
|------|------------|
| `MITReels/Views/ReelView.swift` | Full layout rewrite with Carbon tokens + golden ratio spacing |
| `MITReels/Views/CoursesView.swift` | Carbon styling, monospace course numbers, uppercase section headers, `.listStyle(.plain)` |
| `MITReels/Views/CourseReelsView.swift` | Lecture number label, remove course number from card |
| `MITReels/Views/DiscoverView.swift` | Background + loading state with Carbon tokens |
| `MITReels/ContentView.swift` | Tab bar tint to MIT Cardinal, keep `.preferredColorScheme(.light)` |
| `MITReels/MITReelsApp.swift` | Add background scraper Task after seed data |
| `MITReels/Utilities/PreviewSampleData.swift` | Ensure previews work with new design |

## Verification

1. `flowdeck build` — confirms compilation
2. Open each view in Xcode Canvas — preview should render with Carbon colors
3. Verify: no `.regularMaterial`, no `.systemGroupedBackground`, no drop shadows remain
4. Verify: all spacing values reference `Spacing.*` constants, no hardcoded pt values
5. Verify: course numbers appear in monospace at the top of every hierarchy
6. Visual check: 60/30/10 color distribution looks balanced on device
