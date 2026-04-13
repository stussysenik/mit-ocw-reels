# SlidingLoop — Physics-Driven Reels Scroll — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SwiftUI `ScrollView` + `.scrollTargetBehavior(.paging)` in `DiscoverView` with a custom UIKit-hosted `SlidingLoop` that drives `contentOffset` via a critically-damped spring on a `CADisplayLink`, yielding interruptible, velocity-aware, no-overshoot scroll with ≤320ms settle time.

**Architecture:** Four pure-Swift physics primitives (`Spring`, `VelocityTracker`, `DisplayLinkDriver`, `SnapTarget`) under `MITReels/Physics/`, composed by a `SlidingLoopStateMachine` struct (extracted for unit-testability) which is hosted inside a `UIScrollView` subclass inside a `UIViewControllerRepresentable`. Each reel renders into its own `UIHostingController<AnyView>` — no recycling in pass 1 (recycling is pass 2).

**Tech Stack:** Swift 5.9, SwiftUI, UIKit (`UIScrollView`, `UIHostingController`, `UIViewControllerRepresentable`), `QuartzCore.CADisplayLink`, Swift Testing framework (`import Testing`), FlowDeck CLI for builds/tests/simulator, Maestro for UI smoke tests.

**Spec:** `docs/superpowers/specs/2026-04-13-sliding-loop-physics-design.md`

---

## File Structure

### New files

- `MITReels/Physics/Spring.swift` — semi-implicit Euler spring integrator
- `MITReels/Physics/VelocityTracker.swift` — rolling-window velocity estimator
- `MITReels/Physics/DisplayLinkDriver.swift` — closure-based `CADisplayLink` wrapper
- `MITReels/Physics/SnapTarget.swift` — pure-function snap policy
- `MITReels/Physics/SlidingLoopStateMachine.swift` — state machine struct composing the primitives
- `MITReels/Components/SlidingLoopHostScrollView.swift` — `UIScrollView` subclass + delegate
- `MITReels/Components/SlidingLoop.swift` — `UIViewControllerRepresentable` SwiftUI wrapper
- `MITReels/Components/SlidingLoopPreview.swift` — `#Preview` harness for tuning (DEBUG only)
- `MITReelsTests/Physics/SpringTests.swift`
- `MITReelsTests/Physics/VelocityTrackerTests.swift`
- `MITReelsTests/Physics/DisplayLinkDriverTests.swift`
- `MITReelsTests/Physics/SnapTargetTests.swift`
- `MITReelsTests/Physics/SlidingLoopStateMachineTests.swift`

### Modified files

- `MITReels/Views/DiscoverView.swift` — swap `ScrollView` for `SlidingLoop`, delete notification-based dislike/videoEnd advances (replaced by direct index math)
- `MITReels/Views/ReelView.swift` — delete 150ms `Task.sleep` at lines 297–303
- `MITReels.xcodeproj/project.pbxproj` — add new Swift files to the `MITReels` and `MITReelsTests` targets

### Unchanged (explicitly out of scope)

- `MITReels/Services/FeedEngine.swift`
- `MITReels/Services/WKWebViewPool.swift`
- `MITReels/Services/ThumbnailPrefetcher.swift`
- `MITReels/Components/YouTubePlayerView.swift`
- All other views, models, services

---

## Prerequisites

Before Task 1 starts, run once:

- [ ] **Pre-Step 1: Confirm FlowDeck config is saved for this project**

```bash
flowdeck config set -w /Users/s3nik/Desktop/mit-ocw-reels/MITReels.xcodeproj -s MITReels
flowdeck config get
```

Expected: output shows workspace=`MITReels.xcodeproj`, scheme=`MITReels`.

- [ ] **Pre-Step 2: Boot or identify a target simulator**

```bash
flowdeck simulator list -P iOS -A | head -20
```

Expected: a list of booted / available iOS simulators. Pick one (e.g. "iPhone 16 Pro") and remember the name — it's used in `-S` flags below. Replace `iPhone 16 Pro` in later commands with whichever simulator you picked.

- [ ] **Pre-Step 3: Baseline test run on `main` to confirm green starting state**

```bash
flowdeck test -S "iPhone 16 Pro"
```

Expected: all existing tests pass. If anything is red, fix it before starting — don't layer new work on broken tests.

- [ ] **Pre-Step 4: Create the `Physics` directory on disk**

```bash
mkdir -p /Users/s3nik/Desktop/mit-ocw-reels/MITReels/Physics
mkdir -p /Users/s3nik/Desktop/mit-ocw-reels/MITReelsTests/Physics
```

Expected: directories exist (silently). The Xcode project still needs to know about them — that happens in Task 0.

- [ ] **Pre-Step 5: Create a new branch**

```bash
cd /Users/s3nik/Desktop/mit-ocw-reels
git checkout -b feature/sliding-loop-physics
```

Expected: `Switched to a new branch 'feature/sliding-loop-physics'`.

---

## Task 0: Xcode project setup — add new files to targets

Xcode project files (`project.pbxproj`) don't auto-discover new files on disk. Every new Swift file in Tasks 1–9 must be added to the `MITReels` target (for app code) or `MITReelsTests` target (for tests). The easiest path is to open Xcode once, create empty placeholder files through the Xcode "New File" menu for all the files we'll write, and then let Tasks 1–9 overwrite their contents.

**Files:**
- Modify: `MITReels.xcodeproj/project.pbxproj` (indirectly, via Xcode GUI)

- [ ] **Step 1: Open the project in Xcode**

```bash
open /Users/s3nik/Desktop/mit-ocw-reels/MITReels.xcodeproj
```

Expected: Xcode launches with the MITReels project open.

- [ ] **Step 2: Create a new group "Physics" under the `MITReels` group**

In Xcode's Project navigator (left sidebar), right-click the `MITReels` group → New Group → name it `Physics`. It should appear alongside `Models`, `Components`, `Services`, etc.

- [ ] **Step 3: Create empty Swift files inside the Physics group**

For each filename below, in Xcode: right-click the `Physics` group → New File → Swift File → name it exactly as listed → ensure "Targets: MITReels" is checked (NOT MITReelsTests).

Files to create (all empty placeholders):
- `Spring.swift`
- `VelocityTracker.swift`
- `DisplayLinkDriver.swift`
- `SnapTarget.swift`
- `SlidingLoopStateMachine.swift`

Then, inside the `Components` group, create:
- `SlidingLoopHostScrollView.swift`
- `SlidingLoop.swift`
- `SlidingLoopPreview.swift`

- [ ] **Step 4: Create a new group "Physics" under the `MITReelsTests` group**

In Xcode: right-click the `MITReelsTests` group → New Group → name it `Physics`.

- [ ] **Step 5: Create empty test Swift files inside the test Physics group**

For each filename below, in Xcode: right-click the `MITReelsTests/Physics` group → New File → Swift File → name it exactly → ensure "Targets: MITReelsTests" is checked (NOT MITReels).

Files:
- `SpringTests.swift`
- `VelocityTrackerTests.swift`
- `DisplayLinkDriverTests.swift`
- `SnapTargetTests.swift`
- `SlidingLoopStateMachineTests.swift`

- [ ] **Step 6: Verify all files are in the pbxproj**

```bash
grep -c "Spring.swift\|VelocityTracker.swift\|DisplayLinkDriver.swift\|SnapTarget.swift\|SlidingLoopStateMachine.swift\|SlidingLoopHostScrollView.swift\|SlidingLoop.swift\|SlidingLoopPreview.swift" /Users/s3nik/Desktop/mit-ocw-reels/MITReels.xcodeproj/project.pbxproj
```

Expected: a number ≥ 16 (each file appears multiple times in pbxproj — PBXFileReference, PBXBuildFile, etc.).

- [ ] **Step 7: Confirm the project still builds with empty files**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: BUILD SUCCEEDED. (Empty Swift files compile cleanly.)

- [ ] **Step 8: Commit the project scaffolding**

```bash
cd /Users/s3nik/Desktop/mit-ocw-reels
git add MITReels.xcodeproj/project.pbxproj MITReels/Physics MITReels/Components/SlidingLoop*.swift MITReelsTests/Physics
git commit -m "chore(physics): scaffold Physics module and SlidingLoop file tree"
```

Expected: commit succeeds.

---

# Phase A — Primitives in isolation (Tasks 1, 2, 3 can run in parallel)

## Task 1: Spring — critically-damped mass-spring-damper integrator

**Parallel-safe with Tasks 2 and 3.** Touches only `Spring.swift` and `SpringTests.swift`.

**Files:**
- Create: `MITReels/Physics/Spring.swift`
- Create: `MITReelsTests/Physics/SpringTests.swift`

