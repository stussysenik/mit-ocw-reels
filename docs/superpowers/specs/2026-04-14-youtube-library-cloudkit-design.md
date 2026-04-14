# YouTube Library + CloudKit — Design

**Date**: 2026-04-14
**Status**: Approved, ready for planning
**Author**: Brainstormed with Claude
**Scope**: Enable users to import any YouTube video or playlist into their own curated library, organize with custom courses + chapters, sync across their iCloud devices, and export their data. The existing 7,000-lecture built-in catalog stays untouched; user content mixes into the unified Discover feed.

---

## 1. Goal

Make MIT Reels capable of ingesting **any YouTube video or playlist** into a **user-owned library** that:

1. Syncs across the user's iCloud devices (private CloudKit DB, zero backend).
2. Mixes into the unified Discover feed alongside the built-in 51 educational sources.
3. Is fully editable — users can create courses, group lectures into chapters, rename, reorder, and delete.
4. Is portable — users can export/import their library as JSON via the iOS share sheet.

The hero flow: **paste a YouTube URL → confirm → doom-scroll it in the feed** in under 5 seconds for a 50-video playlist.

## 2. Non-Goals (v1)

- Channel imports (`youtube.com/@mit` paste support)
- Non-YouTube sources (Vimeo, direct MP4, Twitch VODs)
- Shared libraries / public CloudKit DB / social features
- Server-side backend, web dashboard, or cross-platform access
- Per-lecture resume position and playback history
- Offline video caching (YouTube ToS)
- User accounts — CloudKit provides identity via Apple ID

Each non-goal has an explicit "when to revisit" trigger documented below in §12.

## 3. Assumptions

1. User is signed into iCloud. If not, app falls back to local-only SwiftData store and surfaces a one-time banner: *"Sign into iCloud to sync your library."*
2. User has a YouTube Data API v3 key configured (already wired via `APIKeys.swift`). No changes to key management.
3. Existing SwiftData schema migrates cleanly — new fields all have defaults.
4. The existing `ReelPlayerPool`, `FeedEngine`, and `SlidingLoopStateMachine` do not need to change. User-created courses flow through the same rendering pipeline as built-in ones.
5. Import is an online-only operation — no value in queueing for later.

---

## 4. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  DiscoverView   CoursesView   UserLibraryCourseDetailView   │
│      │              │                    │                  │
│      └──── + ───────┴──── ImportSheet ────┘                  │
│                         │                                     │
└─────────────────────────┼─────────────────────────────────────┘
                          │
┌─────────────────────────▼─────────────────────────────────────┐
│                    Pipeline Layer                              │
│                                                                │
│  YouTubeURLParser  ─────┐                                      │
│    (pure function)      │                                      │
│                         ▼                                      │
│                  ImportPipeline (actor)                        │
│                         │                                      │
│            ┌────────────┼────────────┐                         │
│            ▼            ▼            ▼                         │
│   YouTubeAPIClient  LibraryDedupeIndex  LibraryExportService  │
│      (actor)           (actor)              (struct)          │
│                                                                │
└───────────────────────────┼─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                     Storage Layer                               │
│                                                                  │
│  ModelContainer(cloudKitDatabase: .private("iCloud.<team>"))    │
│                           │                                      │
│            ┌──────────────┼──────────────┐                       │
│            ▼              ▼              ▼                       │
│         Course        Lecture       (CloudKit private DB)       │
│       @Model         @Model            │                         │
│       + isUserCreated  + chapterTitle   │ automatic sync         │
│                        + sortOrder      ▼                        │
│                                    Other Devices                 │
└──────────────────────────────────────────────────────────────────┘
```

**Module boundaries**: each layer communicates only with the one directly below it. The pipeline layer never reaches into UI state. The storage layer never calls the network. This matches the existing codebase's actor isolation discipline.

## 5. Data Model Changes

Additive only. Three new fields, one new enum case, zero new `@Model` types. SwiftData auto-migrates because every new field has a default.

### 5.1 `Lecture` (MITReels/Models/Lecture.swift)

```swift
@Model
final class Lecture {
    // ... existing fields unchanged ...

