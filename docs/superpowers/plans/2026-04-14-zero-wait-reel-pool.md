# Zero-Wait Reel Pool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate visible thumbnail-to-player transitions on rapid consecutive swipes in the MIT OCW Reels discover feed. Target: 5+ flicks at 150ms interval with zero visible load after swipe #1, plus fix a physics gap where mid-settle gesture grabs lose spring velocity.

**Architecture:** Replace the 3-slot checkout/checkin `WKWebViewPool` (which kills video state on checkin) with a 5-slot `ReelPlayerPool` whose slots are keyed by relative position from the current center (−2…+2). Slots share one `WKProcessPool`, warm up via `loadVideoById({mute:1}) → state 1 → pauseVideo → seekTo(0)` (which forces actual first-frame decode — `cueVideoById` alone does *not* decode per the IFrame Player API docs), and persist across cell recycling. Velocity handoff is done the Origami/POP way: a scalar `pendingVelocity` field on `VelocityTracker` seeded from `spring.velocity` when the user interrupts a settling animation.

**Tech Stack:** Swift 5.9, SwiftUI, UIKit (`WKWebView`, `WKProcessPool`, `WKWebsiteDataStore`), Swift Testing framework (`import Testing`), FlowDeck CLI for builds/tests/simulator, Instruments (Allocations + Time Profiler + Core Animation) for Phase 6 validation.

**Spec:** `docs/superpowers/specs/2026-04-13-zero-wait-reel-pool-design.md`

---

## File Structure

### New files

- `MITReels/Services/ReelPlayerPool.swift` — `@MainActor` pool owning 5 persistent `WKWebView` instances, slot state machine, warm-up sequencer, jetsam recovery
- `MITReelsTests/Services/ReelPlayerPoolTests.swift` — unit tests for slot rotation, warm-up state machine, memory pressure shrink, jetsam recovery
- `MITReelsTests/Services/ThumbnailPrefetcherTests.swift` — extend existing test file OR create if absent; tests for bumped LRU and backward-window coverage

### Modified files

- `MITReels/Physics/VelocityTracker.swift` — add `pendingVelocity: Double?` field + `seedVelocity(_:)` method; update `velocity` accessor to fall through to pending
- `MITReels/Physics/SlidingLoopStateMachine.swift` — replace `velocityTracker.reset()` in `willBeginDragging()` with `velocityTracker.seedVelocity(spring.velocity)` when transitioning from `.settling`
- `MITReelsTests/Physics/VelocityTrackerTests.swift` — add tests for seed + fall-through behaviour
- `MITReelsTests/Physics/SlidingLoopStateMachineTests.swift` — add mid-settle grab velocity-preservation test
- `MITReels/Services/ThumbnailPrefetcher.swift` — bump `countLimit` 30→64; add `prefetchIdsAround(centerIndex:window:in:)` helper
- `MITReels/Views/DiscoverView.swift` — instantiate `ReelPlayerPool`; replace `count: 6` prefetch with ±25 window; call `pool.shift(toCenterIndex:)` on `visibleIndex` change; delete `nextId` deferred sleep block and `isNearby` pass-through; delete `WKWebViewPool.shared.handleMemoryWarning()` line
- `MITReels/Views/ReelView.swift` — remove `@State` video vars, remove `isNearby` property, replace inline `YouTubePlayerView` with a new `PoolBorrowedPlayerView` representable
- `MITReels/Components/YouTubePlayerView.swift` — **delete** in Phase 5 (replaced by `PoolBorrowedPlayerView` + pool-owned coordinator logic)
- `MITReels/Services/WKWebViewPool.swift` — **delete** in Phase 5
- `MITReels/MITReelsApp.swift` — replace `WKWebViewPool.shared.warmUp()` with `ReelPlayerPool.shared.warmUp()`
- `MITReels.xcodeproj/project.pbxproj` — add `ReelPlayerPool.swift` and its test file to the appropriate targets; remove `WKWebViewPool.swift` and `YouTubePlayerView.swift` references in Phase 5

### Unchanged (explicitly out of scope)

- `MITReels/Physics/Spring.swift`, `SnapTarget.swift`, `DisplayLinkDriver.swift`
- `MITReels/Components/SlidingLoop*.swift` — host scroll view and state machine wiring stays as-is
- `MITReels/Services/FeedEngine.swift` — no buffer changes (its `displayWindow` is what we read for ±25 prefetch)
- `MITReels/Services/CachedThumbnailView.swift` — consumer already, no change

---

## Prerequisites

Run these once before Task 1. Each is a checkbox — confirm before proceeding.

- [ ] **Pre-Step 1: Confirm FlowDeck config is saved for this project**

```bash
flowdeck config get
```

Expected: `workspace = MITReels.xcodeproj`, `scheme = MITReels`. If missing, set with:

```bash
flowdeck config set -w /Users/s3nik/Desktop/mit-ocw-reels/MITReels.xcodeproj -s MITReels
```

- [ ] **Pre-Step 2: Pick a simulator for testing**

```bash
flowdeck simulator list -P iOS -A | head -10
```

Pick an iPhone simulator (e.g. "iPhone 16 Pro"). Use its exact name in later `-S` flags. For memory ceiling validation in Phase 6, also boot "iPhone SE (3rd generation)" — that's the iPhone-SE-class jetsam target.

- [ ] **Pre-Step 3: Baseline test run**

```bash
flowdeck test -S "iPhone 16 Pro"
```

Expected: all existing tests green. If anything is red, fix it before layering this work.

- [ ] **Pre-Step 4: Ensure branch is clean**

```bash
git status
```

Expected: clean working tree on `feature/sliding-loop-physics`. The two untracked spec/plan files may be present — those are this plan and its spec.

---

## Phase 1: Velocity Handoff (XS)

**Rationale:** Independent physics fix. Lands immediately, no dependencies on any other phase. Fixes `SlidingLoopStateMachine.willBeginDragging()` discarding spring residual velocity on mid-settle interrupt. Uses the Origami `POPBouncyPatch.mm:144-152` pattern (scalar write, not sample reconstruction).

### Task 1.1: Add `pendingVelocity` to `VelocityTracker`

**Files:**
- Modify: `MITReels/Physics/VelocityTracker.swift`
- Test: `MITReelsTests/Physics/VelocityTrackerTests.swift`

- [ ] **Step 1: Write the failing test — seeded velocity reads back before samples arrive**

Add to `VelocityTrackerTests.swift` (after `zeroTimespanReturnsZeroVelocity`):

```swift
/// Seeding a velocity before any samples arrive makes the tracker report
/// that velocity. Models the Origami "catch the moving page" handoff —
/// spring velocity flows into the drag state as a scalar.
@Test func seedVelocityBeforeSamplesReadsBackSeededValue() {
    var tracker = VelocityTracker()
    tracker.seedVelocity(1234)
    #expect(tracker.velocity == 1234)
}

/// A seeded velocity is ignored once two real samples exist. The real
/// rolling-window reading takes over without any handoff glitch.
@Test func seedVelocityFallsThroughOnceSamplesArrive() {
    var tracker = VelocityTracker()
    tracker.seedVelocity(9999)  // obviously wrong number
    let dt = 1.0 / 60.0
    tracker.add(position: 0, at: 0)
    tracker.add(position: 10, at: dt)
    // Two samples → computed = (10 - 0) / (1/60) = 600 pts/sec.
    // The seed is discarded.
    #expect(abs(tracker.velocity - 600) < 1)
}

/// reset() clears pendingVelocity as well as samples.
@Test func resetClearsPendingVelocity() {
    var tracker = VelocityTracker()
    tracker.seedVelocity(500)
    tracker.reset()
    #expect(tracker.velocity == 0)
}

/// Single sample + a pending seed: seed still wins (samples.count < 2).
@Test func singleSampleUsesSeedNotZero() {
    var tracker = VelocityTracker()
    tracker.seedVelocity(750)
    tracker.add(position: 0, at: 0)
    #expect(tracker.velocity == 750)
}
```