- [ ] **Step 1: Write the failing test file**

Overwrite `MITReelsTests/Physics/SpringTests.swift`:

```swift
import Testing
import Foundation
@testable import MITReels

/// Tests the critically-damped spring integrator.
///
/// The underlying ODE is a mass-spring-damper at critical damping:
///   friction = 2 · √(mass · tension)
///   tension  = (2π / response)² · mass
/// which guarantees monotonic convergence with no overshoot in the continuous
/// case. Semi-implicit Euler at 60 Hz introduces sub-pixel discrete-time error,
/// which these tests bound rather than pin exactly.
struct SpringTests {
    /// At critical damping, the spring should not visibly overshoot its target.
    /// "Visible" here means > 1 logical pixel at @2x, i.e. > 0.5 points.
    @Test func criticallyDampedStaysBelowSubPixelOvershoot() {
        var spring = Spring(response: 0.3, position: 0, velocity: 0, target: 100)
        var maxPosition: Double = 0
        let dt = 1.0 / 60.0
        for _ in 0..<120 {
            spring = spring.stepped(dt: dt)
            maxPosition = max(maxPosition, spring.position)
        }
        #expect(maxPosition <= 100.5)
    }

    /// From rest, distance-to-target should never increase between steps.
    @Test func monotonicConvergenceFromRest() {
        var spring = Spring(response: 0.3, position: 0, velocity: 0, target: 100)
        var previousDistance = abs(spring.target - spring.position)
        let dt = 1.0 / 60.0
        for _ in 0..<60 {
            spring = spring.stepped(dt: dt)
            let distance = abs(spring.target - spring.position)
            // Allow 1e-9 for floating-point noise at the asymptote.
            #expect(distance <= previousDistance + 1e-9)
            previousDistance = distance
        }
    }

    /// Handed-off velocity must actually move the position — the integrator
    /// must not silently discard velocity when position equals target.
    @Test func velocityHandoffAdvancesPosition() {
        var spring = Spring(response: 0.3, position: 0, velocity: 2000, target: 0)
        spring = spring.stepped(dt: 1.0 / 60.0)
        #expect(spring.position > 0)
    }

    /// At response=0.28 and a 1000-unit step, isSettled should be reached in
    /// at most 25 frames (~417ms at 60 Hz). Typical settle is ~300ms.
    @Test func settlesWithinBudget() {
        var spring = Spring(response: 0.28, position: 0, velocity: 0, target: 1000)
        let dt = 1.0 / 60.0
        var steps = 0
        while !spring.isSettled && steps < 100 {
            spring = spring.stepped(dt: dt)
            steps += 1
        }
        #expect(spring.isSettled)
        #expect(steps <= 25)
    }

    /// isSettled requires BOTH sub-threshold velocity and sub-threshold distance.
    @Test func isSettledChecksBothVelocityAndDistance() {
        var moving = Spring(response: 0.28, position: 0, velocity: 100, target: 0)
        #expect(!moving.isSettled)

        var arrived = Spring(response: 0.28, position: 100, velocity: 0, target: 100)
        #expect(arrived.isSettled)

        var nearButFast = Spring(response: 0.28, position: 99.9, velocity: 10, target: 100)
        #expect(!nearButFast.isSettled)

        _ = moving
        _ = arrived
        _ = nearButFast
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (Spring doesn't exist yet)**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/SpringTests"
```

Expected: BUILD FAILED with errors like `cannot find 'Spring' in scope`. This confirms the tests are wired up correctly — they fail because the type doesn't exist, not because of a typo.

- [ ] **Step 3: Write the Spring implementation**

Overwrite `MITReels/Physics/Spring.swift`:

```swift
import Foundation

/// A critically-damped mass-spring-damper integrator using semi-implicit Euler.
///
/// Single knob: `response` (settle time in seconds). Damping is derived
/// to exactly meet the critical-damping condition
///   friction = 2 · √(mass · tension)
/// so there is no `damping` or `bounciness` argument. If you want bounce,
/// promote damping from derived to explicit — but only after measuring.
///
/// Use from a `CADisplayLink` tick callback: call `stepped(dt:)` on the same
/// timestamp delta the display link reports, read `position` on each step,
/// stop the driver when `isSettled` is true.
struct Spring: Equatable, Sendable {
    var mass: Double = 1
    /// Settle time budget in seconds. 0.28 ≈ "decisive, not abrupt".
    var response: Double = 0.28
    var position: Double = 0
    var velocity: Double = 0
    var target: Double = 0

    /// Stiffness derived from response and mass.
    /// tension = (2π / response)² · mass
    private var tension: Double {
        let omega = 2 * .pi / response
        return omega * omega * mass
    }

    /// Critical damping: friction = 2 · √(mass · tension).
    private var friction: Double {
        2 * (mass * tension).squareRoot()
    }

    /// Advances the integrator by `dt` seconds using semi-implicit Euler.
    ///
    /// Semi-implicit (velocity-updated-first) is strictly more stable than
    /// explicit Euler for stiff oscillators — we use the *new* velocity to
    /// update position, which dissipates energy correctly instead of adding it.
    func stepped(dt: Double) -> Spring {
        var next = self
        let accel = -tension * (next.position - next.target) - friction * next.velocity
        next.velocity += accel * dt
        next.position += next.velocity * dt
        return next
    }

    /// True when both the velocity and the remaining distance are below half
    /// a logical point — i.e. any further motion would be invisible at @2x.
    var isSettled: Bool {
        abs(velocity) < 0.5 && abs(target - position) < 0.5
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/SpringTests"
```

Expected: all 5 tests pass. If any fail with a close-to-but-not-exact margin (e.g. overshoot is 100.51 instead of 100.5), the discrete-time integrator is accumulating more error than expected — investigate `dt` or the step order before loosening the threshold.

- [ ] **Step 5: Commit**

```bash
git add MITReels/Physics/Spring.swift MITReelsTests/Physics/SpringTests.swift
git commit -m "feat(physics): add critically-damped Spring integrator with tests"
```

---

## Task 2: VelocityTracker + SnapTarget — stateless primitives

**Parallel-safe with Tasks 1 and 3.** Two primitives in one task because both are small and tightly related — `VelocityTracker` feeds `SnapTarget`.

**Files:**
- Create: `MITReels/Physics/VelocityTracker.swift`
- Create: `MITReels/Physics/SnapTarget.swift`
- Create: `MITReelsTests/Physics/VelocityTrackerTests.swift`
- Create: `MITReelsTests/Physics/SnapTargetTests.swift`

- [ ] **Step 1: Write the failing VelocityTracker test file**

Overwrite `MITReelsTests/Physics/VelocityTrackerTests.swift`:

```swift
import Testing
import Foundation
@testable import MITReels

/// Tests the rolling-window velocity estimator.
///
/// We use our own estimator rather than `UIPanGestureRecognizer.velocity(in:)`
/// because the recognizer's value is instantaneous and swings wildly when the
/// user pauses mid-drag. A rolling window smooths that out.
struct VelocityTrackerTests {
    /// Four uniform samples at 60 Hz, each 10pts further, should produce
    /// velocity ≈ 600 pts/sec (10pts / 0.01667s).
    @Test func uniformSamplesProduceExpectedVelocity() {
        var tracker = VelocityTracker()
        let dt = 1.0 / 60.0
        tracker.add(position: 0, at: 0)
        tracker.add(position: 10, at: dt)
        tracker.add(position: 20, at: dt * 2)
        tracker.add(position: 30, at: dt * 3)

        // 3-sample window keeps the last 3 samples.
        // Velocity is computed across the window span:
        //   (last - first) / (last.time - first.time)
        // With samples (10, dt), (20, 2dt), (30, 3dt):
        //   (30 - 10) / (3dt - dt) = 20 / (2 / 60) = 600 pts/sec
        #expect(abs(tracker.velocity - 600) < 1)
    }

    /// Samples older than 100ms must be evicted when a newer sample arrives.
    @Test func staleSamplesAreEvicted() {
        var tracker = VelocityTracker()
        tracker.add(position: 0, at: 0)
        // Jump forward past the 100ms eviction window.
        tracker.add(position: 100, at: 0.2)
        tracker.add(position: 120, at: 0.22)

        // The sample at t=0 should have been evicted when we added t=0.2,
        // leaving only the two fresh samples.
        // Velocity = (120 - 100) / 0.02 = 1000 pts/sec.
        #expect(abs(tracker.velocity - 1000) < 50)
    }

    /// reset() must clear all samples so subsequent velocity reads return 0.
    @Test func resetClearsState() {
        var tracker = VelocityTracker()
        tracker.add(position: 0, at: 0)
        tracker.add(position: 10, at: 0.01)
        #expect(tracker.velocity != 0)
        tracker.reset()
        #expect(tracker.velocity == 0)
    }

    /// A single sample yields zero velocity (no delta to compute from).
    @Test func singleSampleReturnsZeroVelocity() {
        var tracker = VelocityTracker()
        tracker.add(position: 100, at: 1.0)
        #expect(tracker.velocity == 0)
    }

    /// Zero timespan (duplicate timestamps) yields zero velocity, not NaN/inf.
    @Test func zeroTimespanReturnsZeroVelocity() {
        var tracker = VelocityTracker()
        tracker.add(position: 0, at: 0)
        tracker.add(position: 100, at: 0)
        #expect(tracker.velocity == 0)
    }
}
```