    /// Optional chapter grouping within a course. Empty = unsorted.
    /// Lectures sharing the same (course, chapterTitle) form a chapter group.
    var chapterTitle: String = ""

    /// Stable ordering within a chapter (or within the course if no chapter).
    /// Lower values appear first. Defaults to 0; ties broken by insertion order.
    var sortOrder: Int = 0
}
```

Why a string for chapters and not a `@Model`: zero migration risk, CloudKit-trivial, and a course with chapters *"Week 1: Linear Algebra"* / *"Week 2: Probability"* is just a `groupBy(chapterTitle)` at query time. Promotes to a real model only if chapter-level metadata (cover images, notes) is ever needed. **YAGNI applies.**

### 5.2 `Course` (MITReels/Models/Course.swift)

```swift
@Model
final class Course {
    // ... existing fields unchanged ...

    /// Marks courses created by the user (via YouTube import or manual creation),
    /// as opposed to courses seeded from the built-in catalog.
    var isUserCreated: Bool = false
}
```

### 5.3 `UniversitySource` (MITReels/Models/UniversitySource.swift)

Add one case:

```swift
case userLibrary = "user_library"
```

With the expected `displayName: "My Library"`, neutral accent color, and a `Folder` SF Symbol. User-created courses set `sourceId = "user_library"`.

### 5.4 Migration

No migration code required. SwiftData's lightweight migration handles additive changes with defaults. Verified by `LectureSchemaMigrationTests` — opens a store built against the old schema, reads existing rows, writes one with the new fields, and checks round-trip.

## 6. Component Specifications

Each component below lists: purpose, public interface, complexity contract, and dependencies. Files target ≤150 LOC unless noted.

### 6.1 `YouTubeURLParser` (new — Services/YouTubeURLParser.swift)

**Purpose**: classify a pasted URL without making network calls.

**Interface**:

```swift
enum ParsedYouTubeURL: Equatable {
    case video(id: String)
    case playlist(id: String)
    case ambiguous(videoId: String, playlistId: String)   // watch?v=...&list=...
    case unsupported(reason: UnsupportedReason)
    case invalid

    enum UnsupportedReason { case channel, shorts, live, unknownHost }
}

enum YouTubeURLParser {
    static func parse(_ raw: String) -> ParsedYouTubeURL
}
```

**Complexity**: O(|url|) single-pass regex match. Zero allocations beyond capture groups. Budget: **<0.5ms** per parse.

**Accepted URL shapes**:
- `https://youtube.com/watch?v={11-char-id}`
- `https://www.youtube.com/watch?v={id}&list={id}` → `.ambiguous`
- `https://youtu.be/{id}`
- `https://youtube.com/playlist?list={id}`
- Stripped/trailing params tolerated; `m.youtube.com` tolerated

**Rejected**: channel URLs, `/shorts/`, `/live/`, any non-youtube host → `.unsupported` or `.invalid`.

**Dependencies**: `Foundation` only. Pure, testable, no actors needed.

### 6.2 `YouTubeAPIClient` additions (modified — Services/YouTubeAPIClient.swift)

Two new methods on the existing actor at `YouTubeAPIClient.swift:93`:

```swift
/// Fetch a single playlist's metadata + item count by playlist ID (not channel).
/// Cost: 1 unit. Returns nil if playlist not found or private.
func fetchPlaylist(id: String) async throws -> YouTubePlaylist?

/// Fetch a single video's metadata by video ID.
/// Cost: 1 unit. Returns nil if video not found, private, or deleted.
func fetchVideo(id: String) async throws -> YouTubeVideo?
```

Existing `fetchPlaylistItems(playlistId:)` at `YouTubeAPIClient.swift:163` is reused as-is for playlist imports — it already handles pagination.

**Complexity**: one URL round-trip each. Daily quota already guarded by `quotaRemaining` check on line 105. No changes to quota logic.

### 6.3 `LibraryDedupeIndex` (new — Services/LibraryDedupeIndex.swift)