- [ ] **Step 2: Run tests — verify the four new tests FAIL (seedVelocity doesn't exist yet)**

```bash
flowdeck test -S "iPhone 16 Pro" -f "VelocityTrackerTests"
```

Expected: build error `value of type 'VelocityTracker' has no member 'seedVelocity'`.

- [ ] **Step 3: Implement `pendingVelocity` + `seedVelocity` in `VelocityTracker`**

Replace the body of `MITReels/Physics/VelocityTracker.swift` after the struct opening:

```swift
struct VelocityTracker: Sendable {
    private struct Sample: Sendable {
        let position: Double
        let time: CFTimeInterval
    }

    private var samples: [Sample] = []
    private let maxSamples = 3
    private let maxAge: CFTimeInterval = 0.1 // 100ms

    /// Scalar velocity seeded before samples arrive — used to model the
    /// Origami "catch the moving page" handoff (POPBouncyPatch.mm:144-152).
    /// Any real sample window (≥2 samples) takes precedence via the
    /// `velocity` accessor, so this value is only consulted during the
    /// instant between a mid-settle grab and the first touch-move.
    private var pendingVelocity: Double?

    mutating func add(position: Double, at time: CFTimeInterval) {
        samples.append(Sample(position: position, time: time))
        samples.removeAll { time - $0.time > maxAge }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    /// Current velocity in points per second. Reading order:
    /// 1. If ≥2 samples, compute from the rolling window (real motion wins)
    /// 2. Otherwise, return the seeded value if present
    /// 3. Otherwise, 0
    var velocity: Double {
        if samples.count >= 2 {
            let first = samples.first!
            let last = samples.last!
            let dt = last.time - first.time
            guard dt > 0 else { return 0 }
            return (last.position - first.position) / dt
        }
        return pendingVelocity ?? 0
    }

    /// Seed the tracker with a scalar residual velocity. Used by
    /// `SlidingLoopStateMachine.willBeginDragging()` to inherit the
    /// spring's velocity on a mid-settle interrupt.
    mutating func seedVelocity(_ v: Double) {
        pendingVelocity = v
    }

    mutating func reset() {
        samples.removeAll()
        pendingVelocity = nil
    }
}
```

- [ ] **Step 4: Run tests — verify ALL VelocityTracker tests pass**

```bash
flowdeck test -S "iPhone 16 Pro" -f "VelocityTrackerTests"
```

Expected: 9 tests pass (5 existing + 4 new). If any of the existing tests regress, the most likely cause is that `velocity` changed semantics for the samples-only case — double-check the `if samples.count >= 2` branch still matches the old formula.

### Task 1.2: Wire the handoff into `SlidingLoopStateMachine.willBeginDragging`

**Files:**
- Modify: `MITReels/Physics/SlidingLoopStateMachine.swift:53-56`
- Test: `MITReelsTests/Physics/SlidingLoopStateMachineTests.swift`

- [ ] **Step 1: Write the failing test — mid-settle grab preserves spring velocity**

Add to `SlidingLoopStateMachineTests.swift`:

```swift
/// Mid-settle grab must carry the spring's residual velocity into the
/// new drag, so the page feels like a moving object the user caught —
/// not a stopped object they started. Without handoff, willBeginDragging
/// resets the tracker and subsequent willEndDragging reads 0.
@Test func midSettleGrabPreservesSpringVelocity() {
    var m = makeMachine()
    m.willBeginDragging()
    m.didScroll(offset: 0, at: 0.0)
    m.didScroll(offset: 20, at: 0.016)
    m.didScroll(offset: 40, at: 0.032)
    _ = m.willEndDragging(offset: 40)  // spring now has velocity > 0
    _ = m.tick(dt: 1.0 / 60.0)         // spring advances a frame

    // Grab mid-settle. The tracker should now be seeded with the spring's
    // current velocity, so a willEndDragging with no new samples reads
    // non-zero velocity.
    m.willBeginDragging()
    let target = m.willEndDragging(offset: 41)
    // Forward motion → target should be page 1 (1000), not page 0.
    #expect(target == 1000)
}

/// Grab from rest (not from settling) seeds 0 — no residual to inherit.
@Test func grabFromRestDoesNotInventVelocity() {
    var m = makeMachine()
    m.willBeginDragging()  // from .idle
    // No samples, no motion. Settling target should be current page.
    let target = m.willEndDragging(offset: 0)
    #expect(target == 0)
}
```

- [ ] **Step 2: Run tests — verify `midSettleGrabPreservesSpringVelocity` FAILS**

```bash
flowdeck test -S "iPhone 16 Pro" -f "SlidingLoopStateMachineTests"
```

Expected: `midSettleGrabPreservesSpringVelocity` fails because current `willBeginDragging()` calls `velocityTracker.reset()`, throwing away spring velocity. `grabFromRestDoesNotInventVelocity` passes (coincidentally, since reset() and seedVelocity(0) produce the same reading).

- [ ] **Step 3: Update `willBeginDragging` to seed instead of reset**

In `MITReels/Physics/SlidingLoopStateMachine.swift`, replace lines 48-56 (the `willBeginDragging` doc comment and body) with:

```swift
    /// Forwarded from `scrollViewWillBeginDragging`.
    ///
    /// Transitions to `.dragging` unconditionally — from `.idle` (normal start)
    /// or from `.settling` (mid-settle interrupt). On a mid-settle interrupt
    /// the spring's residual velocity is handed off to the velocity tracker
    /// via a scalar seed (Origami `POPBouncyPatch.mm:144-152` pattern), so
    /// the subsequent `willEndDragging` reads the real motion the user's
    /// finger caught instead of zero.
    mutating func willBeginDragging() {
        let residual: Double = {
            if case .settling = state { return spring.velocity }
            return 0
        }()
        velocityTracker.reset()
        velocityTracker.seedVelocity(residual)
        state = .dragging
    }
```

Note: we call `reset()` first to clear any stale samples from a prior drag, *then* seed the scalar. The scalar is unaffected by `reset()`'s sample clear because it's stored in a separate field — but `reset()` now also clears `pendingVelocity` (see Task 1.1 Step 3). That's why we call `seedVelocity` *after* `reset()`.

- [ ] **Step 4: Run tests — verify state machine tests pass**

```bash
flowdeck test -S "iPhone 16 Pro" -f "SlidingLoopStateMachineTests"
```

Expected: all state machine tests pass, including `midSettleGrabPreservesSpringVelocity` and the pre-existing `interruptDuringSettlingReEntersDragging`.

- [ ] **Step 5: Run the full physics test suite once to check no regressions**

```bash
flowdeck test -S "iPhone 16 Pro" -f "Physics"
```

Expected: all physics tests pass.

- [ ] **Step 6: Commit Phase 1**

```bash
git add MITReels/Physics/VelocityTracker.swift \
        MITReels/Physics/SlidingLoopStateMachine.swift \
        MITReelsTests/Physics/VelocityTrackerTests.swift \
        MITReelsTests/Physics/SlidingLoopStateMachineTests.swift
git commit -m "$(cat <<'EOF'
feat(physics): velocity handoff on mid-settle grab

Add pendingVelocity scalar to VelocityTracker and seed it from
Spring.velocity when willBeginDragging transitions from .settling.
Models the Origami/POP POPBouncyPatch.mm:144-152 pattern: velocity
is first-class state, written directly mid-flight, not reconstructed
from position deltas.

Fixes a gap where grabbing a settling page felt like starting from
a dead stop — the new behaviour makes it feel like catching a moving
object, which is the "Down pulse" behaviour the rest of the spring
settle physics was already designed for.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: ReelPlayerPool Primitive (M)

**Rationale:** Zero-risk infrastructure phase. Builds the pool as a standalone primitive with unit tests. Does not touch any existing view code. The pool is a drop-in replacement for the current `WKWebViewPool` but with completely different semantics: slots are long-lived, keyed by relative position, warmed via mute-autoplay-pause, and share a single `WKProcessPool`.

### Task 2.1: Skeleton file + slot type + state enum

**Files:**
- Create: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Create the file with empty class + slot type**

Write `MITReels/Services/ReelPlayerPool.swift`:

```swift
import WebKit

/// Persistent pool of 5 `WKWebView` instances for zero-wait reel playback.
///
/// Keyed by *relative position from the current center* (`-2…+2`), not by
/// lecture identity. When the user scrolls to a new center, `shift` rotates
/// slot assignments in place: the rolled-off slot's WebView is re-used
/// (not re-created) to warm the new +2 position.
///
/// All 5 WebViews share one `WKProcessPool` and `WKWebsiteDataStore.default()`
/// so `yt-player.js` downloads once and iframes re-use the cached bundle.
///
/// Warm-up sequence per slot uses `loadVideoById({mute: 1})` + `pauseVideo`
/// at time 0 — NOT `cueVideoById`. The YouTube IFrame Player API docs are
/// explicit: `cueVideoById` "does not request the video stream until
/// playVideo() or seekTo() is called." State 5 (CUED) is a metadata signal,
/// not a decoded-frame signal. Mute-autoplay-pause is the only path that
/// guarantees first-frame decode.
@MainActor
final class ReelPlayerPool {

    // MARK: - Slot

    enum SlotState: Equatable {
        /// No video assigned yet; iframe HTML loaded but inert.
        case empty
        /// `loadVideoById` called, awaiting YouTube state 1 (playing muted).
        case loading
        /// State 1 fired; `pauseVideo` + `seekTo(0)` called, awaiting state 2.
        case warming
        /// State 2 at time 0: first frame decoded, paused, muted, off-alpha.
        /// Ready to promote to `.playing` in <50ms via `unMute + playVideo`.
        case warm
        /// The one center slot: unmuted, playing, visible.
        case playing
        /// Warm-up timed out or YouTube error. Thumbnail-only fallback.
        case failed(consecutiveFailures: Int)
        /// Memory-pressure or jetsam recovered: iframe HTML reloaded, ready
        /// to be reassigned on the next `shift` pass.
        case recycled
    }

    final class Slot {
        let webView: WKWebView
        var relativePosition: Int
        var state: SlotState = .empty
        var lectureId: String?
        var warmUpDeadline: Task<Void, Never>?

        init(webView: WKWebView, relativePosition: Int) {
            self.webView = webView
            self.relativePosition = relativePosition
        }
    }

    // MARK: - Singleton + init

    static let shared = ReelPlayerPool()

    private let capacityPerSide: Int
    private var slots: [Slot] = []
    private let processPool = WKProcessPool()
    private var navDelegate: PoolNavigationDelegate!
    private var messageHandler: PoolMessageHandler!

    init(capacityPerSide: Int = 2) {
        self.capacityPerSide = capacityPerSide
        self.navDelegate = PoolNavigationDelegate(pool: self)
        self.messageHandler = PoolMessageHandler(pool: self)
    }

    // MARK: - Public API (expanded in later tasks)

    func warmUp() { /* Task 2.3 */ }
    func shift(toCenterIndex index: Int, in lectures: [Lecture]) { /* Task 2.5 */ }
    func playerView(forRelativePosition rp: Int) -> UIView? { /* Task 2.6 */ return nil }
    func playCenter() { /* Task 2.7 */ }
    func pauseAllButCenter() { /* Task 2.7 */ }
    func handleMemoryPressure() { /* Task 2.8 */ }

    // MARK: - Internal helpers (defined in later tasks)

    fileprivate func didFinishNavigation(for webView: WKWebView) { /* Task 2.3 */ }
    fileprivate func didReceiveMessage(_ body: String, from webView: WKWebView) { /* Task 2.4 */ }
    fileprivate func webContentProcessDidTerminate(for webView: WKWebView) { /* Task 2.9 */ }
}

// MARK: - Nav delegate (jetsam + ready tracking)

private final class PoolNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var pool: ReelPlayerPool?
    init(pool: ReelPlayerPool) { self.pool = pool }

    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        Task { @MainActor [weak pool] in
            pool?.didFinishNavigation(for: webView)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak pool] in
            pool?.webContentProcessDidTerminate(for: webView)
        }
    }
}

