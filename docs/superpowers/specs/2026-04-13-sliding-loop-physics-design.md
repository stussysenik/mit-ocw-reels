# SlidingLoop — Physics-Driven Reels Scroll

**Date:** 2026-04-13
**Status:** Approved — ready for implementation plan
**Scope:** Scroll physics only. Player reveal latency is a separate follow-up.
**Approach:** UIKit-hosted `UIScrollView` with overridden deceleration, driven by a custom spring on `CADisplayLink`.

## Context

The reels feed in `DiscoverView` currently uses SwiftUI's native paging (`ScrollView` + `LazyVStack` + `.scrollTargetBehavior(.paging)`). It is functionally correct but does not feel snappy. Specific latency sources observed:

- 150ms `Task.sleep` before revealing the player (`ReelView.swift:297–302`)
- Notification-based scroll advance adds a dispatch hop (`DiscoverView.swift:152–158`)
- Player time polled on a 500ms interval
- All transitions use fixed `.easeInOut` curves — no springs anywhere
- Only N+1 preload via `isNearby` flag

The goal is a long-term foundation for Origami-quality interaction: interruptible, physics-driven, velocity-aware scrolling with a critically-damped spring profile (no overshoot, minimum settle time). Feel reference: iA Writer / Notion — precise, decisive, no bounce. Architecture reference: Facebook Origami Studio (POPSpringAnimation, POPDecayAnimation, velocity handoff via patch graph).

The user has committed to a custom-physics implementation (approach "C" in the brainstorming session), accepting the 1–2k LOC investment in exchange for total control of the feel surface.

## Guiding Principle

**"Own the tick, delegate the plumbing."** The `UIScrollView` host keeps accessibility, split-screen behavior, status-bar-tap-to-top, Dynamic Type, keyboard/rotator scroll, and state restoration — all for free. The custom layer owns exactly one thing: what happens to `contentOffset` between the moment a finger lifts and the moment the view comes to rest. That seam is `scrollViewWillEndDragging(_:, withVelocity:, targetContentOffset:)`.

## Non-Goals

- Replacing `UIScrollView` with a bare `UIView` + pan recognizer (rejected — loses accessibility for free).
- Touching `ReelView`, `WKWebViewPool`, `FeedEngine`, or `ThumbnailPrefetcher`.
- Fixing the 150ms player reveal lag or the 500ms time poll (separate pass).
- Recycling cells via `UICollectionView` (deferred to pass 2).
- Adding new features (pinch-on-reel, peek, custom rubber-band). Foundation only.

## Architecture

Four pure-Swift primitives under `MITReels/Physics/`, plus a thin UIKit host under `MITReels/Components/`.

```
MITReels/Physics/
├── Spring.swift              // critically-damped mass-spring-damper integrator
├── VelocityTracker.swift     // rolling-window velocity estimator
├── DisplayLinkDriver.swift   // CADisplayLink wrapper, closure-based tick
├── SnapTarget.swift          // pure function: offset + velocity → target index
MITReels/Components/
├── SlidingLoop.swift         // UIViewRepresentable + coordinator
├── SlidingLoopHostView.swift // UIScrollView subclass + state machine
```

The primitives have zero UIKit imports and are unit-testable in isolation. The host view composes them and implements the scroll delegate state machine.

## Primitives

### Spring

A semi-implicit Euler integrator of a mass-spring-damper ODE. Critical damping is a closed-form constraint, not a tunable dial:

```
friction = 2 · √(mass · tension)        // critical damping
tension  = (2π / response)² · mass      // response in seconds
```

Public API:

```swift
struct Spring {
    var mass: Double = 1
    var response: Double = 0.28          // default: 280ms settle, "decisive"
    var position: Double = 0
    var velocity: Double = 0
    var target: Double = 0

    func stepped(dt: Double) -> Spring
    var isSettled: Bool { abs(velocity) < 0.5 && abs(target - position) < 0.5 }
}
```

**One knob — `response`.** No `damping` argument, no `bounciness`. If we ever want bounce, we promote `damping` from derived to explicit. Until then, fewer knobs means fewer wrong settings.

Default `response` is 0.28s, subject to tuning in Phase C against the preview harness.

### VelocityTracker

Rolling-window velocity estimator. 3-sample window, rejects samples older than 100ms.

```swift
struct VelocityTracker {
    mutating func add(position: Double, at time: CFTimeInterval)
    var velocity: Double { get }  // points/sec
    mutating func reset()
}
```

