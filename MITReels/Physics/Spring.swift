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
