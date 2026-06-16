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

    /// Fixed integration timestep in seconds. Settling steps the spring in
    /// these quanta regardless of the `CADisplayLink` frame delta, so the
    /// trajectory is a pure function of elapsed time — identical at 60 Hz and
    /// 120 Hz, and stable through a frame stutter. 1/240 s is well inside the
    /// semi-implicit-Euler stability bound for the default `response`.
    private static let fixedStep: Double = 1.0 / 240.0

    /// Carries the sub-quantum remainder of frame deltas between ticks so the
    /// quanta stepped track wall-clock elapsed time exactly (no drift).
    private var accumulator: Double = 0

    /// The index the loop last settled on. Idle ticks report this directly
    /// rather than re-deriving an index by rounding the position, which removes
    /// the off-by-one at page boundaries.
    private(set) var settledIndex: Int = 0

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
    /// or from `.settling` (mid-settle interrupt). On a mid-settle interrupt
    /// the spring's residual velocity is handed off to the velocity tracker
    /// as a scalar seed (Origami `POPBouncyPatch.mm:144-152` pattern), so
    /// the subsequent `willEndDragging` reads the real motion the user's
    /// finger caught instead of zero. Without this, grabbing a moving page
    /// snaps it to a dead stop — the "catch the moving page" interaction
    /// the spring physics were designed for simply doesn't work.
    mutating func willBeginDragging() {
        let residual: Double = {
            if case .settling = state { return spring.velocity }
            return 0
        }()
        velocityTracker.reset()
        velocityTracker.seedVelocity(residual)
        accumulator = 0
        state = .dragging
    }

    /// Forwarded from `scrollViewWillEndDragging`. Computes target and returns
    /// the target offset in points, which the caller should use to prime
    /// `spring.target` (already done inside) and to anchor the native
    /// `targetContentOffset.pointee`.
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
        spring.target = targetY  // always an exact integer multiple of pageHeight
        accumulator = 0          // fresh settle: no carry-over from a prior run
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
            // Idle: report the stored settle index, not a re-rounded position,
            // so the idle index can never disagree with the settle target.
            return (spring.position, settledIndex)
        }
        // Integrate the spring in fixed quanta, carrying the remainder. The
        // epsilon absorbs float-accumulation error so clean refresh rates
        // (60 Hz → 4 quanta/tick, 120 Hz → 2) extract an identical, stable
        // count per matched elapsed time.
        let epsilon = Self.fixedStep * 1e-3
        accumulator += dt
        while accumulator + epsilon >= Self.fixedStep {
            accumulator -= Self.fixedStep
            spring = spring.stepped(dt: Self.fixedStep)
            if spring.isSettled {
                let final = spring.target  // exact: targetIndex * pageHeight
                spring.position = final
                spring.velocity = 0
                accumulator = 0
                settledIndex = targetIndex
                state = .idle
                return (final, targetIndex)
            }
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
        accumulator = 0
        settledIndex = index
        state = .idle
    }
}
