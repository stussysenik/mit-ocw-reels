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
        let proxy = DisplayLinkProxy(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
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
