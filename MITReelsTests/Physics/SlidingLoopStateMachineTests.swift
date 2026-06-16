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
        // Drive until settled. Hard cap at 200 steps to avoid infinite loop.
        var steps = 0
        var settledIndex: Int? = nil
        while settledIndex == nil && steps < 200 {
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

    // MARK: - Velocity Handoff (Origami "catch the moving page")

    /// Mid-settle grab must carry the spring's residual velocity into
    /// the new drag. Without handoff, `willBeginDragging` resets the
    /// tracker and a subsequent `willEndDragging` with no fresh samples
    /// reads velocity = 0, which snaps back to the current page instead
    /// of completing the in-flight motion. With the scalar seed (Origami
    /// POPBouncyPatch.mm:144-152 pattern) the tracker carries the spring
    /// velocity across the Settling → Dragging transition.
    @Test func midSettleGrabPreservesSpringVelocity() {
        var m = makeMachine()
        // 1. Fling forward to build up spring velocity.
        m.willBeginDragging()
        m.didScroll(offset: 0, at: 0.0)
        m.didScroll(offset: 20, at: 0.016)
        m.didScroll(offset: 40, at: 0.032)
        _ = m.willEndDragging(offset: 40)  // velocity > flickThreshold
        // Advance one frame — spring is now settling toward page 1 (1000).
        _ = m.tick(dt: 1.0 / 60.0)
        // Sanity: the spring should now be carrying forward velocity.
        #expect(m.spring.velocity > 0)

        // 2. User grabs mid-settle with a single tiny position update.
        m.willBeginDragging()
        // 3. User lifts immediately with one sample — not enough for the
        //    rolling window, so the tracker must fall through to the seed.
        let target = m.willEndDragging(offset: 41)
        // The seeded forward velocity should drive a flick decision to
        // page 1 (target = 1000), not a snap back to page 0.
        #expect(target == 1000)
    }

    /// Grabbing from `.idle` (not mid-settle) seeds 0 — there is no
    /// residual to inherit because nothing was moving.
    @Test func grabFromRestDoesNotInventVelocity() {
        var m = makeMachine()
        m.willBeginDragging()  // from .idle
        let target = m.willEndDragging(offset: 0)
        #expect(target == 0)  // settles to current page, not a phantom flick
    }

    // MARK: - Frame-rate-independent settling (loop-engine spec)

    /// Drives one machine through a flick using the supplied per-tick frame
    /// delta, sampling the in-flight content offset on every `nth` tick (only
    /// while still settling — the settle frame snaps to target and is reported
    /// separately). Returns the settle index, the exact final offset, and the
    /// pre-settle trajectory samples.
    private func runFlick(dt: Double, sampleEveryNthTick nth: Int)
        -> (index: Int, finalOffset: Double, samples: [Double]) {
        var m = makeMachine()
        m.willBeginDragging()
        m.didScroll(offset: 0, at: 0.0)
        m.didScroll(offset: 20, at: 0.016)
        m.didScroll(offset: 40, at: 0.032)
        _ = m.willEndDragging(offset: 40)  // forward flick → target page 1 (1000)

        var samples: [Double] = []
        var index: Int? = nil
        var finalOffset = 40.0
        var ticks = 0
        while index == nil && ticks < 8000 {
            let r = m.tick(dt: dt)
            ticks += 1
            if let s = r.settledIndex {
                index = s
                finalOffset = r.offset
                break
            }
            if ticks % nth == 0 { samples.append(r.offset) }
        }
        return (index ?? -1, finalOffset, samples)
    }

    /// The headline determinism guarantee: the same flick must produce the same
    /// settled index, the same final offset *to the pixel*, and an identical
    /// trajectory at matched elapsed times, whether the display runs at 60 Hz
    /// or 120 Hz. With variable-`dt` semi-implicit Euler the trajectories
    /// diverge; fixed-timestep integration makes position a pure function of
    /// elapsed time. We sample the 120 Hz run every other tick so both sample
    /// sequences land on the same 1/60 s grid.
    @Test func identicalFlickSettlesIdenticallyAt60And120Hz() {
        let a = runFlick(dt: 1.0 / 60.0, sampleEveryNthTick: 1)
        let b = runFlick(dt: 1.0 / 120.0, sampleEveryNthTick: 2)

        #expect(a.index == b.index)
        #expect(a.finalOffset == b.finalOffset)  // exact rest position, to the pixel

        let n = min(a.samples.count, b.samples.count)
        #expect(n >= 8)  // enough overlap to be meaningful
        for i in 0..<n {
            #expect(a.samples[i] == b.samples[i])
        }
    }

    /// A frame stutter must not change the outcome or visibly glitch the
    /// trajectory. We compare a smooth 60 Hz settle against the extreme case of
    /// a 1/12 s delta on *every* tick (a sustained hitch). Sampling the fine
    /// run every 5th tick aligns both on the same 1/12 s grid. Under variable
    /// `dt` the coarse delta overshoots wildly (semi-implicit Euler is unstable
    /// at large steps); fixed-timestep integration breaks each delta into safe
    /// quanta, so both trajectories match.
    @Test func largeFrameStutterMatchesSmoothSettle() {
        let smooth = runFlick(dt: 1.0 / 60.0, sampleEveryNthTick: 5)
        let stutter = runFlick(dt: 1.0 / 12.0, sampleEveryNthTick: 1)

        #expect(smooth.index == stutter.index)
        #expect(smooth.finalOffset == stutter.finalOffset)

        let n = min(smooth.samples.count, stutter.samples.count)
        #expect(n >= 3)
        for i in 0..<n {
            #expect(smooth.samples[i] == stutter.samples[i])
        }
    }

    /// After settling to `targetIndex`, an idle tick must report that exact
    /// index — never an off-by-one from re-deriving it by rounding the position.
    @Test func idleIndexAgreesWithSettleTarget() {
        var m = makeMachine()
        m.willBeginDragging()
        m.didScroll(offset: 0, at: 0.0)
        m.didScroll(offset: 20, at: 0.016)
        m.didScroll(offset: 40, at: 0.032)
        _ = m.willEndDragging(offset: 40)  // → target page 1

        var index: Int? = nil
        var steps = 0
        while index == nil && steps < 2000 {
            index = m.tick(dt: 1.0 / 120.0).settledIndex
            steps += 1
        }
        #expect(index == 1)
        #expect(m.state == .idle)

        // A late idle tick reports the same index and the exact rest offset.
        let again = m.tick(dt: 1.0 / 60.0)
        #expect(again.settledIndex == 1)
        #expect(again.offset == 1000)
    }
}
