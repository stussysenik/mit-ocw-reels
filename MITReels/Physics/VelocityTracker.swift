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

    /// Scalar velocity seeded before samples arrive — used to model the
    /// Origami "catch the moving page" handoff, where POPBouncyPatch.mm
    /// writes `spring.velocity` directly mid-flight rather than
    /// reconstructing velocity from position deltas. Consulted only while
    /// the rolling window has fewer than 2 samples; real touch samples
    /// always win once accumulated.
    private var pendingVelocity: Double?

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

    /// Current velocity in points per second. Reading order:
    /// 1. If ≥2 samples exist, compute from the rolling window
    /// 2. Otherwise, return the seeded pending velocity if present
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

    /// Seed the tracker with a scalar residual velocity for mid-settle
    /// handoff. Called by `SlidingLoopStateMachine.willBeginDragging()`
    /// with the spring's current velocity so the user's finger catches
    /// the page in motion rather than resetting it to a dead stop.
    mutating func seedVelocity(_ v: Double) {
        pendingVelocity = v
    }

    mutating func reset() {
        samples.removeAll()
        pendingVelocity = nil
    }
}
