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
