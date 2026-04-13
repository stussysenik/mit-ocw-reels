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
    /// bounded time. The bound here is the *sub-pixel* settle threshold
    /// (abs(target - position) < 0.5 on a 1000-unit travel → 0.05% accuracy),
    /// not the user-visible settle time which is much shorter.
    ///
    /// Analytical: critical damping gives x(t) = A·(1+ωt)·e^(-ωt) with
    /// ω = 2π/0.28 ≈ 22.44 rad/s. Solving (1+u)·e^(-u) < 5e-4 yields
    /// u ≈ 10.05 → t ≈ 0.448s ≈ 27 frames. Semi-implicit Euler at dt=1/60
    /// adds ~60% error on top, landing near 45 frames. 50 is a safe ceiling.
    ///
    /// Real user-facing scroll settles visually in ~15-20 frames because
    /// the eye doesn't see sub-pixel motion — the display link stops writing
    /// contentOffset once isSettled triggers, but the motion was already
    /// invisible well before that.
    @Test func settlesWithinBudget() {
        var spring = Spring(response: 0.28, position: 0, velocity: 0, target: 1000)
        let dt = 1.0 / 60.0
        var steps = 0
        while !spring.isSettled && steps < 200 {
            spring = spring.stepped(dt: dt)
            steps += 1
        }
        #expect(spring.isSettled)
        #expect(steps <= 50)
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
