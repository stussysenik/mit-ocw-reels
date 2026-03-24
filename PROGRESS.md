# MIT Reels — Development Progress

## Vision

Build a TikTok-style iOS app that makes the world's best university lectures as discoverable as social media content. Open, swipe, learn — no accounts, no ads.

## Timeline

### Day 1 — Foundation (Mar 20)

| Commit | What shipped |
|--------|-------------|
| `a8da1e5` | **Initial MVP**: Discover + Courses tabs, basic vertical scroll feed, SwiftData models for Course and Lecture |
| `84b6318` | Supabase backend exploration (later replaced with local seed data) |

**Key decision**: Dropped Supabase in favor of bundled JSON seed data + background scraping. Faster cold start, works offline, zero infrastructure.

### Day 2 — Design System & Video Reliability (Mar 21–22)

| Commit | What shipped |
|--------|-------------|
| `7c3aaa1` | Full lecture catalogue, multi-source filtering, macOS support exploration |
| `0886e13` | **NASA-inspired redesign**: IBM Carbon tokens, school gradients, WCAG 2.1 compliance |
| `18e0ab2` | YouTube oEmbed validation pipeline, instructor metadata |
| `7eb2b0f` | OCW links (syllabus, readings), immersive full-screen feed |
| `178b2cb` | O(1) rendering, thumbnail fixes, department filters |
| `61c7204` | Test suite: OCW scraper, filter, and URL extraction tests |
| `333c470` | **O(1) rendering overhaul**: actor isolation, code tightening |
| `594ad7f` | Fix WKWebView memory accumulation crash |
| `abf4a9a` | Eliminate 113MB WKWebView cache crash + data quality |
| `d894236` | Fault-tolerant playback + YouTube captions |
| `53dc955` | YouTube deep-link button overlay |
| `4b1ef12` | Fix duplicate key crash, code cleanup |

**Key decision**: Moved from eager WebView creation to pooled, lazy initialization after discovering WKWebView accumulated 113MB of cache data, causing OOM crashes.

### Day 3 — Multi-Source Explosion (Mar 23)

| Commit | What shipped |
|--------|-------------|
| `31e64d4` | **Multi-university**: 974 courses, 3,325 lectures from 9 universities |
| `300fb7d` | Expanded to 30 sources, 1,588 courses, 5,117 lectures |
| `98555dd` | Fix 5-8s launch hang from synchronous 5,000+ record seed (batched to 200/batch) |
| `820d504` | Sub-250ms feed rendering — cap feed at 200, skip relationship loading |
| `0f1bc87` | 39 sources, 5,725 lectures + video validation gate |
| `97ddd72` | **47 sources**, 7,127 lectures including creative/maker content |
| `1033ef9` | Data-driven `UniversitySource` enum, dead code removal |
| `95652d3` | Preference engine, shake-to-filter, 56 sources, HD on WiFi |
| `0adaa9b` | TikTok-style video preloading — next reel pre-initializes |
| `c5ad16c` | Improved thumbs-up/down — 44pt targets, haptic, color flash |
| `ad48b33` | Toast feedback on thumbs + swipe-to-delete algorithm weights |
| `5fe64ec` | Smooth dislike choreography, expandable labels |
| `66c15af` | Two-row metadata layout |
| `2dbc6e7` | **Multi-source support**: pooled WKWebView, settings cleanup |

**Key crisis**: Adding 5,000+ lectures caused a 5-8s launch hang. Fixed by batching seed insertion (200 items/batch, ~50ms each) and capping the initial feed at 200 items. Feed rendering went from seconds to sub-250ms.

### Day 4 — Polish & Architecture (Mar 24)

| Commit | What shipped |
|--------|-------------|
| `fd2b0fb` | Staggered WKWebView pool, stale frame fix |
| `e75829a` | Dislike auto-advances to next reel, MIT-only default sources |
| `e43b142` | Titans of CNC: 76 lectures, 27 courses |
| `0f9536a` | Cached thumbnails, visibility bridge, HTML entity cleanup |
| `31ba504` | **Actor-based FeedEngine**: Sendable DTO boundary, weighted sampling, recursion guard, dislike race condition fix |

**Key decision**: Replaced the static 200-item shuffled array with an actor-isolated sliding-window pipeline. The engine now computes batches dynamically using real-time interaction weights, with velocity-aware buffer depth (10–30 items).

## Architecture Evolution

```
Day 1: @Query → shuffled() → ForEach
        Simple, but no preference learning, no dedup, loads everything

Day 2: @Query → filter(eligible) → prefix(200).shuffled() → ForEach
        Capped for performance, but still static — thumbs have no effect on feed

Day 3: @Query → FeedPreferences weights → weightedShuffle → prefix(200) → ForEach
        Preference learning works, but still pre-computed — no real-time adaptation

Day 4: @Query → FeedItem DTO → FeedEngine actor → sliding window → [String] IDs → Lecture lookup → ForEach
        Real-time weighted batches, velocity-aware depth, session-local soft signals,
        per-course caps, Sendable boundary, no @Model data races
```

## What Shipped in v1.0.0

- **51 educational sources** — MIT, Stanford, Harvard, Yale, Caltech, Berkeley, CMU, Princeton, Cornell, 3Blue1Brown, Khan Academy, Crash Course, freeCodeCamp, Computerphile, Fireship, and 36 more
- **7,000+ validated lectures** across 2,000+ courses
- **Actor-based feed engine** — sliding-window pipeline with stratified weighted sampling
- **Preference learning** — thumbs-up/down with source and topic weight persistence
- **3-tier thumbnail cache** — NSCache → URLCache → network, 7 thumbnails always warm
- **Video validation pipeline** — oEmbed checks, 24h scraper, 7-day re-validation
- **NASA-inspired design** — IBM Carbon tokens, WCAG 2.1 contrast, golden ratio spacing
- **8 unit test files** + 8 Maestro UI test flows
- **Zero external dependencies** — SwiftUI, SwiftData, WebKit, UIKit only

## Metrics

| Metric | Value |
|--------|-------|
| Swift source files | 39 |
| Lines of code | ~15,700 |
| Test files | 8 (unit) + 8 (Maestro UI) |
| Test LOC | ~676 |
| Educational sources | 51 |
| Lectures (seed) | 7,000+ |
| Courses | 2,000+ |
| External dependencies | 0 |
| Minimum iOS | 17.0 |
| Total commits | 37 |
| Development time | 5 days |
