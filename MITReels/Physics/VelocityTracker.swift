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