// MARK: - Script message handler (YouTube state events)

private final class PoolMessageHandler: NSObject, WKScriptMessageHandler {
    weak var pool: ReelPlayerPool?
    init(pool: ReelPlayerPool) { self.pool = pool }

    func userContentController(_ ucc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let body = msg.body as? String, let wv = msg.webView else { return }
        Task { @MainActor [weak pool] in
            pool?.didReceiveMessage(body, from: wv)
        }
    }
}
```

- [ ] **Step 2: Add the new file to the Xcode project**

Open `MITReels.xcodeproj` in Xcode and confirm the new file is added to the `MITReels` target (right-click the `Services` group → "Add Files to MITReels…" → select `ReelPlayerPool.swift`, check `MITReels` target, uncheck tests target).

Alternative: use `ruby -e` or a pbxproj scripting helper if you prefer. But opening in Xcode is the safe path for a single file addition.

- [ ] **Step 3: Build to verify the skeleton compiles**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: build succeeds with no warnings on the new file. Any compile error here is a typo — fix before moving on.

- [ ] **Step 4: Commit skeleton**

```bash
git add MITReels/Services/ReelPlayerPool.swift MITReels.xcodeproj/project.pbxproj
git commit -m "feat(players): scaffold ReelPlayerPool skeleton"
```

### Task 2.2: Player HTML with mute-default playerVars

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Add the player HTML constant and WebView factory**

In `ReelPlayerPool.swift`, add a `static let` for the HTML and a private `makeWebView()` factory. The HTML is adapted from `WKWebViewPool.playerHTML` with key differences:
- `playerVars.mute = 1` is set at player-creation time (prevents audio leak if `loadVideoById({mute:1})` is ignored)
- A new `prepareWarm(videoId)` JS function that loads the video muted, waits for state 1, then pauses at 0
- Exposes `promoteToPlaying()` for the unmute handoff
- Exposes `demoteToWarm()` for pausing when the slot rolls off center

Add below the `init`:

```swift
    // MARK: - HTML + WebView factory

    private static let playerHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
    * { margin: 0; padding: 0; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
    #player { width: 100%; height: 100%; }
    #player iframe { background: transparent !important; }
    </style>
    </head>
    <body>
    <div id="player"></div>
    <script>
    var tag = document.createElement('script');
    tag.src = "https://www.youtube.com/iframe_api";
    document.head.appendChild(tag);

    var player;
    var apiReady = false;
    var playerReady = false;
    var pendingWarm = null;

    function msg(s) {
        try { window.webkit.messageHandlers.poolEvent.postMessage(s); } catch(e) {}
    }

    function onYouTubeIframeAPIReady() {
        apiReady = true;
        msg('apiReady');
        if (pendingWarm) { startWarm(pendingWarm); pendingWarm = null; }
    }

    function ensurePlayer(videoId) {
        if (player) return true;
        if (!apiReady) { pendingWarm = videoId; return false; }
        player = new YT.Player('player', {
            videoId: videoId,
            playerVars: {
                playsinline: 1, rel: 0, modestbranding: 1,
                controls: 1, fs: 1, enablejsapi: 1,
                mute: 1, autoplay: 1,  // start muted + autoplay to force decode
                origin: 'https://mitreels.app'
            },
            events: {
                'onReady': function() {
                    playerReady = true;
                    msg('playerReady');
                },
                'onStateChange': function(e) { msg('state:' + e.data); },
                'onError': function(e) { msg('error:' + e.data); }
            }
        });
        return true;
    }

    // Warm-up: load muted, wait for state 1 (PLAYING), pause + seek to 0.
    // This is the only sequence that forces YouTube's iframe to actually
    // decode the first frame. cueVideoById does NOT decode per the API docs.
    function startWarm(videoId) {
        if (!ensurePlayer(videoId)) return;
        if (playerReady) {
            player.mute();
            player.loadVideoById({ videoId: videoId, startSeconds: 0 });
            // State 1 handler (Swift side) will call pauseAtZero() when ready.
        } else {
            pendingWarm = videoId;
        }
    }

    function pauseAtZero() {
        if (!player || !playerReady) return;
        player.pauseVideo();
        player.seekTo(0, true);
    }

    function promoteToPlaying() {
        if (!player || !playerReady) return;
        player.unMute();
        player.playVideo();
    }

    function demoteToWarm() {
        if (!player || !playerReady) return;
        player.pauseVideo();
        player.mute();
        player.seekTo(0, true);
    }

    function seekTo(s) { if (player && playerReady) player.seekTo(s, true); }
    function clearSlot() { if (player) { player.stopVideo(); } }
    </script>
    </body>
    </html>
    """

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.userContentController.add(messageHandler, name: "poolEvent")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.scrollView.isScrollEnabled = false
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.alpha = 0  // off until slot is promoted
        wv.navigationDelegate = navDelegate
        return wv
    }
```

- [ ] **Step 2: Build to verify HTML string escapes are correct**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build. If a compile error about unterminated string, check the triple-quote termination.

- [ ] **Step 3: Commit**

```bash
git add MITReels/Services/ReelPlayerPool.swift
git commit -m "feat(players): add ReelPlayerPool HTML with mute-autoplay warm-up"
```

### Task 2.3: Warm-up — implement `warmUp()` that creates 5 slots and loads HTML

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Fill in `warmUp()` — create 5 slots, load HTML, register nav delegate**

Replace the empty `warmUp()` placeholder with:

```swift
    /// Create 5 persistent WebViews and load the player HTML into each.
    /// Call once at app init. Staggered 250ms apart to avoid thundering-herd
    /// WebContent process spawn at launch.
    func warmUp() {
        guard slots.isEmpty else { return }
        let positions = Array(-capacityPerSide ... capacityPerSide)
        for (i, pos) in positions.enumerated() {
            let wv = makeWebView()
            let slot = Slot(webView: wv, relativePosition: pos)
            slots.append(slot)
            let delayMs = i * 250
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard self != nil else { return }
                wv.loadHTMLString(Self.playerHTML, baseURL: URL(string: "https://mitreels.app"))
            }
        }
    }
```

- [ ] **Step 2: Fill in `didFinishNavigation(for:)` — mark slot as ready-for-warm-assignment**

Replace the empty helper with:

```swift
    fileprivate func didFinishNavigation(for webView: WKWebView) {
        // HTML loaded. Slot stays in .empty until a `shift` assigns a lecture.
        // No state change here — the shift call drives warm-up.
        _ = slots.first(where: { $0.webView === webView })
    }
```

(The `didFinishNavigation` hook is a no-op on first pass — slots sit in `.empty` until `shift` assigns them. It becomes load-bearing in Task 2.9 for jetsam recovery.)

- [ ] **Step 3: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build.

### Task 2.4: Slot state machine — JS bridge event handling

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Implement `didReceiveMessage` + warm-up state transitions**

Replace the empty helper with:

```swift
    fileprivate func didReceiveMessage(_ body: String, from webView: WKWebView) {
        guard let slot = slots.first(where: { $0.webView === webView }) else { return }

        if body == "apiReady" || body == "playerReady" {
            // Player object ready. If a warm-up is pending (slot.state == .loading
            // but no JS fired yet), the JS-side pendingWarm path has already
            // queued it — nothing to do here.
            return
        }

        if body.hasPrefix("state:"), let s = Int(body.dropFirst(6)) {
            handleYouTubeState(s, slot: slot)
        } else if body.hasPrefix("error:") {
            slot.warmUpDeadline?.cancel()
            slot.state = .failed(consecutiveFailures: failureCount(slot) + 1)
        }
    }

    private func handleYouTubeState(_ state: Int, slot: Slot) {
        switch (state, slot.state) {
        case (1, .loading):
            // PLAYING (muted, offscreen). Force the pause+seek handoff.
            slot.state = .warming
            slot.webView.evaluateJavaScript("pauseAtZero()", completionHandler: nil)
        case (2, .warming):
            // PAUSED at t=0: first frame decoded. Slot is warm.
            slot.warmUpDeadline?.cancel()
            slot.state = .warm
        case (1, .warm), (1, .playing):
            // Promoted to playing (re-entering play after a pause).
            slot.state = .playing
        case (2, .playing):
            // External pause (user tapped).
            slot.state = .warm
        case (0, _):
            // Ended — notify anyone listening. Stays in current state.
            break
        default:
            break
        }
    }

    private func failureCount(_ slot: Slot) -> Int {
        if case .failed(let n) = slot.state { return n }
        return 0
    }
```

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add MITReels/Services/ReelPlayerPool.swift
git commit -m "feat(players): implement ReelPlayerPool warm-up state transitions"
```

### Task 2.5: `shift(toCenterIndex:)` — rotate slot assignments

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Implement `shift`**

Replace the empty `shift` with:

```swift
    /// Rotate slot assignments when the visible center changes.
    ///
    /// Given a new center index, compute each slot's lecture id from
    /// `lectures[index + relativePosition]`. Slots whose lecture id is
    /// unchanged (the overlap band) stay put. Slots whose lecture id
    /// changed get a new warm-up. Slots that now point outside the
    /// lecture array become `.empty`.
    func shift(toCenterIndex index: Int, in lectures: [Lecture]) {
        guard !slots.isEmpty else { return }

        // Reassign each slot's relative-position → lecture mapping.
        for slot in slots {
            let targetIndex = index + slot.relativePosition
            let targetId: String? = (targetIndex >= 0 && targetIndex < lectures.count)
                ? lectures[targetIndex].youtubeId
                : nil

            if slot.lectureId == targetId { continue }  // no change

            slot.lectureId = targetId
            slot.warmUpDeadline?.cancel()

            if let id = targetId {
                slot.state = .loading
                scheduleWarmUpDeadline(for: slot)
                let js = "startWarm('\(id)')"
                slot.webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                slot.state = .empty
                slot.webView.evaluateJavaScript("clearSlot()", completionHandler: nil)
            }
        }

        // Promote the center slot to playing if it's warm.
        if let center = slots.first(where: { $0.relativePosition == 0 }),
           case .warm = center.state {
            promote(center)
        }

        // Pause non-center slots that are currently playing (e.g. after
        // backward scroll where the new center was previously warm).
        for slot in slots where slot.relativePosition != 0 {
            if case .playing = slot.state {
                demote(slot)
            }
        }
    }

    private func scheduleWarmUpDeadline(for slot: Slot) {
        slot.warmUpDeadline = Task { @MainActor [weak slot] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let slot else { return }
            if case .loading = slot.state { slot.state = .failed(consecutiveFailures: 1) }
            if case .warming = slot.state { slot.state = .failed(consecutiveFailures: 1) }
        }
    }

    private func promote(_ slot: Slot) {
        slot.state = .playing
        slot.webView.alpha = 1
        slot.webView.evaluateJavaScript("promoteToPlaying()", completionHandler: nil)
    }

    private func demote(_ slot: Slot) {
        slot.state = .warm
        slot.webView.alpha = 0
        slot.webView.evaluateJavaScript("demoteToWarm()", completionHandler: nil)
    }
```

Note: the "slot keyed by relative position from center" semantics mean we do NOT rotate the slot array — slots stay in the same array positions, but their `lectureId` assignments shuffle when the center changes. Rolled-off slots (those whose new target is now out of bounds OR whose lecture changed) re-run warm-up for the new id.

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build. If you see an "unused variable `targetIndex`" warning or similar, double-check the body.

### Task 2.6: `playerView(forRelativePosition:)` — cell-facing accessor

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Implement**

Replace the empty placeholder with:

```swift
    /// The WebView for the slot at the given relative position, or nil if
    /// the slot is outside ±capacityPerSide.
    func playerView(forRelativePosition rp: Int) -> UIView? {
        slots.first(where: { $0.relativePosition == rp })?.webView
    }

    /// Convenience: what lecture id is the slot currently assigned to?
    func lectureId(forRelativePosition rp: Int) -> String? {
        slots.first(where: { $0.relativePosition == rp })?.lectureId
    }

    /// Convenience: is a given slot's warm-up complete?
    func isReady(forRelativePosition rp: Int) -> Bool {
        guard let slot = slots.first(where: { $0.relativePosition == rp }) else { return false }
        switch slot.state {
        case .warm, .playing: return true
        default: return false
        }
    }
```

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 2.7: `playCenter` / `pauseAllButCenter`

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Implement**

Replace the two empty placeholders with:

```swift
    /// Promote the center slot to playing (if it's warm).
    func playCenter() {
        if let center = slots.first(where: { $0.relativePosition == 0 }),
           case .warm = center.state {
            promote(center)
        }
    }

    /// Pause all non-center slots. Used on drag-begin — we don't want audio
    /// from a rolled-off center continuing while the user is mid-drag.
    /// Actually during a drag, the center is still the one at position 0
    /// because shift hasn't fired yet. So this only affects slots that were
    /// somehow left in .playing state outside the center (shouldn't happen
    /// but defensive).
    func pauseAllButCenter() {
        for slot in slots where slot.relativePosition != 0 {
            if case .playing = slot.state { demote(slot) }
        }
    }
```

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 2.8: `handleMemoryPressure` — shrink to ±1

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Implement**

Replace the empty placeholder with:

```swift
    /// Called when the app receives `didReceiveMemoryWarningNotification`.
    /// Recycles the -2 and +2 slots (clears their iframes). The next `shift`
    /// call re-warms them automatically once memory pressure subsides.
    func handleMemoryPressure() {
        for slot in slots where abs(slot.relativePosition) == capacityPerSide {
            slot.warmUpDeadline?.cancel()
            slot.state = .recycled
            slot.lectureId = nil
            slot.webView.evaluateJavaScript("clearSlot()", completionHandler: nil)
        }
    }
```

Design note: we do NOT unload the HTML itself (`loadHTMLString("")`) on memory pressure — that would require re-downloading `yt-player.js` (~200KB) on recovery. Instead, `clearSlot()` calls `player.stopVideo()` which releases the decoder state while keeping the player shell alive. This is much cheaper to recover from.

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 2.9: Jetsam recovery — `webContentProcessDidTerminate`

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Implement the handler**

Replace the empty `webContentProcessDidTerminate` placeholder with:

```swift
    /// Called when iOS kills a WebContent process under memory pressure
    /// (jetsam). The WebView's page is gone; calling any JS on it will
    /// silently fail. Reload the player HTML and mark the slot `.recycled`
    /// so the next `shift` re-warms it.
    fileprivate func webContentProcessDidTerminate(for webView: WKWebView) {
        guard let slot = slots.first(where: { $0.webView === webView }) else { return }
        slot.warmUpDeadline?.cancel()
        slot.state = .recycled
        slot.lectureId = nil
        slot.webView.alpha = 0
        slot.webView.loadHTMLString(Self.playerHTML, baseURL: URL(string: "https://mitreels.app"))
    }
```

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 2.10: Unit tests for `ReelPlayerPool`

**Files:**
- Create: `MITReelsTests/Services/ReelPlayerPoolTests.swift`

- [ ] **Step 1: Write failing tests (first pass — assignment logic)**

Create `MITReelsTests/Services/ReelPlayerPoolTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import MITReels

/// Unit tests for ReelPlayerPool. These cover the slot-assignment
/// state machine logic — NOT the real WebView warm-up, which requires
/// a live WKWebView and would make tests flaky. WebView interactions
/// are verified manually via the SlidingLoopPreview harness in Phase 6.
@MainActor
struct ReelPlayerPoolTests {

    private func makeLectures(_ count: Int) -> [Lecture] {
        // Lecture is a SwiftData @Model class; its init signature is
        // (title:youtubeId:courseNumber:courseName:department:[defaults]).
        // No ModelContainer needed for pure instance creation — we only
        // persist when we call `context.insert`, which these tests don't.
        (0..<count).map { i in
            Lecture(
                title: "Lecture \(i)",
                youtubeId: String(format: "vid%08d", i),
                courseNumber: "0.0",
                courseName: "Test",
                department: ""
            )
        }
    }

    @Test func shiftAssignsSlotsAroundCenter() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)

        pool.shift(toCenterIndex: 10, in: lectures)

        #expect(pool.lectureId(forRelativePosition: -2) == "vid00000008")
        #expect(pool.lectureId(forRelativePosition: -1) == "vid00000009")
        #expect(pool.lectureId(forRelativePosition:  0) == "vid00000010")
        #expect(pool.lectureId(forRelativePosition:  1) == "vid00000011")
        #expect(pool.lectureId(forRelativePosition:  2) == "vid00000012")
    }

    @Test func shiftForwardByOneRecyclesFarBack() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)

        pool.shift(toCenterIndex: 10, in: lectures)
        pool.shift(toCenterIndex: 11, in: lectures)

        // Slot at relativePosition -2 now holds vid9, up from vid8.
        #expect(pool.lectureId(forRelativePosition: -2) == "vid00000009")
        // Slot at +2 now holds vid13.
        #expect(pool.lectureId(forRelativePosition:  2) == "vid00000013")
    }

    @Test func shiftBackwardReusesCachedAssignments() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)

        pool.shift(toCenterIndex: 10, in: lectures)
        pool.shift(toCenterIndex: 11, in: lectures)
        pool.shift(toCenterIndex: 10, in: lectures)  // backward

        #expect(pool.lectureId(forRelativePosition: 0) == "vid00000010")
    }

    @Test func shiftAtBoundaryLeavesSlotsEmpty() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(5)

        pool.shift(toCenterIndex: 0, in: lectures)
        // relativePosition -2 and -1 have no valid lecture (negative index)
        #expect(pool.lectureId(forRelativePosition: -2) == nil)
        #expect(pool.lectureId(forRelativePosition: -1) == nil)
        #expect(pool.lectureId(forRelativePosition:  0) == "vid00000000")
    }

    @Test func handleMemoryPressureRecyclesFarSlots() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)
        pool.shift(toCenterIndex: 10, in: lectures)

        pool.handleMemoryPressure()

        // Far slots cleared; near slots retained.
        #expect(pool.lectureId(forRelativePosition: -2) == nil)
        #expect(pool.lectureId(forRelativePosition:  2) == nil)
        #expect(pool.lectureId(forRelativePosition: -1) == "vid00000009")
        #expect(pool.lectureId(forRelativePosition:  1) == "vid00000011")
    }

    @Test func playerViewReturnsNilForOutOfRangePosition() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        #expect(pool.playerView(forRelativePosition: 3) == nil)
        #expect(pool.playerView(forRelativePosition: -3) == nil)
    }

    @Test func playerViewReturnsSameInstanceAcrossCalls() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let a = pool.playerView(forRelativePosition: 0)
        let b = pool.playerView(forRelativePosition: 0)
        #expect(a === b)
    }
}
```

- [ ] **Step 2: Add the test file to the test target in Xcode**

Open Xcode, right-click `MITReelsTests` → Add Files → `ReelPlayerPoolTests.swift` → check `MITReelsTests` target.

- [ ] **Step 3: Run the pool tests**

```bash
flowdeck test -S "iPhone 16 Pro" -f "ReelPlayerPoolTests"
```

Expected: all 7 tests pass. If `shiftAssignsSlotsAroundCenter` fails with nil values at ±2, double-check the `shift` method's index math in Task 2.5.

- [ ] **Step 4: Commit Phase 2**

```bash
git add MITReels/Services/ReelPlayerPool.swift \
        MITReelsTests/Services/ReelPlayerPoolTests.swift \
        MITReels.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(players): introduce ReelPlayerPool with 5 warm slots

Persistent pool of 5 WKWebViews keyed by relative position from center
(-2...+2), sharing one WKProcessPool and WKWebsiteDataStore. Warm-up
uses loadVideoById({mute:1}) + pauseVideo + seekTo(0) — the only
sequence that forces YouTube's iframe to actually decode the first
frame. cueVideoById explicitly does not decode per the API docs.

Includes jetsam recovery via webContentProcessDidTerminate and
memory-pressure shrink to ±1. Not yet integrated with any view; unit
tests cover slot assignment, rotation, and pressure handling.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Extend Thumbnail Prefetch to ±25 (S)

**Rationale:** Small but load-bearing: with the pool in place, the thumbnail layer is the "2 ms floor" shown instantly while the pool warms. A ±25 window means even aggressive backward scrolls hit a cached thumbnail.

### Task 3.1: Bump `ThumbnailPrefetcher.countLimit` and add `prefetchIdsAround`

**Files:**
- Modify: `MITReels/Services/ThumbnailPrefetcher.swift`
- Test: `MITReelsTests/Services/ThumbnailPrefetcherTests.swift` (create if absent)

- [ ] **Step 1: Write the failing test for the new method**

Create `MITReelsTests/Services/ThumbnailPrefetcherTests.swift` (if a test file already exists, append):

```swift
import Testing
import Foundation
@testable import MITReels

@MainActor
struct ThumbnailPrefetcherTests {

    @Test func countLimitIs64() {
        #expect(ThumbnailPrefetcher.shared.cacheCountLimit == 64)
    }

    @Test func prefetchIdsAroundReturnsWindowClampedToBounds() {
        let ids = (0..<50).map { "id\($0)" }
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 10, window: 25, in: ids)
        // Should span 10-25 ... 10+25 clamped to [0, 49], so indices 0..35.
        #expect(window.first == "id0")
        #expect(window.last == "id35")
        #expect(window.count == 36)
    }

    @Test func prefetchIdsAroundHandlesEmptyArray() {
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 0, window: 25, in: [])
        #expect(window.isEmpty)
    }

    @Test func prefetchIdsAroundHandlesCenterPastEnd() {
        let ids = ["a", "b", "c"]
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 100, window: 25, in: ids)
        #expect(window.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests — verify they FAIL**

```bash
flowdeck test -S "iPhone 16 Pro" -f "ThumbnailPrefetcherTests"
```

Expected: build error on `cacheCountLimit` and `idsAround` — neither exists yet.

- [ ] **Step 3: Read `ThumbnailPrefetcher.swift` to find the right insertion points**

```bash
```

Use the Read tool to open `MITReels/Services/ThumbnailPrefetcher.swift`. Locate:
- Line where `NSCache.countLimit = 30` is set
- The top-level `static let shared` declaration

- [ ] **Step 4: Bump `countLimit` to 64 and add the `idsAround` helper**

In `ThumbnailPrefetcher.swift`:

1. Change `cache.countLimit = 30` → `cache.countLimit = 64`
2. Expose `cacheCountLimit` as a read-only accessor: `var cacheCountLimit: Int { cache.countLimit }`
3. Add a static helper:

```swift
    /// Compute the window of ids to prefetch around a center index.
    /// Clamps to [0, ids.count). Used by DiscoverView to drive the
    /// ±25 prefetch on visibleIndex change.
    static func idsAround(centerIndex: Int, window: Int, in ids: [String]) -> [String] {
        guard !ids.isEmpty, centerIndex < ids.count else { return [] }
        let lower = max(0, centerIndex - window)
        let upper = min(ids.count - 1, centerIndex + window)
        guard lower <= upper else { return [] }
        return Array(ids[lower...upper])
    }
```

- [ ] **Step 5: Run the tests — verify they pass**

```bash
flowdeck test -S "iPhone 16 Pro" -f "ThumbnailPrefetcherTests"
```

Expected: 4 tests pass.

### Task 3.2: Wire DiscoverView to the ±25 window

**Files:**
- Modify: `MITReels/Views/DiscoverView.swift:128-136`

- [ ] **Step 1: Replace the `count: 6` prefetch with `idsAround`**

In `DiscoverView.swift`, locate the block around line 128:

```swift
            // Prefetch thumbnails from engine's ahead-window
            Task {
                let ids = await feedEngine.prefetchIds(count: 6)
                for id in ids {
                    if ThumbnailPrefetcher.shared.cachedImage(for: id) == nil {
                        _ = await ThumbnailPrefetcher.shared.fetchAndCache(videoId: id)
                    }
                }
            }
```

Replace with:

```swift
            // Prefetch thumbnails in a ±25 window around the current visible
            // index. Backward scrolls hit a cached thumbnail too — widens from
            // the old forward-only ±6 to match the ReelPlayerPool warm window.
            Task {
                let currentIndex = displayLectures.firstIndex { $0.youtubeId == new } ?? 0
                let ids = ThumbnailPrefetcher.idsAround(
                    centerIndex: currentIndex,
                    window: 25,
                    in: displayLectures.map(\.youtubeId)
                )
                for id in ids {
                    if ThumbnailPrefetcher.shared.cachedImage(for: id) == nil {
                        _ = await ThumbnailPrefetcher.shared.fetchAndCache(videoId: id)
                    }
                }
            }
```

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build.

- [ ] **Step 3: Commit Phase 3**

```bash
git add MITReels/Services/ThumbnailPrefetcher.swift \
        MITReels/Views/DiscoverView.swift \
        MITReelsTests/Services/ThumbnailPrefetcherTests.swift \
        MITReels.xcodeproj/project.pbxproj
git commit -m "feat(discover): widen thumbnail prefetch window to ±25"
```

---

## Phase 4: ReelView Ownership Transfer (M)

**Rationale:** The invasive phase but scoped tightly: `ReelView`'s layout stays identical. The work is moving WebView ownership from `YouTubePlayerView.makeUIView` (which checks out of `WKWebViewPool`) to a thin `PoolBorrowedPlayerView` that borrows a pool-owned `UIView` via `pool.playerView(forRelativePosition:)`.

Migration bridge: the new representable coexists with the old `YouTubePlayerView` during Phase 4. Phase 5 flips the switch by deleting the old component and the `WKWebViewPool`.

### Task 4.1: Create `PoolBorrowedPlayerView` — a minimal `UIViewRepresentable`

**Files:**
- Create: `MITReels/Components/PoolBorrowedPlayerView.swift`

- [ ] **Step 1: Write the representable**

```swift
import SwiftUI
import UIKit

/// Thin SwiftUI wrapper that borrows a pool-owned WebView based on the
/// cell's relative position from the current visible center. The pool
/// owns the WebView; this representable just re-parents it.
///
/// Keying: the cell passes its `relativePosition` computed from
/// `visibleIndex - cellIndex`. The pool returns the WebView for that
/// slot. When the cell recycles (scrolls out of the ±2 window), the
/// pool returns nil and the representable presents an empty container.
struct PoolBorrowedPlayerView: UIViewRepresentable {
    let relativePosition: Int

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isOpaque = false
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // Remove any previously attached WebView (from a prior shift).
        for sub in container.subviews { sub.removeFromSuperview() }

        guard let slot = ReelPlayerPool.shared.playerView(forRelativePosition: relativePosition) else {
            return
        }

        // Re-parent the pool's WebView into our container.
        slot.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(slot)
        NSLayoutConstraint.activate([
            slot.topAnchor.constraint(equalTo: container.topAnchor),
            slot.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            slot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            slot.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
```

- [ ] **Step 2: Add to Xcode project target `MITReels`**

- [ ] **Step 3: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 4.2: Migrate `ReelView` to use `PoolBorrowedPlayerView`

**Files:**
- Modify: `MITReels/Views/ReelView.swift`

- [ ] **Step 1: Read `ReelView.swift` to identify the `videoPlayer` body and the `@State` vars to remove**

Open `MITReels/Views/ReelView.swift`. Note lines 34-46 (video `@State` vars) and lines 261-316 (the `videoPlayer` computed var).

- [ ] **Step 2: Add a `relativePosition: Int` parameter to `ReelView`**

In `ReelView.swift`, replace the struct property list (lines 12-32) by inserting:

```swift
    /// The cell's position relative to the current visible center,
    /// e.g. -1 for "one above center," +2 for "two below center."
    /// Drives which pool slot this cell borrows.
    var relativePosition: Int = 0
```

Also add it to the init. The old `isNearby` parameter becomes unused — leave it for Phase 4 (Phase 5 removes it).

- [ ] **Step 3: Replace the `videoPlayer` computed var's YouTubePlayerView with `PoolBorrowedPlayerView`**

In `ReelView.swift`, find the block (around line 272):

```swift
                if isVisible || isNearby {
                    YouTubePlayerView(
                        videoId: lecture.youtubeId,
                        autoplay: isVisible && autoplayEnabled,
                        // ... bindings ...
                    )
                    .compositingGroup()
                    .opacity(isVisible && showVideoLayer ? 1 : 0)
                    // ... onChange modifiers ...
                }
```

Replace with:

```swift
                PoolBorrowedPlayerView(relativePosition: relativePosition)
                    .compositingGroup()
```

The pool handles alpha internally — we don't need SwiftUI's `.opacity(...)` gate. The cell is always attached when inside the pool window; the pool drives visibility via the WebView's `alpha` property.

- [ ] **Step 4: Remove the now-unused `@State` vars that only existed for `YouTubePlayerView` bindings**

Delete these `@State` declarations from `ReelView.swift`:

```swift
    @State private var isVideoLoading = true
    @State private var hasVideoError = false
    @State private var showVideoLayer = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var seekTarget: Double? = nil
```

Also delete any `onChange(of: isPlaying)` / `onChange(of: isVideoLoading)` modifiers in the `videoPlayer` body that reference these.

Note: the `TimelineScrubber` at line 332 depends on `currentTime` and `duration`. For Phase 4, replace the TimelineScrubber block with a comment `// TODO Phase 5: timeline scrubber reads from ReelPlayerPool slot state`. The scrubber is restored in Phase 5 once the pool exposes a time-publisher.

- [ ] **Step 5: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build. Any error about missing `currentTime`/`duration` means you missed a reference — search the file for `currentTime` and `duration`.

- [ ] **Step 6: Commit Phase 4**

```bash
git add MITReels/Components/PoolBorrowedPlayerView.swift \
        MITReels/Views/ReelView.swift \
        MITReels.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
refactor(reel): transfer player ownership to ReelPlayerPool

ReelView now borrows a pool-owned WebView via PoolBorrowedPlayerView
instead of creating its own via YouTubePlayerView → WKWebViewPool
checkout. Video @State vars removed — slot state owns them now.
Timeline scrubber temporarily disabled pending Phase 5 slot-state
publisher wiring.

Layout is unchanged. Only ownership moved.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5: DiscoverView Wire-Up + WKWebViewPool Retirement (S)

**Rationale:** The cutover. After this phase, the old pool is gone and the new pool drives all video playback. Also restores the timeline scrubber by publishing slot time/duration via a small bridge.

### Task 5.1: Expose slot time/duration publisher from `ReelPlayerPool`

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: Add an `@Published` field on the Slot class for time/duration**

This requires promoting `Slot` to `ObservableObject`. Change the Slot declaration:

```swift
    final class Slot: ObservableObject {
        let webView: WKWebView
        var relativePosition: Int
        @Published var state: SlotState = .empty
        var lectureId: String?
        @Published var currentTime: Double = 0
        @Published var duration: Double = 0
        var warmUpDeadline: Task<Void, Never>?

        init(webView: WKWebView, relativePosition: Int) {
            self.webView = webView
            self.relativePosition = relativePosition
        }
    }
```

- [ ] **Step 2: Extend the JS bridge to forward `time:` events**

In `ReelPlayerPool.playerHTML`, add inside the player's `onStateChange`:

```js
                'onStateChange': function(e) {
                    msg('state:' + e.data);
                    if (e.data === 1) startTimePolling();
                    else if (e.data === 0 || e.data === 2) stopTimePolling();
                },
```

Add these JS helpers alongside `promoteToPlaying`:

```js
    var timePoller = null;
    function startTimePolling() {
        stopTimePolling();
        timePoller = setInterval(function() {
            if (player && player.getCurrentTime) {
                msg('time:' + (player.getCurrentTime()||0).toFixed(1) + ':' + (player.getDuration()||0).toFixed(1));
            }
        }, 500);
    }
    function stopTimePolling() {
        if (timePoller) { clearInterval(timePoller); timePoller = null; }
    }
```

- [ ] **Step 3: Handle `time:` events in `didReceiveMessage`**

Extend `didReceiveMessage`:

```swift
        if body.hasPrefix("time:") {
            let parts = body.dropFirst(5).split(separator: ":")
            if parts.count == 2, let t = Double(parts[0]), let d = Double(parts[1]) {
                slot.currentTime = t
                slot.duration = d
            }
            return
        }
```

- [ ] **Step 4: Expose a slot-lookup accessor for SwiftUI consumers**

Add:

```swift
    /// Observable slot for a relative position. SwiftUI views can
    /// `@ObservedObject` this to get state/time updates.
    func slot(forRelativePosition rp: Int) -> Slot? {
        slots.first(where: { $0.relativePosition == rp })
    }
```

- [ ] **Step 5: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 5.2: Restore timeline scrubber in `ReelView` via slot observation

**Files:**
- Modify: `MITReels/Views/ReelView.swift`

- [ ] **Step 1: Add `@ObservedObject` for the slot**

In `ReelView.swift`, add near the other state:

```swift
    @ObservedObject private var slot: ReelPlayerPool.Slot
```

Update the init to resolve the slot from the pool:

```swift
    init(
        lecture: Lecture,
        lectureIndex: Int? = nil,
        isVisible: Bool = false,
        relativePosition: Int = 0,
        autoplayEnabled: Bool = true,
        captionsEnabled: Bool = true,
        onViewCourse: ((Lecture) -> Void)? = nil
    ) {
        // ... existing init body ...
        self.relativePosition = relativePosition
        // Safe fallback: if the pool has no slot for this position (cell
        // outside ±2 window), synthesize a throwaway observable slot so
        // the @ObservedObject wrapper has something to hold.
        self._slot = ObservedObject(
            wrappedValue: ReelPlayerPool.shared.slot(forRelativePosition: relativePosition)
                ?? ReelPlayerPool.Slot.empty
        )
    }
```

Add a static `empty` slot on `ReelPlayerPool.Slot`:

```swift
        static let empty = Slot(webView: WKWebView(), relativePosition: 999)
```

(The 999 position means no real slot will match; the @ObservedObject is just a placeholder.)

- [ ] **Step 2: Restore the `TimelineScrubber` block reading from `slot.currentTime` / `slot.duration`**

In the `videoPlayer` body, replace the `// TODO Phase 5` comment with:

```swift
            if isVisible && slot.duration > 0 {
                TimelineScrubber(currentTime: Binding(
                    get: { slot.currentTime },
                    set: { _ in /* read-only display; scrubbing handled via pool.seek */ }
                ), duration: slot.duration) { time in
                    ReelPlayerPool.shared.seek(forRelativePosition: relativePosition, to: time)
                }
            }
```

- [ ] **Step 3: Add `seek(forRelativePosition:to:)` to `ReelPlayerPool`**

In `ReelPlayerPool.swift`:

```swift
    func seek(forRelativePosition rp: Int, to seconds: Double) {
        guard let slot = slots.first(where: { $0.relativePosition == rp }) else { return }
        slot.webView.evaluateJavaScript("seekTo(\(seconds))", completionHandler: nil)
    }
```

- [ ] **Step 4: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

### Task 5.3: Wire `DiscoverView` to call `pool.shift` on visibleIndex changes

**Files:**
- Modify: `MITReels/Views/DiscoverView.swift`

- [ ] **Step 1: Call `ReelPlayerPool.shared.shift(toCenterIndex:in:)` in the `visibleId` onChange handler**

In `DiscoverView.swift`, add inside the `.onChange(of: visibleId)` block (around line 128, near the prefetch Task):

```swift
            // Drive the zero-wait player pool
            let currentIndex = displayLectures.firstIndex { $0.youtubeId == new } ?? 0
            ReelPlayerPool.shared.shift(toCenterIndex: currentIndex, in: displayLectures)
```

- [ ] **Step 2: Delete the `nextId` deferred block**

Remove these lines from `DiscoverView.swift` (around 138-142):

```swift
            // Defer WebView preload updates to after scroll animation settles
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                nextId = displayLectures.nextId(after: new)
            }
```

And remove the `nextId` `@State` declaration near the top of `DiscoverView`.

- [ ] **Step 3: Update the `SlidingLoop` cell closure to pass `relativePosition`**

In the `feedContent` body at `DiscoverView.swift:224`, change:

```swift
            SlidingLoop(items: displayLectures, visibleIndex: $visibleIndex) { lecture, isVisible in
                ReelView(
                    lecture: lecture,
                    isVisible: isVisible,
                    isNearby: lecture.youtubeId == nextId,
                    autoplayEnabled: autoplayEnabled,
                    // ...
                )
```

To:

```swift
            SlidingLoop(items: displayLectures, visibleIndex: $visibleIndex) { lecture, isVisible in
                let cellIndex = displayLectures.firstIndex { $0.youtubeId == lecture.youtubeId } ?? 0
                let rel = cellIndex - visibleIndex
                ReelView(
                    lecture: lecture,
                    isVisible: isVisible,
                    relativePosition: rel,
                    autoplayEnabled: autoplayEnabled,
                    // ...
                )
```

- [ ] **Step 4: Replace the old memory-warning wiring**

Change `DiscoverView.swift:187-190` from:

```swift
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            WKWebViewPool.shared.handleMemoryWarning()
            ThumbnailPrefetcher.shared.handleMemoryWarning()
        }
```

To:

```swift
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            ReelPlayerPool.shared.handleMemoryPressure()
            ThumbnailPrefetcher.shared.handleMemoryWarning()
        }
```

- [ ] **Step 5: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: the codepath compiles but `YouTubePlayerView` and `WKWebViewPool` are still referenced by… now nobody. They'll be deleted in Task 5.4.

### Task 5.4: Delete `WKWebViewPool` and `YouTubePlayerView`

**Files:**
- Delete: `MITReels/Services/WKWebViewPool.swift`
- Delete: `MITReels/Components/YouTubePlayerView.swift`
- Modify: `MITReels/MITReelsApp.swift` — replace warm-up call

- [ ] **Step 1: Replace `WKWebViewPool.shared.warmUp()` with the new pool's warm-up**

In `MITReels/MITReelsApp.swift`, find the line calling `WKWebViewPool.shared.warmUp()` (likely in `.onAppear` or an `init()` body) and replace with:

```swift
ReelPlayerPool.shared.warmUp()
```

- [ ] **Step 2: Delete the two files**

```bash
rm MITReels/Services/WKWebViewPool.swift
rm MITReels/Components/YouTubePlayerView.swift
```

- [ ] **Step 3: Remove the files from the Xcode project**

Open Xcode, find `WKWebViewPool.swift` and `YouTubePlayerView.swift` in the Project Navigator, right-click → Delete → "Remove Reference" (the files are already gone from disk).

- [ ] **Step 4: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: clean build. If any residual reference fails, it's either in `YouTubePlayerViewTests.swift` (delete that test file too) or in the preview blocks. Clean them up.

- [ ] **Step 5: Run the full test suite**

```bash
flowdeck test -S "iPhone 16 Pro"
```

Expected: all tests pass (except `YouTubePlayerViewTests.swift` which was deleted).

- [ ] **Step 6: Manual smoke test on simulator**

```bash
flowdeck run -S "iPhone 16 Pro"
```

In the running app: scroll the discover feed. Expected:
- First reel loads (may have a brief thumbnail flash on app launch — pool warm-up happens in parallel)
- Swipe 2, 3, 4, 5 in rapid succession. No thumbnail flash after swipe #1.
- Swipe backward. Previously-watched reel is instantly ready.

If you see flashes, the pool's warm-up is slower than expected. Note this for Phase 6 tuning but don't block the commit.

- [ ] **Step 7: Commit Phase 5**

```bash
git add MITReels/Views/DiscoverView.swift \
        MITReels/Services/ReelPlayerPool.swift \
        MITReels/Views/ReelView.swift \
        MITReels/MITReelsApp.swift \
        MITReels.xcodeproj/project.pbxproj
git rm MITReels/Services/WKWebViewPool.swift \
       MITReels/Components/YouTubePlayerView.swift \
       MITReelsTests/YouTubePlayerViewTests.swift 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(discover): adopt ReelPlayerPool, retire WKWebViewPool

DiscoverView now drives ReelPlayerPool.shift on visibleIndex changes,
and cells borrow pool-owned WebViews via PoolBorrowedPlayerView.
The old 3-slot checkout/checkin WKWebViewPool and its YouTubePlayerView
consumer are deleted — their semantics (stop video on checkin) are
incompatible with zero-wait playback. Timeline scrubber restored via
slot ObservableObject publishing currentTime/duration.

The nextId deferred-sleep path in DiscoverView is also removed; the
pool's ±2 warm window makes it redundant.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6: Maestro + Instruments Validation + Tuning (S)

**Rationale:** The pool is wired and the codepath is clean, but we haven't proven the performance claims. Phase 6 is measurement + tuning — not new features. Maestro gives us a scriptable, reproducible 5-swipe acceptance test so we don't rely on manual doom-scrolling (which is hand-variable and not repeatable between tuning iterations). Instruments gives us the memory / first-frame latency / Core Animation numbers that Maestro can't see.

### Task 6.0: Maestro flow for the rapid-interaction acceptance test

**Files:**
- Create: `maestro/flows/rapid-swipe-acceptance.yaml`

- [ ] **Step 1: Write the Maestro flow**

Create `maestro/flows/rapid-swipe-acceptance.yaml`:

```yaml
# Acceptance test: 5 consecutive swipes at ~150ms interval with no visible
# thumbnail flash after swipe #1. Records a video for frame-by-frame review.
#
# Run: maestro test maestro/flows/rapid-swipe-acceptance.yaml --format=junit
#      (pair with: xcrun simctl io booted recordVideo out.mov & )
appId: com.mitreels.MITReels
---
- launchApp:
    clearState: false
- waitForAnimationToEnd:
    timeout: 5000
# Let the first reel finish warming up before starting the acceptance run.
- waitForAnimationToEnd
- assertVisible:
    id: ".*"
    timeout: 3000
# 5 rapid upward swipes, ~150ms between them.
- swipe:
    direction: UP
    duration: 200
- swipe:
    direction: UP
    duration: 200
- swipe:
    direction: UP
    duration: 200
- swipe:
    direction: UP
    duration: 200
- swipe:
    direction: UP
    duration: 200
# Settle at the final reel — if the player is thumbnail-only here, the
# pool's furthest warm-up did not complete in time and the acceptance
# test should be considered failing (manual inspection of the recorded
# video is the authoritative signal).
- waitForAnimationToEnd:
    timeout: 2000
# Backward scroll back to origin — previously-watched reels must be
# instantly ready.
- swipe:
    direction: DOWN
    duration: 200
- swipe:
    direction: DOWN
    duration: 200
- swipe:
    direction: DOWN
    duration: 200
- swipe:
    direction: DOWN
    duration: 200
- swipe:
    direction: DOWN
    duration: 200
```

- [ ] **Step 2: Run the flow while recording simulator video**

```bash
# Terminal 1 — start recording
xcrun simctl io CAC3C00F-E58A-4B0F-B870-C65EB98C1B2C recordVideo /tmp/rapid-swipe.mov &
REC_PID=$!

# Terminal 2 — run the Maestro flow
maestro --udid CAC3C00F-E58A-4B0F-B870-C65EB98C1B2C test maestro/flows/rapid-swipe-acceptance.yaml

# Terminal 1 — stop recording
kill -INT $REC_PID
```

- [ ] **Step 3: Review the recording frame-by-frame**

Open `/tmp/rapid-swipe.mov` in QuickTime. Step through with the right arrow key. Count the number of reels where a thumbnail flash is visible after swipe #1. **Pass criterion: 0 flashes** across reels 2–5 in the forward sequence and all 5 backward reels.

- [ ] **Step 4: Document the pass/fail in the plan's Review section**

### Task 6.1: Instruments Allocations trace — measure peak memory

**Files:**
- None (measurement only)

- [ ] **Step 1: Launch with Allocations instrument on iPhone SE 3rd-gen simulator**

```bash
flowdeck simulator boot -S "iPhone SE (3rd generation)"
flowdeck run -S "iPhone SE (3rd generation)" --instruments Allocations
```

(If `--instruments` isn't supported, launch via Xcode → Product → Profile → Allocations template.)

- [ ] **Step 2: Run the doom-scroll test — 50 reels at ~150 ms/swipe**

In the running app, swipe forward 50 times as fast as you can. Then stop the trace.

- [ ] **Step 3: Record peak resident memory**

Read the "All Heap & Anonymous VM" graph's peak value. **Target: <400 MB**. If higher, note the actual value for the tuning step.

If peak exceeds 400 MB: consider reducing `capacityPerSide` from 2 to 1 (shrinks pool from 5 to 3 slots). Edit `ReelPlayerPool.shared = ReelPlayerPool(capacityPerSide: 1)` and re-measure.

If peak is comfortably under 300 MB: the pool is not the bottleneck — no action.

- [ ] **Step 4: Document the measurement in the plan's review section**

Append to this plan file's "Review" section (bottom):

```markdown
### Phase 6 measurements (YYYY-MM-DD)

- Peak resident on iPhone SE 3rd gen, 50-reel doom-scroll: ___ MB
- capacityPerSide: ___
- Verdict: ✅ under target / ⚠ shrunk pool / ❌ still over
```

### Task 6.2: Instruments Time Profiler — measure first-frame latency

**Files:**
- None

- [ ] **Step 1: Launch with Time Profiler on iPhone 16 Pro**

```bash
flowdeck run -S "iPhone 16 Pro" --instruments TimeProfiler
```

- [ ] **Step 2: Start a trace, then do 5 swipes at ~150 ms interval**

- [ ] **Step 3: Measure the time between `shift(toCenterIndex:)` call and the first frame showing on the new center**

In the Time Profiler detail view, filter for `promoteToPlaying` and measure the wall-clock gap to the next compositor flush showing the new player. **Target: <80 ms**.

If above 80 ms: the `unMute + playVideo` handoff is slower than spec. Try the optional snapshot-poster trick (Task 6.4).

### Task 6.3: Instruments Core Animation — check for jank

**Files:**
- None

- [ ] **Step 1: Launch with Core Animation template**

```bash
flowdeck run -S "iPhone 16 Pro" --instruments CoreAnimation
```

- [ ] **Step 2: Doom-scroll 30 reels, then stop**

- [ ] **Step 3: Check the dropped-frames counter**

**Target: 0 dropped frames during the 30-swipe sequence.** If dropped frames appear, the alpha crossfade or WebView reparenting is blocking the main thread. Likely culprit: `updateUIView` calling `addSubview` during a scroll gesture.

### Task 6.4: Tune — snapshot-poster toggle (optional)

**Files:**
- Modify: `MITReels/Services/ReelPlayerPool.swift`

- [ ] **Step 1: If Task 6.2 showed first-frame latency >80 ms, add the snapshot-poster trick**

Before `promoteToPlaying`, call `WKWebView.takeSnapshot` on the warm slot and display the resulting UIImage as a one-frame overlay during the unmute handoff. Implementation sketch:

```swift
    func playCenter() {
        guard let center = slots.first(where: { $0.relativePosition == 0 }),
              case .warm = center.state else { return }

        let config = WKSnapshotConfiguration()
        center.webView.takeSnapshot(with: config) { [weak self, weak center] image, _ in
            guard let center else { return }
            // Flash the snapshot on the window for 1 frame before unmuting.
            // The flash hides any brief compositor gap during the state 1
            // transition.
            if let img = image {
                center.posterSnapshot = img  // new @Published UIImage? on Slot
            }
            Task { @MainActor [weak self] in
                self?.promote(center)
                try? await Task.sleep(for: .milliseconds(50))
                center.posterSnapshot = nil
            }
        }
    }
```

The `ReelView` `videoPlayer` body then shows the poster image (if non-nil) above the WebView at alpha 1 for the 50 ms handoff window.

- [ ] **Step 2: Re-measure first-frame latency**

Repeat Task 6.2. If still >80 ms, consider accepting the gap and updating the acceptance criterion. The spec said "target <80 ms" — if reality is 120 ms with no visible flash, that's still a ship-quality result.

### Task 6.5: Final commit — Phase 6 parameter tuning

**Files:**
- Modify as needed based on Phase 6 measurements

- [ ] **Step 1: Apply any tuning changes decided in Tasks 6.1–6.4**

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(reel): tune pool parameters from Instruments measurements

See plan Review section for measured values and the corresponding
tuning decisions.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Checklist

After completing the plan, verify against the spec:

- [ ] **Acceptance #1** (5 consecutive swipes, no thumbnail flash after swipe #1) — tested manually in Task 5.4 Step 6 and measured in Task 6.2.
- [ ] **Acceptance #2** (mid-settle grab preserves motion) — tested by `SlidingLoopStateMachineTests.midSettleGrabPreservesSpringVelocity` in Task 1.2.
- [ ] **Acceptance #3** (backward swipe reuses cued slot) — tested by `ReelPlayerPoolTests.shiftBackwardReusesCachedAssignments` in Task 2.10, verified manually in Task 5.4 Step 6.
- [ ] **Acceptance #4** (memory <400 MB) — measured in Task 6.1.
- [ ] **Acceptance #5** (memory warning response) — tested by `ReelPlayerPoolTests.handleMemoryPressureRecyclesFarSlots` in Task 2.10; manual `simulateMemoryWarning` should be done as part of Task 6.1.
- [ ] **Acceptance #6** (existing SlidingLoop physics tests pass) — verified in Task 1.2 Step 5.

## Review

_To be filled in during Phase 6 with measurements and tuning outcomes._