- [ ] **Step 2: Write the failing SnapTarget test file**

Overwrite `MITReelsTests/Physics/SnapTargetTests.swift`:

```swift
import Testing
@testable import MITReels

/// Tests the snap-to-index policy. Pure function, no state.
///
/// Single-step policy: a flick advances by at most one page in the velocity
/// direction. No inertial multi-page projection — that's where Apple's default
/// paging feels mushy.
struct SnapTargetTests {
    @Test func zeroVelocityBelowMidpointRoundsDown() {
        let idx = SnapTarget.nextIndex(
            from: 450, velocity: 0, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 0)
    }

    @Test func zeroVelocityAboveMidpointRoundsUp() {
        let idx = SnapTarget.nextIndex(
            from: 551, velocity: 0, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 1)
    }

    @Test func forwardFlickAdvancesOneFromCurrent() {
        // offset=200, round(200/1000)=0, velocity above threshold → 0 + 1 = 1
        let idx = SnapTarget.nextIndex(
            from: 200, velocity: 501, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 1)
    }

    @Test func backwardFlickClampsAtZero() {
        // offset=200, round(200/1000)=0, backward flick → -1, clamp → 0
        let idx = SnapTarget.nextIndex(
            from: 200, velocity: -501, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 0)
    }

    @Test func veryLargeForwardVelocityStillOnlyAdvancesOnePage() {
        // Even with huge velocity, single-step policy caps at +1.
        let idx = SnapTarget.nextIndex(
            from: 300, velocity: 10000, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 1)
    }

    @Test func clampsAtLastIndex() {
        // offset=9000, round(9000/1000)=9, +1 = 10, clamp → 9 (itemCount-1)
        let idx = SnapTarget.nextIndex(
            from: 9000, velocity: 1000, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 9)
    }

    @Test func belowFlickThresholdSnapsToNearest() {
        // |velocity| < flickThreshold (default 500) → use rounded position.
        let idx = SnapTarget.nextIndex(
            from: 400, velocity: 300, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 0) // round(0.4) = 0
    }

    @Test func emptyItemCountReturnsZero() {
        let idx = SnapTarget.nextIndex(
            from: 0, velocity: 0, pageHeight: 1000, itemCount: 0
        )
        #expect(idx == 0)
    }

    @Test func zeroPageHeightReturnsZero() {
        let idx = SnapTarget.nextIndex(
            from: 100, velocity: 100, pageHeight: 0, itemCount: 10
        )
        #expect(idx == 0)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/VelocityTrackerTests"
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/SnapTargetTests"
```

Expected: BUILD FAILED — `cannot find 'VelocityTracker'` / `cannot find 'SnapTarget'`.

- [ ] **Step 4: Write the VelocityTracker implementation**

Overwrite `MITReels/Physics/VelocityTracker.swift`:

```swift
import Foundation
import QuartzCore

/// Rolling-window velocity estimator.
///
/// Samples positions paired with timestamps. Computes instantaneous velocity
/// as `(last - first) / (last.time - first.time)` across the sample window.
/// Samples older than `maxAge` relative to the newest sample are evicted,
/// and the window is capped at `maxSamples` entries (most recent wins).
///
/// This exists so we don't depend on `UIPanGestureRecognizer.velocity(in:)`
/// which reports instantaneous velocity at query time and swings wildly when
/// a user pauses mid-drag. The rolling window produces a stable reading.
struct VelocityTracker: Sendable {
    private struct Sample: Sendable {
        let position: Double
        let time: CFTimeInterval
    }

    private var samples: [Sample] = []
    private let maxSamples = 3
    private let maxAge: CFTimeInterval = 0.1 // 100ms

    /// Add a new position sample. Evicts stale / excess samples automatically.
    mutating func add(position: Double, at time: CFTimeInterval) {
        samples.append(Sample(position: position, time: time))
        // Evict anything older than maxAge relative to the newest sample.
        samples.removeAll { time - $0.time > maxAge }
        // Cap to the most recent maxSamples.
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    /// Current velocity in points per second. Returns 0 when insufficient data.
    var velocity: Double {
        guard samples.count >= 2 else { return 0 }
        let first = samples.first!
        let last = samples.last!
        let dt = last.time - first.time
        guard dt > 0 else { return 0 }
        return (last.position - first.position) / dt
    }

    mutating func reset() {
        samples.removeAll()
    }
}
```

- [ ] **Step 5: Write the SnapTarget implementation**

Overwrite `MITReels/Physics/SnapTarget.swift`:

```swift
import Foundation

/// Pure-function snap-to-index policy.
///
/// Given a current scroll offset, a velocity estimate, and page geometry,
/// returns the index the scroller should settle on. Single-step: at most
/// one page advance per call. Clamps to `[0, itemCount - 1]`.
enum SnapTarget {
    /// - Parameters:
    ///   - offset: Current scroll offset in points.
    ///   - velocity: Measured velocity in points/sec (positive = forward).
    ///   - pageHeight: Height of a single page in points.
    ///   - itemCount: Total number of pages.
    ///   - flickThreshold: Velocity magnitude above which we advance by one
    ///     page rather than snapping to the nearest. Default 500 pts/sec.
    static func nextIndex(
        from offset: Double,
        velocity: Double,
        pageHeight: Double,
        itemCount: Int,
        flickThreshold: Double = 500
    ) -> Int {
        guard itemCount > 0, pageHeight > 0 else { return 0 }
        let current = Int((offset / pageHeight).rounded())
        let raw: Int
        if abs(velocity) < flickThreshold {
            raw = current
        } else if velocity > 0 {
            raw = current + 1
        } else {
            raw = current - 1
        }
        return max(0, min(itemCount - 1, raw))
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/VelocityTrackerTests"
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/SnapTargetTests"
```

Expected: all 5 + 9 tests pass.

- [ ] **Step 7: Commit**

```bash
git add MITReels/Physics/VelocityTracker.swift MITReels/Physics/SnapTarget.swift MITReelsTests/Physics/VelocityTrackerTests.swift MITReelsTests/Physics/SnapTargetTests.swift
git commit -m "feat(physics): add VelocityTracker and SnapTarget with tests"
```

---

## Task 3: DisplayLinkDriver — CADisplayLink wrapper

**Parallel-safe with Tasks 1 and 2.** Touches only `DisplayLinkDriver.swift` and its test.

**Files:**
- Create: `MITReels/Physics/DisplayLinkDriver.swift`
- Create: `MITReelsTests/Physics/DisplayLinkDriverTests.swift`

- [ ] **Step 1: Write the failing test file**

Overwrite `MITReelsTests/Physics/DisplayLinkDriverTests.swift`:

```swift
import Testing
import Foundation
@testable import MITReels

/// Tests the CADisplayLink wrapper.
///
/// We can't easily test the actual tick timing in unit tests (no real display),
/// so we focus on lifecycle: start/stop state, idempotence, and that the
/// onTick closure is fully wired through.
struct DisplayLinkDriverTests {
    @Test func initiallyNotRunning() {
        let driver = DisplayLinkDriver()
        #expect(!driver.isRunning)
    }

    @Test func startSetsIsRunning() async {
        let driver = await MainActor.run { DisplayLinkDriver() }
        await MainActor.run { driver.start() }
        let running = await MainActor.run { driver.isRunning }
        #expect(running)
        await MainActor.run { driver.stop() }
    }

    @Test func stopResetsIsRunning() async {
        let driver = await MainActor.run { DisplayLinkDriver() }
        await MainActor.run {
            driver.start()
            driver.stop()
        }
        let running = await MainActor.run { driver.isRunning }
        #expect(!running)
    }

    @Test func doubleStartIsIdempotent() async {
        let driver = await MainActor.run { DisplayLinkDriver() }
        await MainActor.run {
            driver.start()
            driver.start()
        }
        let running = await MainActor.run { driver.isRunning }
        #expect(running)
        await MainActor.run { driver.stop() }
    }

    @Test func doubleStopIsIdempotent() async {
        let driver = await MainActor.run { DisplayLinkDriver() }
        await MainActor.run {
            driver.stop()
            driver.stop()
        }
        let running = await MainActor.run { driver.isRunning }
        #expect(!running)
    }

    /// Verifies the closure wiring: when the display link fires, onTick is
    /// invoked with a positive dt. We wait up to 200ms for at least one tick.
    @Test func tickFiresOnTickClosure() async {
        let expectation = TickExpectation()
        await MainActor.run {
            let driver = DisplayLinkDriver()
            driver.onTick = { dt in
                Task { await expectation.fulfill(with: dt) }
            }
            driver.start()
            // Keep driver alive for the duration of this test
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                driver.stop()
            }
        }
        try? await Task.sleep(for: .milliseconds(250))
        let recorded = await expectation.dts
        #expect(!recorded.isEmpty, "Expected at least one tick within 200ms")
        if let first = recorded.first {
            #expect(first > 0 && first < 0.1, "dt should be plausible frame time")
        }
    }

    actor TickExpectation {
        var dts: [CFTimeInterval] = []
        func fulfill(with dt: CFTimeInterval) { dts.append(dt) }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/DisplayLinkDriverTests"
```