We compute velocity ourselves rather than using `UIPanGestureRecognizer.velocity(in:)` because the recognizer reports instantaneous velocity at query time — it swings wildly when a user pauses mid-drag. The rolling window produces a stable reading that matches POP's internal decay model.

### DisplayLinkDriver

Closure-based `CADisplayLink` wrapper, ProMotion-aware.

```swift
final class DisplayLinkDriver {
    var onTick: ((CFTimeInterval) -> Void)?
    func start()
    func stop()
    var isRunning: Bool { get }
}
```

- `preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)`
- Attached to `.main` runloop, `.common` mode
- **Runs only while the spring is settling.** Stopped during drag (pan owns offset), stopped when idle. Zero idle CPU.

### SnapTarget

A pure function — the Origami snap algorithm, simplified to a single-step policy:

```swift
enum SnapTarget {
    static func nextIndex(
        from offset: Double,
        velocity: Double,
        pageHeight: Double,
        itemCount: Int,
        flickThreshold: Double = 500
    ) -> Int
}
```

Algorithm:
1. `current = round(offset / pageHeight)`
2. If `|velocity| < flickThreshold` → return `current`
3. Else if `velocity > 0` → return `current + 1`
4. Else → return `current - 1`
5. Clamp to `[0, itemCount - 1]`

**Single-step policy.** No multi-page flicks. People always want the next reel or the previous one; projecting an inertial trajectory across multiple pages is where Apple's default paging feels mushy. This is a deliberate restriction.

## Data Flow

Three-state machine, all transitions explicit:

```
Idle ──touchesBegan──▶ Dragging
Dragging ──willEndDragging──▶ Settling
Settling ──spring.isSettled──▶ Idle
Settling ──touchesBegan (interrupt)──▶ Dragging
```

Every finger-lift goes through `Settling`, even when the user released on a page with zero velocity — in that case the spring's target equals its position and settles on the first tick. There is no direct `Dragging → Idle` edge, which keeps the state machine trivially exhaustive.

### Idle

`DisplayLinkDriver` stopped. `contentOffset` static. `visibleIndex` reflects the settled page. No CPU.

### Dragging

`UIScrollView` owns `contentOffset` natively — pan events update it without any intervention. We sample into `VelocityTracker` on every `scrollViewDidScroll`. The `DisplayLinkDriver` stays stopped; there is nothing for it to do while the user is in direct control.

### Settling

Entered from `scrollViewWillEndDragging`:

```swift
func scrollViewWillEndDragging(
    _ scrollView: UIScrollView,
    withVelocity nativeVelocity: CGPoint,
    targetContentOffset: UnsafeMutablePointer<CGPoint>
) {
    // 1. Kill Apple's deceleration by anchoring its target.
    targetContentOffset.pointee = scrollView.contentOffset

    // 2. Compute snap using OUR velocity (stable, not instantaneous).
    let v = velocityTracker.velocity
    let targetIndex = SnapTarget.nextIndex(
        from: scrollView.contentOffset.y,
        velocity: v,
        pageHeight: scrollView.bounds.height,
        itemCount: itemCount
    )
    let targetY = Double(targetIndex) * Double(scrollView.bounds.height)

    // 3. Hand off to spring with current velocity.
    spring.position = scrollView.contentOffset.y
    spring.velocity = v
    spring.target = targetY

    // 4. Start the tick.
    displayLink.start()
}
```

Each `onTick(dt)`:

```swift
spring = spring.stepped(dt: dt)
scrollView.setContentOffset(CGPoint(x: 0, y: spring.position), animated: false)
if spring.isSettled {
    scrollView.setContentOffset(CGPoint(x: 0, y: spring.target), animated: false)
    displayLink.stop()
    onVisibleIndexChanged?(targetIndex)
}
```

### Interruption

If `scrollViewWillBeginDragging` fires while `displayLink.isRunning`:

```swift
displayLink.stop()
velocityTracker.reset()
// UIScrollView takes over. Spring state is discarded.
// contentOffset is preserved — scrollView is already where spring left it.
```

Both spring and pan write the same `contentOffset`, so transitioning ownership is just "stop writing from one side." That is the velocity handoff — almost anticlimactic because the architecture makes it trivial.

### Why `setContentOffset(_:animated:false)` instead of layer `bounds.origin`?

Because UIScrollView's internal state (delegate callbacks, accessibility, content inset handling) must stay consistent with what it's showing. Writing directly to `layer.bounds.origin` desynchronizes them and breaks VoiceOver page-turn gestures. We own *when* the offset changes; UIScrollView owns everything downstream of that.

## Integration Plan

### Public SwiftUI API

