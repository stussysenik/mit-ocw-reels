# MIT OCW Reels

A native iOS app that turns MIT OpenCourseWare lectures into a vertical-scroll video feed. Browse 600+ lectures across 23 courses, organized by MIT's five-school hierarchy.

Built with SwiftUI + SwiftData. Designed for clarity.

---

<p align="center">
  <img src="screenshots/01_discover_feed.png" width="200" />
  &nbsp;&nbsp;
  <img src="screenshots/02_courses_hub.png" width="200" />
  &nbsp;&nbsp;
  <img src="screenshots/03_school_list.png" width="200" />
  &nbsp;&nbsp;
  <img src="screenshots/04_settings.png" width="200" />
</p>

<p align="center">
  <sub>Discover Feed &nbsp;|&nbsp; School Hub &nbsp;|&nbsp; Course Browser &nbsp;|&nbsp; Settings</sub>
</p>

---

## Features

**Discover Feed** — Doom-scroll through randomized MIT lectures. One swipe, one page. Haptic snap on each transition. Autoplay toggleable.

**School Hub** — Courses organized by MIT's five schools: Engineering, Science, Architecture & Planning, Humanities, and Cross-Disciplinary. Gradient cards show course counts and department pills.

**Course Browser** — Drill into any school to browse courses by department. Toggle between list and grid views. Tap a course to enter its dedicated lecture feed.

**Fullscreen Video** — YouTube iframe embed with native fullscreen support. Timeline scrubber for seeking. Thumbnail poster images while loading.

**Background Catalog Sync** — OCW scraper runs in the background every 24 hours, expanding the lecture catalog from live MIT sitemaps.

## Architecture

```
MITReels/
├── Design/          # Carbon design tokens, typography, color system
├── Models/          # SwiftData models (Course, Lecture, MITSchool)
├── Views/           # Main screens (Discover, Courses, SchoolDetail, CourseReels)
├── Components/      # Reusable UI (ReelView, SchoolCard, YouTubePlayer, Shimmer)
├── Services/        # OCW scraper, Supabase integration
└── Utilities/       # Preview data, Color+Hex extension
```

**Data flow**: `@Query` drives reactive updates from SwiftData. `@AppStorage` persists user preferences (autoplay, view mode). Navigation via `NavigationStack` with type-safe links.

**Video**: WKWebView iframe embed with `postMessage` control for play/pause/seek. Avoids YouTube Error 153 via proper origin matching.

## Design

Inspired by the [NASA Graphics Standards Manual (1975)](https://standardsmanual.com/products/nasa-graphics-standards-manual). Bold typography. Systematic spacing. Zero decoration. The interface stays out of the way so the lectures can speak.

Color tokens follow IBM Carbon's White Theme for WCAG 2.1 contrast compliance. School accent colors are derived from MIT's academic identity.

## Tech Stack

- **SwiftUI** — Declarative UI with `ScrollView` + `.scrollTargetBehavior(.paging)`
- **SwiftData** — Persistent storage with `@Query` reactive fetching
- **WKWebView** — YouTube iframe embed with JavaScript bridge
- **XcodeGen** — Project generation from `project.yml`
- **Maestro** — Automated UI testing flows

## Requirements

- iOS 17.0+
- Xcode 15+
- Swift 5.9+

## Build

```bash
# Generate Xcode project
xcodegen generate

# Build for simulator
xcodebuild -project MITReels.xcodeproj -scheme MITReels \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests
xcodebuild test -project MITReels.xcodeproj -scheme MITReels \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run Maestro UI tests
maestro test .maestro/
```

## License

Educational project. MIT OCW content is provided under MIT OpenCourseWare's [Creative Commons license](https://ocw.mit.edu/terms/).