Expected: BUILD FAILED — `cannot find 'DisplayLinkDriver'`.

- [ ] **Step 3: Write the DisplayLinkDriver implementation**

Overwrite `MITReels/Physics/DisplayLinkDriver.swift`:

```swift
import Foundation
import QuartzCore

/// Closure-based `CADisplayLink` wrapper, ProMotion-aware.
///
/// Invariants:
/// - Attached to `.main` runloop, `.common` mode (runs during tracking).
/// - `preferredFrameRateRange` requests up to 120 Hz on ProMotion displays.
/// - Invocation is idempotent: `start()` while running is a no-op, `stop()`
///   while stopped is a no-op.
/// - `isRunning` reflects the attached state, not the paused state — we never
///   pause, we stop.
///
/// The driver is MainActor-bound because `CADisplayLink` requires a runloop
/// attachment and its tick fires on the main thread.
@MainActor
final class DisplayLinkDriver {
    var onTick: ((CFTimeInterval) -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    var isRunning: Bool { displayLink != nil }

    init() {}

    deinit {
        displayLink?.invalidate()
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(owner: self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        lastTimestamp = 0
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    fileprivate func handleTick(timestamp: CFTimeInterval) {
        let dt: CFTimeInterval
        if lastTimestamp == 0 {
            // First tick — estimate with one frame at 60 Hz rather than
            // reporting dt=0 (which would stall the integrator).
            dt = 1.0 / 60.0
        } else {
            dt = timestamp - lastTimestamp
        }
        lastTimestamp = timestamp
        onTick?(dt)
    }
}

/// `CADisplayLink` holds a strong reference to its target. We route through a
/// small proxy object so `DisplayLinkDriver` isn't retained by its own link —
/// that would leak the driver until `stop()` is called.
///
/// `MainActor.assumeIsolated` is safe here because CADisplayLink fires on the
/// main runloop (we added it with `.add(to: .main, forMode: .common)`), so the
/// objc-selector callback is always executing on the main thread.
private final class DisplayLinkProxy: NSObject {
    weak var owner: DisplayLinkDriver?

    init(owner: DisplayLinkDriver) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            owner?.handleTick(timestamp: link.timestamp)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/DisplayLinkDriverTests"
```

Expected: all 6 tests pass. The `tickFiresOnTickClosure` test is the slowest — it waits ~250ms for a real display link tick.

- [ ] **Step 5: Commit**

```bash
git add MITReels/Physics/DisplayLinkDriver.swift MITReelsTests/Physics/DisplayLinkDriverTests.swift
git commit -m "feat(physics): add DisplayLinkDriver CADisplayLink wrapper with tests"
```

---

## Phase A Gate

- [ ] **Run the full Physics test module:**

```bash
flowdeck test -S "iPhone 16 Pro" --test-targets MITReelsTests
```

Expected: All physics tests (SpringTests + VelocityTrackerTests + SnapTargetTests + DisplayLinkDriverTests) pass, plus all pre-existing tests still pass. If a pre-existing test regresses, investigate — Phase A should be purely additive.

- [ ] **Commit Phase A gate marker (optional annotation commit for bisect):**

```bash
git commit --allow-empty -m "chore: Phase A complete — physics primitives in isolation"
```

---

# Phase B — State machine and host view

## Task 4: SlidingLoopStateMachine — testable state composition

The spec defines a 3-state machine inside `SlidingLoopHostView`. We extract it into a pure struct so it can be unit-tested without driving a real `UIScrollView`. The hostview in Task 5 will forward delegate callbacks to this struct.

**Files:**
- Create: `MITReels/Physics/SlidingLoopStateMachine.swift`
- Create: `MITReelsTests/Physics/SlidingLoopStateMachineTests.swift`

- [ ] **Step 1: Write the failing state machine tests**

Overwrite `MITReelsTests/Physics/SlidingLoopStateMachineTests.swift`:

```swift
import Testing
import Foundation
@testable import MITReels

/// Tests the 3-state machine: Idle → Dragging → Settling → Idle.
///
/// Every finger-lift routes through Settling; even a zero-velocity release
/// enters Settling and then resolves on the first tick. There is no direct
/// Dragging → Idle edge.
struct SlidingLoopStateMachineTests {
    private func makeMachine() -> SlidingLoopStateMachine {
        var m = SlidingLoopStateMachine(response: 0.28)
        m.itemCount = 10
        m.pageHeight = 1000
        return m
    }

    @Test func initialStateIsIdle() {
        let m = makeMachine()
        #expect(m.state == .idle)
    }

    @Test func willBeginDraggingEntersDragging() {
        var m = makeMachine()
        m.willBeginDragging()
        #expect(m.state == .dragging)
    }

    @Test func willEndDraggingFromRestEntersSettlingAtCurrentPage() {
        var m = makeMachine()
        m.willBeginDragging()
        // No samples → velocity = 0 → settles at nearest page.
        let target = m.willEndDragging(offset: 0)
        if case .settling(let idx) = m.state {
            #expect(idx == 0)
            #expect(target == 0)
        } else {
            Issue.record("Expected .settling after willEndDragging, got \(m.state)")
        }
    }

    @Test func forwardFlickEntersSettlingAtNextPage() {
        var m = makeMachine()
        m.willBeginDragging()
        // Simulate a forward drag: positions increasing fast.
        m.didScroll(offset: 0, at: 0.0)
        m.didScroll(offset: 20, at: 0.016)
        m.didScroll(offset: 40, at: 0.032)
        // Velocity ≈ (40 - 0) / 0.032 ≈ 1250 pts/sec → above flick threshold
        let target = m.willEndDragging(offset: 40)
        if case .settling(let idx) = m.state {
            #expect(idx == 1)
            #expect(target == 1000)
        } else {
            Issue.record("Expected .settling, got \(m.state)")
        }
    }

    @Test func tickUntilSettledTransitionsToIdleWithTargetIndex() {
        var m = makeMachine()
        m.willBeginDragging()
        _ = m.willEndDragging(offset: 0)
        // Drive until settled. Hard cap at 100 steps to avoid infinite loop.
        var steps = 0
        var settledIndex: Int? = nil
        while settledIndex == nil && steps < 100 {
            let result = m.tick(dt: 1.0 / 60.0)
            settledIndex = result.settledIndex
            steps += 1
        }
        #expect(settledIndex == 0)
        #expect(m.state == .idle)
    }

    @Test func tickDuringIdleReportsImmediatelySettled() {
        var m = makeMachine()
        let result = m.tick(dt: 1.0 / 60.0)
        // Idle state — no settling to do. Callers interpret this as "stop driver."
        #expect(result.settledIndex != nil)
    }

    @Test func interruptDuringSettlingReEntersDragging() {
        var m = makeMachine()
        m.willBeginDragging()
        m.didScroll(offset: 0, at: 0.0)
        m.didScroll(offset: 50, at: 0.05)
        _ = m.willEndDragging(offset: 50)
        // Spring is now running toward page 1.
        _ = m.tick(dt: 1.0 / 60.0)
        // User grabs mid-settle.
        m.willBeginDragging()
        #expect(m.state == .dragging)
    }

    @Test func dragEndAtExactPageStaysOnPage() {
        var m = makeMachine()
        m.willBeginDragging()
        // Slow settle at exact page boundary.
        m.didScroll(offset: 1000, at: 0.0)
        m.didScroll(offset: 1000, at: 0.1)
        _ = m.willEndDragging(offset: 1000)
        if case .settling(let idx) = m.state {
            #expect(idx == 1)
        } else {
            Issue.record("Expected .settling(1), got \(m.state)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/SlidingLoopStateMachineTests"
```

