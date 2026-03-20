# MIT OCW Reels

TikTok-style short-form lecture reels from MIT OpenCourseWare. Swipe through 100+ real MIT lectures organized by course, or discover new content in a continuous feed.

<!-- TODO: Add screenshot -->

## Features

- **Discover tab** — infinite vertical scroll of MIT lectures as short-form reels
- **Courses tab** — browse by MIT course, tap into a course's reel playlist
- **YouTube playback** — embedded YouTube player for each lecture segment
- **Offline seed data** — 100+ lectures bundled via `seed_data.json`, no backend required to run

## Tech Stack

- **SwiftUI** — declarative UI with iOS 17+ APIs
- **SwiftData** — local persistence
- **XcodeGen** — `project.yml` generates `MITReels.xcodeproj`
- **YouTube iFrame** — embedded via `WKWebView`

## Getting Started

### Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 17+ simulator or device

### Build & Run

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Open in Xcode
open MITReels.xcodeproj

# Build & run on simulator (Cmd+R)
```

## Project Structure

```
MITReels/
├── MITReelsApp.swift          # App entry point & SwiftData setup
├── ContentView.swift          # Root tab view (Discover / Courses)
├── Models/
│   ├── Course.swift           # Course model
│   └── Lecture.swift          # Lecture model
├── Views/
│   ├── DiscoverView.swift     # Vertical reel feed
│   ├── CoursesView.swift      # Course list
│   ├── CourseReelsView.swift   # Reels within a course
│   └── ReelView.swift         # Individual reel card
├── Components/
│   └── YouTubePlayerView.swift # WKWebView YouTube embed
├── Services/
│   └── SupabaseService.swift  # Backend service (placeholder)
└── Resources/
    └── seed_data.json         # 100+ MIT OCW lectures
```

## License

MIT