**Purpose**: O(1) existence check for any `youtubeId` in the store, avoiding O(n·m) scans on every import.

**Concurrency model**: holds a dedicated background `ModelContext` spawned from the shared `ModelContainer`. All SwiftData reads happen on that context, not the main context — so warming and re-warming never block the UI.

**Interface**:

```swift
actor LibraryDedupeIndex {
    init(container: ModelContainer)

    /// One-time warm at app launch. O(n) in existing lectures, ~30-50ms for 10k rows.
    func warm() async

    /// O(1) lookup. True if a lecture with this youtubeId already exists anywhere
    /// in the store (built-in catalog OR user library).
    func contains(youtubeId: String) -> Bool

    /// Insert a newly-saved lecture's id into the index. O(1).
    func register(youtubeId: String)

    /// Re-warm the affected subset after a CloudKit remote change notification.
    func handleRemoteChange() async
}
```

**Complexity**:
- `warm()`: single `FetchDescriptor<Lecture>` with `propertiesToFetch = [\.youtubeId]` → thin projection, no relationship hydration. ~30ms for 10k rows. O(n) one-time.
- `contains` / `register`: O(1) `Set<String>` operations.
- `handleRemoteChange()`: O(delta) — processes only changed records from the CloudKit notification payload.

**Why this exists**: without it, every import would call `ModelContext.fetch(...where: youtubeId == X)` per incoming video — 500 SwiftData queries for a 500-video playlist, each ~0.5ms even with an index. The actor replaces these with in-memory `Set<String>` lookups: one O(n) warm at launch, then O(1) per check forever. Net: 500 imports go from ~250ms of query overhead to ~5μs of set operations.

### 6.4 `ImportPipeline` (new — Services/ImportPipeline.swift)

**Purpose**: orchestrate `ParsedYouTubeURL → fetched metadata → dedupe → SwiftData insert → feed refresh`.

**Interface**:

```swift
@MainActor
final class ImportPipeline: ObservableObject {
    @Published private(set) var state: ImportState = .idle

    enum ImportState {
        case idle
        case fetching(source: String)         // "Loading playlist..."
        case preview(PreviewPayload)          // user confirms
        case saving(progress: Double)         // 0.0–1.0
        case completed(course: Course, inserted: Int, skipped: Int)
        case failed(ImportError)
    }

    struct PreviewPayload {
        let kind: Kind
        let title: String
        let subtitle: String
        let thumbnails: [URL]
        let itemCount: Int
        enum Kind { case singleVideo, playlist }
    }

    func classify(url: String) async
    func confirmImport(into target: ImportTarget) async
    func cancel()
}

enum ImportTarget {
    case newCourse(name: String, chapterTitle: String?)
    case existingCourse(Course, chapterTitle: String?)
}
```

**State machine**: `idle → fetching → preview → saving → completed | failed`. Any state can return to `idle` via `cancel()`.

**Complexity per import**:
- Single video: 1 API call + 1 insert → <200ms p95
- 50-video playlist: 1 API call + 50 inserts batched → <300ms p95
- 500-video playlist: 10 API calls (serial for rate safety) + 500 inserts batched 200/txn → <2.5s p95

**Insertion strategy**: batched `modelContext.insert(...)` with one `save()` per batch of 200. This is the same pattern `OCWScraper.swift` uses for bulk seeding and is already validated in production.

**Dedupe**: every incoming `YouTubeVideo.videoId` hits `dedupeIndex.contains(...)`. Present → skip + increment `skipped` counter. Absent → create `Lecture`, insert, register in index.

### 6.5 `LibraryExportService` (new — Services/LibraryExportService.swift)

**Purpose**: round-trip user library to/from JSON for data portability.

**Interface**:

```swift
enum LibraryExportService {
    /// Encode all user-created courses + their lectures to streamed JSON.
    /// O(n+m) in courses and lectures; budget <1.5s for 1k courses.
    static func export(from container: ModelContainer) throws -> URL

    /// Decode a library.json file and merge into the store.
    /// Dedupes by youtubeId. Returns counts for confirmation UI.
    static func importLibrary(from url: URL, into container: ModelContainer) throws -> ImportSummary

    struct ImportSummary {
        let coursesAdded: Int
        let lecturesAdded: Int
        let coursesSkipped: Int
        let lecturesSkipped: Int
    }
}
```

**JSON schema** (v1, versioned):

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-04-14T12:00:00Z",
  "appVersion": "1.0.0",
  "courses": [
    {
      "courseNumber": "my-ml-101",
      "title": "My ML Course",
      "department": "User Library",
      "isUserCreated": true,
      "lectures": [
        {
          "youtubeId": "abc123DEF45",
          "title": "Linear Regression",
          "chapterTitle": "Week 1: Fundamentals",
          "sortOrder": 0
        }
      ]
    }
  ]
}
```

Schema version is load-bearing — future versions can add fields without breaking older exports.

### 6.6 `CloudKitContainer` (new — Services/CloudKitContainer.swift)

**Purpose**: single source of truth for `ModelContainer` configuration. Replaces the current inline configuration in `MITReelsApp.swift`.

```swift
enum CloudKitContainer {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Course.self, Lecture.self, /* existing models */])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.mitreels")   // resolved at plan time
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Fallback for users not signed into iCloud. Same schema, local only.
    static func makeLocalOnlyContainer() -> ModelContainer { /* see plan */ }
}
```

**Container ID is a plan-time decision**: the exact string `iCloud.com.<teamid>.MITReels` must be registered in the Apple Developer portal as a CloudKit container and added to the app's entitlements. The implementation plan pins the exact identifier in Phase 1.

**Detection**: on cold start, check `FileManager.default.ubiquityIdentityToken`. Nil → use local-only container + show banner. Non-nil → CloudKit container. The banner is dismissable but reappears on any subsequent cold start until the user signs in.

### 6.7 UI components (new — Views/Library/)

- **`ImportSheet`**: single text field, Paste button, live classification feedback. Calls `ImportPipeline.classify(url:)`.
- **`ImportPreviewSheet`**: renders `PreviewPayload`, lets user edit course name + chapter, pick target. Two buttons: *Save* and *Cancel*.
- **`UserLibraryCourseDetailView`**: grouped list by `chapterTitle`, swipe actions, drag-to-reorder, toolbar with *Play All* / *Rename* / *Add Lectures* / *Export* / *Delete*.
- **`ChapterSection`**: a single chapter's header + lectures. Reusable.
- **`CourseEditorSheet`**: inline course rename + chapter assign.

Each of these is a thin `View` that observes `ImportPipeline` or reads SwiftData via `@Query`. No new state management frameworks.

## 7. Data Flow — The Hero Path

```
User pastes "https://youtube.com/playlist?list=PLxyz"
          │
          ▼
ImportSheet.onPaste → ImportPipeline.classify(url: ...)
          │
          ▼
YouTubeURLParser.parse  →  .playlist(id: "PLxyz")                  [<0.5ms]
          │
          ▼
state = .fetching("Loading playlist...")
          │
          ▼
YouTubeAPIClient.fetchPlaylist(id: "PLxyz")
          │ + fetchPlaylistItems(playlistId: "PLxyz")
          ▼                                                          [~300ms]
state = .preview(PreviewPayload { title, 42 thumbs, 42 items })
          │
          ▼
User edits title, taps Save
          │
          ▼
ImportPipeline.confirmImport(into: .newCourse(name: "My ML Course"))
          │
          ▼
state = .saving(progress: 0.0)
          │
          ▼
for batch in lectures.chunks(of: 200):
  for video in batch:
    if !dedupeIndex.contains(video.id):                              [O(1)]
      insert Lecture                                                 [SwiftData]
      dedupeIndex.register(video.id)                                 [O(1)]
  modelContext.save()                                                [1 txn/batch]
  progress += batch.count / total
          │
          ▼
CloudKit background upload begins                                    [async, non-blocking]
          │
          ▼