```swift
struct SlidingLoop<Item: Identifiable, Content: View>: UIViewRepresentable {
    let items: [Item]
    @Binding var visibleIndex: Int
    @ViewBuilder let content: (Item, _ isVisible: Bool) -> Content
}
```

Matches SwiftUI idioms so `DiscoverView`'s call site changes minimally.

### UIScrollView configuration

```swift
scrollView.isPagingEnabled = false       // we do our own paging
scrollView.decelerationRate = .fast      // defensive floor; we anchor targetContentOffset
scrollView.bounces = true
scrollView.alwaysBounceVertical = true
scrollView.showsVerticalScrollIndicator = false
scrollView.contentInsetAdjustmentBehavior = .never
```

`decelerationRate = .fast` is defensive: our `scrollViewWillEndDragging` always anchors `targetContentOffset.pointee = scrollView.contentOffset` to kill Apple's deceleration entirely, so this setting should never actually run. We set it anyway so that if a future code path ever forgets to anchor, the fallback is a short runway rather than a long one.

### Cell hosting — no recycling in pass 1

Each item is rendered into a `UIHostingController<Content>` with `containerRelativeFrame(.vertical)` sizing (one per item). Feed buffer is 10–30 items; peak memory ~60 MB is acceptable for v1 and lets us verify the physics in isolation without also debugging cell reuse.

**Recycling is pass 2.** When we migrate to `UICollectionView` + `UIHostingConfiguration`, the primitives move over unchanged. The whole point of the layering is that `Spring`, `VelocityTracker`, `DisplayLinkDriver`, and `SnapTarget` do not know they are being used in a non-recycling host.

### DiscoverView diff (conceptual)

**Before:**
```swift
ScrollView(.vertical) {
    LazyVStack(spacing: 0) {
        ForEach(displayLectures, id: \.youtubeId) { lecture in
            ReelView(lecture: lecture, ...)
                .containerRelativeFrame(.vertical)
                .id(lecture.youtubeId)
        }
    }
    .scrollTargetLayout()
}
.scrollPosition(id: $visibleId)
.scrollTargetBehavior(.paging)
```

**After:**
```swift
SlidingLoop(items: displayLectures, visibleIndex: $visibleIndex) { lecture, isVisible in
    ReelView(lecture: lecture, isVisible: isVisible, isNearby: ..., ...)
}
```

### Deliberate side cleanups (landed with this pass)

1. **Remove the 150ms `Task.sleep`** in `ReelView.swift:297–302`. It was compensating for stutter that no longer exists once the scroll runs on a display-synced spring. If it turns out to still be needed, we address it at the player-reveal layer in pass 2 — not at the scroll layer.
2. **Remove the notification-based advance** in `DiscoverView.swift:152–158`. `SlidingLoop` emits `visibleIndex` changes via direct binding; `FeedEngine.advance()` is called synchronously from that change.
3. **Nothing else touched.** `ReelView`, `WKWebViewPool`, `FeedEngine`, `ThumbnailPrefetcher` stay unchanged. The seam is *just* the scroll container.

## Test Strategy

Swift Testing (not XCTest), per global Swift skills. Tests live under `MITReelsTests/Physics/`.

### SpringTests
- **Overshoot below visual threshold for critical damping.** Init `Spring(response: 0.3, target: 100)` with `position = 0, velocity = 0`, step at 60 Hz for 2 seconds. Assert `max(positions) ≤ 100.5` (under a half-point of overshoot, which is below 1 logical pixel at @2x — discrete-time semi-implicit Euler is not perfectly zero, but is indistinguishable on screen).
- **Monotonic convergence** from zero initial velocity (each step reduces `|target - position|`).
- **Velocity handoff is non-zero.** With `velocity = 2000, target = 0, position = 0`, one 16.67ms step must advance position past 0 — i.e. the spring actually *uses* the handed-off velocity rather than discarding it. Exact distance is integrator-dependent and not pinned.
- **`isSettled` threshold.** Converges to `|velocity| < 0.5 && |target - position| < 0.5`, then reports settled.
- **Settle time budget.** `response = 0.28`, step from 0 to 1000 at 60 Hz — assert `isSettled` within 25 frames (≈ 417ms). Generous upper bound; typical settle lands around 300ms.

### VelocityTrackerTests
- Four samples 16.67ms apart, each 10pts further → velocity ≈ 600 pts/sec.
- Sample older than 100ms evicted correctly.
- `reset()` clears state.