Expected: BUILD FAILED — `cannot find 'SlidingLoopStateMachine'`.

- [ ] **Step 3: Write the state machine implementation**

Overwrite `MITReels/Physics/SlidingLoopStateMachine.swift`:

```swift
import Foundation
import QuartzCore

/// The 3-state machine that composes the physics primitives.
///
///     Idle ──willBeginDragging──▶ Dragging
///     Dragging ──willEndDragging──▶ Settling(targetIndex)
///     Settling ──tick (spring.isSettled)──▶ Idle
///     Settling ──willBeginDragging (interrupt)──▶ Dragging
///
/// Every finger-lift routes through Settling. A zero-velocity release still
/// enters Settling (with target == position) and resolves on the first tick.
///
/// This struct is pure value semantics — no UIKit, no @MainActor. Tests drive
/// it directly. The hostview (Task 5) forwards `UIScrollViewDelegate`
/// callbacks into it.
struct SlidingLoopStateMachine: Sendable {
    enum State: Equatable, Sendable {
        case idle
        case dragging
        case settling(targetIndex: Int)
    }

    private(set) var state: State = .idle
    private(set) var spring: Spring
    private var velocityTracker = VelocityTracker()

    /// Total page count. Set by the host view when `items.count` changes.
    var itemCount: Int = 0

    /// Height of a single page in points. Set by the host view in layoutSubviews.
    var pageHeight: Double = 0

    /// Flick threshold in pts/sec. Exposed for tuning in Phase C.
    var flickThreshold: Double = 500

    init(response: Double = 0.28) {
        self.spring = Spring(response: response)
    }

    // MARK: - Delegate forwarders

    /// Forwarded from `scrollViewDidScroll`. Samples into the velocity tracker.
    mutating func didScroll(offset: Double, at time: CFTimeInterval) {
        velocityTracker.add(position: offset, at: time)
    }

    /// Forwarded from `scrollViewWillBeginDragging`.
    ///
    /// Transitions to `.dragging` unconditionally — from `.idle` (normal start)
    /// or from `.settling` (mid-settle interrupt). Resets the velocity tracker
    /// so a fresh window collects the new drag.
    mutating func willBeginDragging() {
        velocityTracker.reset()
        state = .dragging
    }

    /// Forwarded from `scrollViewWillEndDragging`. Computes target and returns
    /// the target offset in points, which the caller should use to prime
    /// `spring.target` (already done inside) and to anchor the native
    /// `targetContentOffset.pointee`.
    ///
    /// Returns the settle-target offset so the caller can optionally use it
    /// for debug visualization.
    @discardableResult
    mutating func willEndDragging(offset: Double) -> Double {
        let v = velocityTracker.velocity
        let targetIndex = SnapTarget.nextIndex(
            from: offset,
            velocity: v,
            pageHeight: pageHeight,
            itemCount: itemCount,
            flickThreshold: flickThreshold
        )
        let targetY = Double(targetIndex) * pageHeight
        spring.position = offset
        spring.velocity = v
        spring.target = targetY
        state = .settling(targetIndex: targetIndex)
        return targetY
    }

    /// Forwarded from the `CADisplayLink` tick. Advances the spring by `dt`
    /// and returns `(offset, settledIndex)` where:
    /// - `offset` is where the scroll view should be positioned this frame
    /// - `settledIndex` is `nil` while still settling, and the target index
    ///   on the frame we transition back to `.idle`. When non-nil, the caller
    ///   should stop the display link and update its visible-index state.
    ///
    /// Calling this while `.idle` is a no-op that returns the current offset
    /// with a settled marker — convenient for hostview code that might see
    /// a late tick after stopping the driver.
    mutating func tick(dt: CFTimeInterval) -> (offset: Double, settledIndex: Int?) {
        guard case .settling(let targetIndex) = state else {
            let currentIndex = Int((spring.position / max(pageHeight, 1)).rounded())
            return (spring.position, currentIndex)
        }
        spring = spring.stepped(dt: dt)
        if spring.isSettled {
            let final = spring.target
            spring.position = final
            spring.velocity = 0
            state = .idle
            return (final, targetIndex)
        }
        return (spring.position, nil)
    }

    /// Re-snap to `index` without animation. Used on rotation / split-screen
    /// resize when `pageHeight` changes mid-flight.
    mutating func hardSnap(to index: Int) {
        let y = Double(index) * pageHeight
        spring.position = y
        spring.velocity = 0
        spring.target = y
        state = .idle
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flowdeck test -S "iPhone 16 Pro" --only "MITReelsTests/SlidingLoopStateMachineTests"
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add MITReels/Physics/SlidingLoopStateMachine.swift MITReelsTests/Physics/SlidingLoopStateMachineTests.swift
git commit -m "feat(physics): add SlidingLoopStateMachine composing primitives"
```

---

## Task 5: SlidingLoopHostScrollView — UIScrollView subclass

The actual `UIScrollView` subclass that owns the display link, the state machine, and the `UIScrollViewDelegate` wiring. It is not generic — it takes item count + a cell-builder closure.

**Files:**
- Create: `MITReels/Components/SlidingLoopHostScrollView.swift`

- [ ] **Step 1: Write the implementation**

Overwrite `MITReels/Components/SlidingLoopHostScrollView.swift`:

```swift
import UIKit
import SwiftUI
import QuartzCore

/// `UIScrollView` subclass that owns the physics-driven paging loop.
///
/// The host view:
/// - Delegates scroll callbacks to a `SlidingLoopStateMachine`.
/// - Runs a `DisplayLinkDriver` only while the machine is settling.
/// - Writes `contentOffset` via `setContentOffset(_:animated: false)` on each
///   tick, which keeps UIScrollView's internal state (delegate callbacks,
///   VoiceOver, content inset handling) consistent.
/// - Hosts each cell as its own `UIHostingController<AnyView>` positioned at
///   `y = index * pageHeight`. No recycling in pass 1.
///
/// The host view is non-generic. The SwiftUI wrapper in `SlidingLoop.swift`
/// erases the `Content` type into `AnyView` before handing off.
@MainActor
final class SlidingLoopHostScrollView: UIScrollView, UIScrollViewDelegate {
    // MARK: - Configuration

    /// Called when the scroll settles on a new visible index.
    var onVisibleIndexChanged: ((Int) -> Void)?

    // MARK: - Physics

    private var machine = SlidingLoopStateMachine(response: 0.28)
    private let displayLink = DisplayLinkDriver()

    // MARK: - Cell hosting

    private(set) var hostingControllers: [UIHostingController<AnyView>] = []
    private var itemCount: Int = 0
    private var lastKnownPageHeight: CGFloat = 0

    private(set) var visibleIndex: Int = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        delegate = self
        isPagingEnabled = false
        decelerationRate = .fast
        bounces = true
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never

        displayLink.onTick = { [weak self] dt in
            self?.handleTick(dt: dt)
        }
    }

    // MARK: - Hosting controller management

    /// Full replacement of the hosted cells. Called from the SwiftUI wrapper
    /// when the items array changes identity.
    func replaceCells(
        with newControllers: [UIHostingController<AnyView>],
        parent: UIViewController
    ) {
        // Tear down old
        for hc in hostingControllers {
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
        }
        hostingControllers.removeAll()

        // Attach new
        for hc in newControllers {
            parent.addChild(hc)
            hc.view.backgroundColor = .clear
            addSubview(hc.view)
            hc.didMove(toParent: parent)
            hostingControllers.append(hc)
        }
        itemCount = newControllers.count
        machine.itemCount = itemCount
        setNeedsLayout()
    }

    /// Update a single cell's rootView in place — used when `visibleIndex`
    /// changes so SwiftUI content sees the new `isVisible` flag without a
    /// full cell rebuild.
    func updateCell(at index: Int, with view: AnyView) {
        guard hostingControllers.indices.contains(index) else { return }
        hostingControllers[index].rootView = view
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let pageHeight = bounds.height
        let width = bounds.width
        guard pageHeight > 0 else { return }
        machine.pageHeight = Double(pageHeight)

        // Content size
        contentSize = CGSize(width: width, height: CGFloat(itemCount) * pageHeight)

        // Cell frames
        for (i, hc) in hostingControllers.enumerated() {
            hc.view.frame = CGRect(
                x: 0,
                y: CGFloat(i) * pageHeight,
                width: width,
                height: pageHeight
            )
        }

        if lastKnownPageHeight == 0 {
            // First layout — sync scroll offset to the current visibleIndex.
            // Covers the "scene storage restores a non-zero index before the
            // view has a height" case.
            machine.hardSnap(to: visibleIndex)
            setContentOffset(
                CGPoint(x: 0, y: CGFloat(visibleIndex) * pageHeight),
                animated: false
            )
        } else if lastKnownPageHeight != pageHeight {
            // Page height changed (rotation / split-screen resize) — re-snap.
            machine.hardSnap(to: visibleIndex)
            setContentOffset(
                CGPoint(x: 0, y: CGFloat(visibleIndex) * pageHeight),
                animated: false
            )
        }
        lastKnownPageHeight = pageHeight
    }

    // MARK: - External control

    /// Jump to a specific index without animation (called from bootstrap
    /// and from external advance-on-dislike code).
    func jump(to index: Int) {
        let clamped = max(0, min(itemCount - 1, index))
        guard clamped != visibleIndex else { return }
        visibleIndex = clamped
        machine.hardSnap(to: clamped)
        let y = CGFloat(clamped) * bounds.height
        setContentOffset(CGPoint(x: 0, y: y), animated: false)
        onVisibleIndexChanged?(clamped)
    }

    // MARK: - Tick

    private func handleTick(dt: CFTimeInterval) {
        let (offset, settledIndex) = machine.tick(dt: dt)
        setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        if let idx = settledIndex {
            displayLink.stop()
            updateVisibleIndex(to: max(0, min(itemCount - 1, idx)))
        }
    }

    private func updateVisibleIndex(to index: Int) {
        guard index != visibleIndex else { return }
        visibleIndex = index
        onVisibleIndexChanged?(index)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        machine.didScroll(
            offset: Double(scrollView.contentOffset.y),
            at: CACurrentMediaTime()
        )
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if displayLink.isRunning {
            displayLink.stop()
        }
        machine.willBeginDragging()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // 1. Kill Apple's deceleration by anchoring its target to now.
        targetContentOffset.pointee = scrollView.contentOffset

        // 2. Hand off to our state machine. It primes the spring internally.
        _ = machine.willEndDragging(offset: Double(scrollView.contentOffset.y))

        // 3. Start the tick.
        displayLink.start()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // No-op — we never use setContentOffset(_:, animated: true).
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: BUILD SUCCEEDED. No test yet — the hostview is tested indirectly via the state machine tests (pure logic) plus a manual preview harness in Task 7.

- [ ] **Step 3: Commit**

```bash
git add MITReels/Components/SlidingLoopHostScrollView.swift
git commit -m "feat(ui): add SlidingLoopHostScrollView with display-link physics"
```

---

## Task 6: SlidingLoop — SwiftUI wrapper

The public SwiftUI-facing API. `UIViewControllerRepresentable` because we need a parent `UIViewController` to manage `UIHostingController` child lifecycle correctly.

**Files:**
- Create: `MITReels/Components/SlidingLoop.swift`

- [ ] **Step 1: Write the implementation**

Overwrite `MITReels/Components/SlidingLoop.swift`:

```swift
import SwiftUI
import UIKit