state = .completed(course, inserted: 42, skipped: 0)
          │
          ▼
Toast: "Added 42 lectures to 'My ML Course'"
DiscoverView @Query re-fires → new lectures appear in feed          [reactive]
```

**Total user-perceived latency for a 42-video playlist: ~500-800ms.** The CloudKit upload continues in the background and does not block the UI.

## 8. Error Handling

Every state in `ImportPipeline.ImportState.failed` maps to a user-facing message and an in-code `ImportError`:

```swift
enum ImportError: LocalizedError {
    case invalidURL
    case unsupportedKind(ParsedYouTubeURL.UnsupportedReason)
    case playlistNotFound
    case videoNotFound
    case quotaExhausted      // already tracked in YouTubeAPIClient
    case network(URLError)
    case cloudKitUnavailable
    case saveFailed(Error)

    var errorDescription: String? { /* user-friendly message */ }
    var recoverySuggestion: String? { /* what to try next */ }
}
```

**Principles**:
- Never surface a raw `Error` to the user.
- Every error has a recovery suggestion.
- Quota exhaustion is not a failure — it's a *"come back tomorrow"* state with a countdown.
- CloudKit unavailable during import → fallback to local-only save + banner — never block the import.

## 9. CloudKit Specifics

**Schema deployment**: on first launch with CloudKit enabled, SwiftData pushes the schema to the development environment. Before App Store submission, manually promote to production via CloudKit Dashboard. Documented as a checklist item in the shipping phase.

**Record size**: each `Lecture` is ~1KB of text fields. Well under CloudKit's 1MB per-record limit.

**Sync throughput**: CloudKit private DB has no hard rate limit for normal use. A 500-lecture import generates ~500 KB of records; upload completes in seconds on WiFi.

**Conflict resolution**: last-writer-wins (SwiftData default). Acceptable because same user on multiple devices almost never edits the same lecture simultaneously. If we ever hit this, we add per-field timestamps.

**Schema evolution**: any future schema change must preserve defaults on all existing fields. This is enforced by `LectureSchemaMigrationTests`.

**Account changes**: when the user signs out of iCloud, SwiftData stops syncing but continues working locally. When they sign back in, sync resumes from the last checkpoint. No manual intervention needed.

## 10. Performance Contracts

All budgets are **p95** and enforced by performance tests that fail the build on regression.

| Operation | Budget | Test name |
|---|---|---|
| URL parse | <0.5ms | `ParserPerfTests.parseUnder1ms` |
| Dedupe warm (10k rows) | <50ms | `DedupeIndexPerfTests.warmUnder50ms` |
| Import 50-video playlist | <300ms | `ImportPipelinePerfTests.import50Under300ms` |
| Import 500-video playlist | <2500ms | `ImportPipelinePerfTests.import500Under2500ms` |
| Export 1k courses | <1500ms | `ExportServicePerfTests.export1kUnder1500ms` |
| Feed reactivity after insert | <16ms (1 frame) | Manual verification via Maestro + Instruments |

MIT-style back-of-envelope for the tightest constraint (500-video import <2500ms):
- 10 API requests × ~150ms typical RTT = 1500ms network
- 500 inserts × ~1.5ms amortized = 750ms SwiftData
- Overhead + serialization = ~250ms
- **Total ~2500ms.** Achievable but tight. If we regress, the fix is parallel batched API fetches (currently serial for quota safety).

## 11. Testing Strategy

### 11.1 Layer 1 — Unit tests (Swift Testing)

- `YouTubeURLParserTests` — table-driven, 15+ cases covering all URL shapes
- `LibraryDedupeIndexTests` — insertion, lookup, concurrent access, remote change handling
- `ImportPipelineTests` — state transitions with a stubbed `YouTubeAPIClient` protocol
- `LibraryExportServiceTests` — round-trip invariant (`decode(encode(x)) == x`)
- `LectureSchemaMigrationTests` — open old-schema store, write new fields, verify round-trip
- `ImportPipelinePerfTests`, `DedupeIndexPerfTests`, `ExportServicePerfTests` — performance budgets

### 11.2 Layer 2 — Integration tests

- URL → parser → pipeline → in-memory `ModelContainer` → assert course + N lectures present
- Import same playlist twice → second import yields 0 new rows (dedupe)
- Export → wipe → import → assert structural equality (round-trip)

### 11.3 Layer 3 — Maestro flows

```
.maestro/
├── 01_import_playlist.yaml      # paste playlist URL → verify course in feed
├── 02_import_single_video.yaml  # paste watch URL → verify in feed
├── 03_create_empty_course.yaml  # New Course → name → add videos
├── 04_edit_course.yaml          # rename, delete lecture, move to chapter
├── 05_play_all.yaml             # course → Play All → reel loads
├── 06_export_import.yaml        # export → fresh install → re-import
└── 07_cloudkit_sync.yaml        # two-simulator: device A → device B
```

All flows run via `flowdeck` on the simulator (per global tooling preference). Each flow ships with a reference screenshot in `screenshots/library/`. CI runs 01-06 every PR; 07 runs nightly.

## 12. When to Revisit Non-Goals

| Non-goal | Revisit trigger |
|---|---|
| Channel imports | First user complains pasting `@mit` doesn't work |
| Vimeo / MP4 / non-YouTube | Explicit user ask for a specific source |
| Shared libraries | Multi-user "I want to send this to a friend" moment |
| Web dashboard | First time you want to browse your library on a non-Apple device |
| Resume position | Power users asking "where was I?" after a session |
| Offline caching | Never (YouTube ToS) |
| User accounts | Never (CloudKit covers identity via Apple ID) |

## 13. Implementation Phases (preview for the plan)

The writing-plans skill will expand each of these into verifiable tasks with dependencies.

1. **CloudKit enablement** (foundation) — swap `ModelConfiguration`, add entitlement, migration test, iCloud fallback banner.
2. **Schema additions** — `chapterTitle`, `sortOrder`, `isUserCreated`, `.userLibrary` source case, migration test.
3. **Parser + API extensions** — `YouTubeURLParser`, two new `YouTubeAPIClient` methods, unit tests.
4. **Dedupe index** — `LibraryDedupeIndex` actor, warm at launch, unit + perf tests.
5. **Import pipeline** — `ImportPipeline` actor + state machine, integration tests.
6. **Import UI** — `ImportSheet`, `ImportPreviewSheet`, `+` buttons in Discover/Courses toolbars.
7. **Library UI** — `UserLibraryCourseDetailView`, `ChapterSection`, `CourseEditorSheet`, Play All entry point.
8. **Export service** — `LibraryExportService`, share-sheet integration, Document Types config.
9. **Maestro flows** — 01-07, one per user-facing capability.
10. **Ship checklist** — CloudKit production schema, privacy strings, screenshots, TestFlight.

Each phase produces a green build + passing tests before the next phase begins.

## 14. Open Questions (resolved during brainstorming)

- **Q**: Database choice — SwiftData+CloudKit, SQLite, or Postgres?
  **A**: SwiftData+CloudKit. SQLite-backed, free sync, existing models already CloudKit-shaped.

- **Q**: Where do user imports live in the UI?
  **A**: Unified Discover feed (via new `.userLibrary` source) + dedicated `UserLibraryCourseDetailView` for editing.

- **Q**: Chapters as a new `@Model` or a string field?
  **A**: String field on `Lecture`. Zero migration risk. Promote to a model only if chapter-level metadata is ever needed.

- **Q**: Channel imports in v1?
  **A**: No. Deferred until user demand.

- **Q**: Non-YouTube video sources in v1?
  **A**: No, but architecture allows via `VideoURLParser` protocol so the second parser is cheap to add.

- **Q**: Server-side backend?
  **A**: No. CloudKit covers sync. JSON export covers portability. Defer until a genuine web-access need arises.

---

*Brainstormed 2026-04-14. Next step: invoke `writing-plans` to break this into ordered implementation tasks.*
