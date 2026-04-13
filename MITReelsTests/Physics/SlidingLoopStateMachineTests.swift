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
}