/// SwiftUI-facing wrapper around `SlidingLoopHostScrollView`.
///
/// Usage:
///
///     SlidingLoop(items: items, visibleIndex: $visibleIndex) { item, isVisible in
///         ReelView(lecture: item, isVisible: isVisible, ...)
///     }
///
/// Rebuild policy: the `UIHostingController` list is rebuilt only when the
/// `items` array's id sequence changes. On every other call to
/// `updateUIViewController` we refresh cells in place so the SwiftUI content
/// sees the new `isVisible` flag without tearing down WKWebViews.
struct SlidingLoop<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    let items: [Item]
    @Binding var visibleIndex: Int
    @ViewBuilder let content: (Item, Bool) -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> SlidingLoopViewController {
        let vc = SlidingLoopViewController()
        let coordinator = context.coordinator
        vc.hostScrollView.onVisibleIndexChanged = { newIndex in
            // Update the binding through the coordinator's live parent snapshot.
            // SwiftUI will call updateUIViewController next, which refreshes
            // in-place cells with the new isVisible flags — we do not refresh
            // here, to keep the update path linear.
            if coordinator.parent.visibleIndex != newIndex {
                coordinator.parent.visibleIndex = newIndex
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: SlidingLoopViewController, context: Context) {
        // Keep the coordinator's snapshot of the parent struct current so the
        // scroll-callback closure always reads the latest binding.
        context.coordinator.parent = self

        let newIds = items.map { AnyHashable($0.id) }
        let structuralChange = context.coordinator.currentItemIds != newIds

        if structuralChange {
            let controllers: [UIHostingController<AnyView>] = items.enumerated().map { index, item in
                let isVisible = index == visibleIndex
                return UIHostingController(rootView: AnyView(content(item, isVisible)))
            }
            vc.hostScrollView.replaceCells(with: controllers, parent: vc)
            context.coordinator.currentItemIds = newIds

            if visibleIndex >= 0 && visibleIndex < items.count {
                vc.hostScrollView.jump(to: visibleIndex)
            }
        } else {
            // In-place refresh — update each cell's rootView with the latest
            // SwiftUI content, which reflects the new isVisible flag.
            for (index, item) in items.enumerated() {
                let isVisible = index == visibleIndex
                vc.hostScrollView.updateCell(at: index, with: AnyView(content(item, isVisible)))
            }
            // If the binding moved externally (e.g. dislike advance writes
            // visibleIndex directly), sync the scroll view.
            if vc.hostScrollView.visibleIndex != visibleIndex {
                vc.hostScrollView.jump(to: visibleIndex)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        var parent: SlidingLoop
        var currentItemIds: [AnyHashable] = []

        init(parent: SlidingLoop) {
            self.parent = parent
        }
    }
}

/// Container view controller that owns the scroll view and provides the
/// parent context that `UIHostingController` children require.
@MainActor
final class SlidingLoopViewController: UIViewController {
    let hostScrollView = SlidingLoopHostScrollView()

    override func loadView() {
        self.view = hostScrollView
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add MITReels/Components/SlidingLoop.swift
git commit -m "feat(ui): add SlidingLoop UIViewControllerRepresentable wrapper"
```

---

## Phase B Gate

- [ ] **Run the full test suite:**

```bash
flowdeck test -S "iPhone 16 Pro"
```

Expected: all tests pass (physics primitives + state machine + all pre-existing). The app still uses the old `ScrollView` path — nothing about `DiscoverView` has been touched yet.

- [ ] **Commit empty gate marker:**

```bash
git commit --allow-empty -m "chore: Phase B complete — host view compiles and tests pass"
```

---

# Phase C — Preview harness and tuning

## Task 7: SlidingLoopPreview — isolated tuning harness

A `#Preview`-only harness with 20 colored placeholder cells. Used to tune `Spring.response` in isolation — no `ReelView`, no `FeedEngine`, no WebView noise.

**Files:**
- Create: `MITReels/Components/SlidingLoopPreview.swift`

- [ ] **Step 1: Write the preview harness**

Overwrite `MITReels/Components/SlidingLoopPreview.swift`:

```swift
#if DEBUG
import SwiftUI

/// 20-cell tuning harness for `SlidingLoop`. DEBUG only.
///
/// Run in Xcode Preview OR as the root view in a one-off scheme to tune
/// `Spring.response` by feel. No real content — just alternating colors and
/// big index numbers so it's obvious which page you're on.
///
/// Expected landing: response ∈ [0.25, 0.32]. Start at 0.28.
struct SlidingLoopPreviewHarness: View {
    private struct PreviewItem: Identifiable {
        let id: Int
        let color: Color
    }

    @State private var visibleIndex: Int = 0
    private let items: [PreviewItem] = (0..<20).map { i in
        PreviewItem(id: i, color: Color(
            hue: Double(i % 10) / 10.0,
            saturation: 0.7,
            brightness: 0.9
        ))
    }

    var body: some View {
        SlidingLoop(items: items, visibleIndex: $visibleIndex) { item, isVisible in
            ZStack {
                item.color.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("\(item.id)")
                        .font(.system(size: 140, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(isVisible ? "VISIBLE" : "…")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Text("idx: \(visibleIndex) / \(items.count - 1)")
                .font(.caption.monospaced())
                .padding(8)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
                .padding()
        }
    }
}

#Preview {
    SlidingLoopPreviewHarness()
}
#endif
```

- [ ] **Step 2: Build and run the preview on a simulator**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Verify visually in Xcode preview**

Open `MITReels/Components/SlidingLoopPreview.swift` in Xcode. Enable live preview (Canvas: Play button). In the live preview:
- Flick down — should snap to next page with no overshoot, ~280ms.
- Slow drag — should land at nearest page.
- Grab mid-settle — should follow finger instantly.

- [ ] **Step 4: Subjective tuning pass**

If the spring feels:
- **Too slow / sluggish** → edit `MITReels/Physics/SlidingLoopStateMachine.swift`, change `init(response: 0.28)` to `0.25`. Rebuild.
- **Too abrupt / instant** → change to `0.32`. Rebuild.
- **Just right** → leave at `0.28`.

Expected: you'll land somewhere in [0.25, 0.32]. Commit the final value.

- [ ] **Step 5: Commit the preview harness**

```bash
git add MITReels/Components/SlidingLoopPreview.swift
# If response value was changed during tuning, also:
git add MITReels/Physics/SlidingLoopStateMachine.swift
git commit -m "feat(ui): add SlidingLoopPreview harness, tune response to <value>"
```

---

# Phase D — DiscoverView integration and side cleanups

## Task 8: Integrate SlidingLoop into DiscoverView

Replaces the `ScrollView + LazyVStack + .scrollTargetBehavior(.paging)` block at `DiscoverView.swift:205-227` with `SlidingLoop`. Bridges `visibleIndex` (Int) to `visibleId` (String?) so existing `onChange(of: visibleId)` logic — haptic, soft-signal, engine advance, prefetch — keeps working unmodified.

**Files:**
- Modify: `MITReels/Views/DiscoverView.swift`

- [ ] **Step 1: Add `visibleIndex` state, derived from / writing to `visibleId`**

Edit `MITReels/Views/DiscoverView.swift`. Add a new `@State` property right after the `@SceneStorage("discoverVisibleId")` line (line 20 area):

```swift
    @SceneStorage("discoverVisibleId") private var visibleId: String?
    /// Bridge between SlidingLoop's Int binding and the String-keyed app state.
    /// visibleId remains the persisted source of truth; visibleIndex is derived.
    @State private var visibleIndex: Int = 0
```

- [ ] **Step 2: Replace the `feedContent` body**

Edit the `@ViewBuilder private var feedContent: some View` block (currently `DiscoverView.swift:192-231`). Replace the non-empty branch:

**Before** (the block starting with `} else { ScrollView(.vertical) {`):

```swift
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(displayLectures, id: \.youtubeId) { lecture in
                        ReelView(
                            lecture: lecture,
                            isVisible: visibleId == lecture.youtubeId,
                            isNearby: lecture.youtubeId == nextId,
                            autoplayEnabled: autoplayEnabled,
                            captionsEnabled: captionsEnabled,
                            onViewCourse: { tappedLecture in
                                navigateToLectureId = tappedLecture.youtubeId
                                navigateToCourse = tappedLecture.course
                            }
                        )
                        .containerRelativeFrame(.vertical)
                        .id(lecture.youtubeId)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $visibleId)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .vertical)
            .background(CarbonColor.reelBackground)
        }
```

**After:**

```swift
        } else {
            SlidingLoop(items: displayLectures, visibleIndex: $visibleIndex) { lecture, isVisible in
                ReelView(
                    lecture: lecture,
                    isVisible: isVisible,
                    isNearby: lecture.youtubeId == nextId,
                    autoplayEnabled: autoplayEnabled,
                    captionsEnabled: captionsEnabled,
                    onViewCourse: { tappedLecture in
                        navigateToLectureId = tappedLecture.youtubeId
                        navigateToCourse = tappedLecture.course
                    }
                )
            }
            .ignoresSafeArea(.container, edges: .vertical)
            .background(CarbonColor.reelBackground)
        }
```

- [ ] **Step 3: Add index ↔ id bridging**

At the end of the `.onChange(of: visibleId)` chain, add two new modifiers to sync the index binding and the id binding. Place them right after the existing `.onChange(of: visibleId) { ... }` block (ending around line 140):

```swift
        .onChange(of: visibleIndex) { old, new in
            guard new >= 0, new < displayLectures.count else { return }
            let newId = displayLectures[new].youtubeId
            if visibleId != newId {
                visibleId = newId
            }
        }
        .onChange(of: displayLectures.map(\.youtubeId)) { _, _ in
            // After bootstrap or buffer refresh, reconcile visibleIndex to
            // whatever visibleId points to (preserves SceneStorage restoration).
            if let vid = visibleId,
               let idx = displayLectures.firstIndex(where: { $0.youtubeId == vid }) {
                if visibleIndex != idx { visibleIndex = idx }
            } else if !displayLectures.isEmpty {
                visibleIndex = 0
            }
        }
```

- [ ] **Step 4: Update dislike-advance to use index math**

The existing dislike handler at `DiscoverView.swift:152-164` uses `withAnimation { visibleId = ... }` which depended on SwiftUI's native `scrollPosition` binding. Since `SlidingLoop` is driven by `$visibleIndex`, change the handler body to set `visibleIndex` directly.

**Before:**

```swift
        .onReceive(NotificationCenter.default.publisher(for: ReelView.dislikeAdvanceNotification)) { note in
            guard let dislikedId = note.object as? String, dislikedId == visibleId,
                  let idx = displayLectures.firstIndex(where: { $0.youtubeId == dislikedId }),
                  idx + 1 < displayLectures.count else { return }
            // Capture next ID synchronously before async engine mutation changes the array.
            let nextVideoId = displayLectures[idx + 1].youtubeId
            withAnimation { visibleId = nextVideoId }
            Task {
                await feedEngine.blockVideo(id: dislikedId)
                await feedEngine.refreshWeights(feedPrefs)
                await syncDisplay()
            }
        }
```

**After:**

```swift
        .onReceive(NotificationCenter.default.publisher(for: ReelView.dislikeAdvanceNotification)) { note in
            guard let dislikedId = note.object as? String, dislikedId == visibleId,
                  let idx = displayLectures.firstIndex(where: { $0.youtubeId == dislikedId }),
                  idx + 1 < displayLectures.count else { return }
            // Advance by index — SlidingLoop animates to the new index via its spring.
            visibleIndex = idx + 1
            Task {
                await feedEngine.blockVideo(id: dislikedId)
                await feedEngine.refreshWeights(feedPrefs)
                await syncDisplay()
            }
        }
```

- [ ] **Step 5: Update video-ended advance similarly**

**Before** (`DiscoverView.swift:146-151`):

```swift
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoEndedNotification)) { note in
            guard let endedId = note.object as? String, endedId == visibleId,
                  let idx = displayLectures.firstIndex(where: { $0.youtubeId == endedId }),
                  idx + 1 < displayLectures.count else { return }
            withAnimation { visibleId = displayLectures[idx + 1].youtubeId }
        }
```

**After:**

```swift
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoEndedNotification)) { note in
            guard let endedId = note.object as? String, endedId == visibleId,
                  let idx = displayLectures.firstIndex(where: { $0.youtubeId == endedId }),
                  idx + 1 < displayLectures.count else { return }
            visibleIndex = idx + 1
        }
```

- [ ] **Step 6: Update the video-unavailable advance similarly**

**Before** (`DiscoverView.swift:172-187`, the `.onReceive` for `videoUnavailableNotification`):

```swift
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoUnavailableNotification)) { note in
            guard let videoId = note.object as? String else { return }
            if videoId == visibleId,
               let idx = displayLectures.firstIndex(where: { $0.youtubeId == videoId }) {
                let next = idx + 1 < displayLectures.count ? idx + 1
                         : idx - 1 >= 0 ? idx - 1 : nil
                if let next {
                    withAnimation { visibleId = displayLectures[next].youtubeId }
                }
            }
            // Route through engine so syncDisplay stays the single source of truth
            Task {
                await feedEngine.blockVideo(id: videoId)
                await syncDisplay()
            }
        }
```

**After:**

```swift
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoUnavailableNotification)) { note in
            guard let videoId = note.object as? String else { return }
            if videoId == visibleId,
               let idx = displayLectures.firstIndex(where: { $0.youtubeId == videoId }) {
                let next = idx + 1 < displayLectures.count ? idx + 1
                         : idx - 1 >= 0 ? idx - 1 : nil
                if let next {
                    visibleIndex = next
                }
            }
            Task {
                await feedEngine.blockVideo(id: videoId)
                await syncDisplay()
            }
        }
```

- [ ] **Step 7: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: BUILD SUCCEEDED. If there are errors:
- "Cannot find 'visibleIndex' in scope" → Step 1 was not done.
- `Lecture` already conforms to `Identifiable` via SwiftData's `@Model` macro (which synthesizes `id: PersistentIdentifier`), so the `Item: Identifiable` constraint on `SlidingLoop` is satisfied automatically. Do NOT add a manual `extension Lecture: Identifiable` — it will conflict with the macro-synthesized conformance.
- If you see "cannot convert `[Lecture]` to expected argument type `[some Identifiable]`" — check that `@Query private var lectures: [Lecture]` still compiles and that nothing in `SlidingLoop`'s signature is over-constrained.

- [ ] **Step 8: Run a quick smoke test on the simulator**

```bash
flowdeck run -S "iPhone 16 Pro"
```

Expected: app launches, reels feed appears, swipe advances with spring physics. No crashes, no blank reels.

- [ ] **Step 9: Commit**

```bash
git add MITReels/Views/DiscoverView.swift
git commit -m "feat(discover): swap native paging for SlidingLoop physics"
```

---

## Task 9: Side cleanups — 150ms sleep in ReelView

Remove the `Task.sleep(for: .milliseconds(150))` in `ReelView.swift` that was compensating for scroll stutter. With the spring-driven scroll, the compensation is no longer needed.

**Files:**
- Modify: `MITReels/Views/ReelView.swift`

- [ ] **Step 1: Remove the 150ms sleep**

Edit `MITReels/Views/ReelView.swift` lines 297-303.

**Before:**

```swift
                    .onChange(of: isVideoLoading) { _, loading in
                        if loading { showVideoLayer = false }
                        // Only auto-reveal when loading finishes AND autoplay is on.
                        // For autoplay-off, the iframe shows a black spinner until
                        // the user taps play — keep showing the thumbnail instead.
                        if !loading && !hasVideoError && isVisible && autoplayEnabled {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(150))
                                guard isVisible, !showVideoLayer else { return }
                                withAnimation(.easeIn(duration: 0.15)) { showVideoLayer = true }
                            }
                        }
                    }
```

**After:**

```swift
                    .onChange(of: isVideoLoading) { _, loading in
                        if loading { showVideoLayer = false }
                        // Only auto-reveal when loading finishes AND autoplay is on.
                        // For autoplay-off, the iframe shows a black spinner until
                        // the user taps play — keep showing the thumbnail instead.
                        if !loading && !hasVideoError && isVisible && autoplayEnabled {
                            withAnimation(.easeIn(duration: 0.15)) { showVideoLayer = true }
                        }
                    }
```

- [ ] **Step 2: Build**

```bash
flowdeck build -S "iPhone 16 Pro"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Smoke test on simulator — autoplay reveal**

```bash
flowdeck run -S "iPhone 16 Pro"
```

Wait for app launch, let a reel load with autoplay on. Expected: video layer reveals immediately when loading finishes, no visible flash of black iframe background.

If you *do* see a flash of black, the 150ms sleep was masking a real issue — add the sleep back as a 50ms reveal delay and note it in the commit. Don't just revert the whole change; the scroll-side latency is the underlying cause and we've removed that.

- [ ] **Step 4: Commit**

```bash
git add MITReels/Views/ReelView.swift
git commit -m "refactor(reel): remove 150ms video reveal sleep (scroll no longer stutters)"
```

---

## Phase D Gate — manual simulator verification

- [ ] **Step 1: Full build + install + launch**

```bash
flowdeck run -S "iPhone 16 Pro"
```

- [ ] **Step 2: Manual verification checklist**

With the app running, test each item. For each, mark it ✅ or ❌. Any ❌ must be fixed before Phase E starts.

- [ ] Slow drag advances to nearest page with no overshoot
- [ ] Fast flick up advances exactly one page
- [ ] Fast flick down advances exactly one page backward (or stays at 0 at top)
- [ ] Grab mid-settle: finger takes over immediately, no "fight"
- [ ] Long hold at a page: no drift, no micro-movement
- [ ] Haptic fires on each page change
- [ ] Thumbs-up on a reel: reel stays, no advance
- [ ] Thumbs-down on a reel: advances to next with spring animation
- [ ] Video ends (wait for short video to finish): auto-advances to next with spring
- [ ] FeedEngine advance: after 5+ scrolls, check console logs for `feedEngine.advance()` calls (use `flowdeck logs` in another terminal)
- [ ] Thumbnail prefetch: no blank thumbs on reels N+1, N+2, N+3
- [ ] Expand/collapse metadata: tap the title line, navigation pushes CourseReelsView
- [ ] Source filter: shake phone, sheet appears, toggling a source rebuilds feed
- [ ] Split View (iPad only, optional): resize scene, reels re-snap cleanly
- [ ] Rotation (iPad only, optional): rotate device, reels re-snap to current index
- [ ] Background → foreground: backgrounds app, re-foregrounds, still on same reel

- [ ] **Step 3: Run the existing Maestro stress scroll flow**

```bash
flowdeck run -S "iPhone 16 Pro" &
sleep 10
maestro test /Users/s3nik/Desktop/mit-ocw-reels/.maestro/flow_stress_scroll_test.yaml
```

Expected: flow completes without crash. Screenshot outputs go to `~/.maestro/tests/`. If any assertion fails or the app crashes, investigate the offending phase.

- [ ] **Step 4: Commit gate marker**

```bash
git commit --allow-empty -m "chore: Phase D complete — SlidingLoop integrated in DiscoverView"
```

---

# Phase E — Measurement and merge

## Task 10: Instruments profiling and final verification

60-second Time Profiler session to confirm no SwiftUI view-graph passes on the spring tick and no dropped frames during scroll.

**Files:** none (measurement only)

- [ ] **Step 1: Build Release configuration**

```bash
flowdeck build -S "iPhone 16 Pro" -C Release
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Launch app on simulator**

```bash
flowdeck run -S "iPhone 16 Pro" -C Release
```

- [ ] **Step 3: Attach Instruments Time Profiler**

Open Instruments.app manually:

```bash
open -a Instruments
```

- Choose **Time Profiler** template.
- Target: the running MITReels simulator instance.
- Record for 60 seconds while you scroll continuously: slow drags, fast flicks, mid-settle grabs.
- Stop.

- [ ] **Step 4: Analyze — check for SwiftUI view-graph passes on tick**

In the Time Profiler call tree, filter on `AG::Graph` (SwiftUI's view graph). Expected: no `AG::Graph::update_attribute` calls happening inside `DisplayLinkDriver.handleTick` or `SlidingLoopHostScrollView.handleTick`. If there are, something in our code path is triggering a SwiftUI invalidation on every tick — investigate which `@State` / `@Binding` is being written.

- [ ] **Step 5: Check for dropped frames**

In Instruments, use the **Core Animation FPS** track (or enable frame drop detection in the profiler). Expected: sustained 60–120 fps during flicks and settles. Any drop below 60 fps is a regression.

- [ ] **Step 6: Capture before/after settle-time measurement**

Using Instruments' time ruler, measure the duration from finger-lift to settled state. Expected: ≤ 320ms (response 0.28 + margin).

If any of these fail, stop and investigate. Do not proceed to merge.

- [ ] **Step 7: Run full test suite one final time**

```bash
flowdeck test -S "iPhone 16 Pro"
```

Expected: all tests pass.

- [ ] **Step 8: Create a PR**

```bash
cd /Users/s3nik/Desktop/mit-ocw-reels
git push -u origin feature/sliding-loop-physics
gh pr create --title "SlidingLoop — physics-driven reels scroll" --body "$(cat <<'EOF'
## Summary
- Replace SwiftUI native paging with custom UIKit-hosted `SlidingLoop` driven by critically-damped spring physics
- Four pure-Swift primitives (`Spring`, `VelocityTracker`, `DisplayLinkDriver`, `SnapTarget`) + state machine, all unit tested
- Delete 150ms `Task.sleep` video reveal compensation (scroll no longer stutters)

## Test plan
- [x] All physics unit tests pass (100% coverage on primitives)
- [x] State machine transitions tested directly
- [x] Manual simulator verification (Phase D checklist)
- [x] Maestro stress scroll flow completes without crash
- [x] Instruments Time Profiler shows no SwiftUI view-graph passes on tick
- [x] Settle time ≤ 320ms after finger lift
- [x] No visible overshoot (critical damping guarantee)

Spec: `docs/superpowers/specs/2026-04-13-sliding-loop-physics-design.md`
Plan: `docs/superpowers/plans/2026-04-13-sliding-loop-physics-implementation.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

- [ ] **Step 9: Commit Phase E completion marker**

```bash
git commit --allow-empty -m "chore: Phase E complete — measured, verified, PR opened"
```

---

## Success Criteria

All of the following must be true before merge:

- [ ] All unit tests pass (100% coverage on `Spring`, `VelocityTracker`, `DisplayLinkDriver`, `SnapTarget`, `SlidingLoopStateMachine`)
- [ ] Manual FlowDeck verification checklist (Phase D) is 100% ✅
- [ ] Maestro stress scroll flow completes without crash
- [ ] Instruments Time Profiler shows no SwiftUI view-graph passes on tick
- [ ] Settle time ≤ 320ms measured via Instruments
- [ ] Zero visible overshoot on any scroll
- [ ] Full test suite green
- [ ] PR description accurately reflects shipped work