### SnapTargetTests
- Zero velocity at offset 450 with pageHeight 1000 → index 0.
- Zero velocity at offset 551 with pageHeight 1000 → index 1.
- Velocity 501 (above threshold) at offset 200 → index 1.
- Velocity -501 at offset 200 → index 0 (clamped).
- Velocity 10000 at offset 500 → index 1, never +2 (single-step policy).
- Clamping at `itemCount - 1`.

### SlidingLoopStateMachineTests
- Drive host view with fake scroll delegate events (no real UIScrollView).
- Assert state transitions: Idle → Dragging → Settling → Idle.
- Interruption: during Settling, fire `willBeginDragging` → `displayLink.isRunning == false`, spring velocity discarded.

### Manual verification (FlowDeck simulator)
- 20-reel scroll session. Verify: flicks snap to next/prev reliably; slow drags land nearest; mid-settle grab is seamless; no visible overshoot; VoiceOver rotator advances pages; Split View resize re-snaps cleanly.
- No automated snapshot tests in pass 1 — physics changes are feel regressions, not visual regressions. They need a human.

### Coverage target
100% on the four primitives. Integration code covered by the state-machine tests. The SwiftUI wrapper is a pass-through, no tests.

## Rollout

Phase gates — each phase ends with a verifiable checkpoint. No phase starts until the previous verifies.

### Phase A — Primitives in isolation (parallelizable)
- Agent A1: `Spring.swift` + `SpringTests.swift`
- Agent A2: `VelocityTracker.swift` + `DisplayLinkDriver.swift` + `SnapTarget.swift` + tests
- **Gate:** `flowdeck test` passes all physics tests. No app code changed.

### Phase B — Host view in isolation (serial)
- `SlidingLoopHostView.swift` + `SlidingLoop.swift`
- `SlidingLoopStateMachineTests.swift`
- **Gate:** state-machine tests pass. App still on old scroll path.

### Phase C — Preview harness & tuning (serial)
- `SlidingLoopPreview.swift` with 20 colored placeholder cells.
- Run on device via FlowDeck, tune `Spring.response` by feel (expected landing: 0.25–0.32s).
- **Gate:** subjective approval. This is the only subjective gate, deliberately happening in isolation — no `ReelView` noise.

### Phase D — DiscoverView integration (serial)
- Swap `ScrollView` → `SlidingLoop` in `DiscoverView`.
- Delete notification-based advance.
- Delete 150ms reveal sleep in `ReelView`.
- **Gate:** manual simulator verification — scroll, prefetch, FeedEngine advancement, haptics, thumbs-up/down, expand/collapse all working.

### Phase E — Measurement + merge (serial)
- 60-second Instruments Time Profiler session.
- Verify: no SwiftUI view-graph pass on tick; no dropped frames during flick + settle.
- Commit, PR, done.

### Parallel dispatch

Only Phase A parallelizes. Everything downstream is serial because interaction feel tuning depends on decisions from the previous phase. Parallelizing feel work produces divergent taste decisions that don't merge.

### Effort

Phase A: 1 session. Phase B: 1 session. Phase C: 0.5 session. Phase D: 0.5 session. Phase E: 0.5 session. **Total: ~3.5 focused sessions, ~1000–1400 LOC net.**

## Risks

1. **Spring tuning feels wrong on first try.** Mitigation: Phase C exists to tune in isolation. If critical damping feels *too* restrained, we unlock `damping < 1.0` as a knob — but only after measuring, not speculatively.
2. **UIScrollView content size updates mid-scroll** as `FeedEngine` appends items. Mitigation: `SlidingLoopHostView` observes `items.count` and adjusts `contentSize` without touching `contentOffset`. Test explicitly in Phase D.
3. **Rotation / split-screen.** Mitigation: on `layoutSubviews`, if `bounds.height` changed, re-snap: `contentOffset.y = visibleIndex * bounds.height`, no animation.
4. **`UIHostingController` memory peak at ~60 MB.** Mitigation: acceptable for pass 1. Recycling is pass 2.
5. **WKWebView reveal lag remains.** Explicitly out of scope. Pass 2 will address player reveal independently.

## Success Criteria

- All unit tests pass with 100% coverage on primitives.
- Manual FlowDeck verification: flicks, slow drags, mid-settle interruption, VoiceOver rotator, Split View resize all behave correctly.
- Instruments Time Profiler shows no SwiftUI view-graph passes on spring tick.
- Scroll settles in ≤ 320ms after finger lift (response 0.28s + margin).
- Zero visible overshoot on any scroll (critical damping guarantee).
- The user, running the app in FlowDeck, confirms it feels measurably snappier than the current path and matches the iA Writer / Notion feel target.
