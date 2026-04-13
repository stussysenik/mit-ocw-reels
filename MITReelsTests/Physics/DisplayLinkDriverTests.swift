import Testing
import Foundation
@testable import MITReels

/// Tests the CADisplayLink wrapper.
///
/// We can't easily test the actual tick timing in unit tests (no real display),
/// so we focus on lifecycle: start/stop state, idempotence, and that the
/// onTick closure is fully wired through.
struct DisplayLinkDriverTests {
    @Test @MainActor func initiallyNotRunning() {
        let driver = DisplayLinkDriver()
        #expect(!driver.isRunning)
    }

    @Test @MainActor func startSetsIsRunning() {
        let driver = DisplayLinkDriver()
        driver.start()
        #expect(driver.isRunning)
        driver.stop()
    }

    @Test @MainActor func stopResetsIsRunning() {
        let driver = DisplayLinkDriver()
        driver.start()
        driver.stop()
        #expect(!driver.isRunning)
    }

    @Test @MainActor func doubleStartIsIdempotent() {
        let driver = DisplayLinkDriver()
        driver.start()
        driver.start()
        #expect(driver.isRunning)
        driver.stop()
    }

    @Test @MainActor func doubleStopIsIdempotent() {
        let driver = DisplayLinkDriver()
        driver.stop()
        driver.stop()
        #expect(!driver.isRunning)
    }

    /// Verifies the closure wiring: when the display link fires, onTick is
    /// invoked with a positive dt. We wait up to 300ms for at least one tick.
    @Test func tickFiresOnTickClosure() async {
        let expectation = TickExpectation()
        let driver = await MainActor.run { () -> DisplayLinkDriver in
            let d = DisplayLinkDriver()
            d.onTick = { dt in
                Task { await expectation.fulfill(with: dt) }
            }
            d.start()
            return d
        }
        try? await Task.sleep(for: .milliseconds(300))
        await MainActor.run { driver.stop() }
        let recorded = await expectation.dts
        #expect(!recorded.isEmpty, "Expected at least one tick within 300ms")
        if let first = recorded.first {
            #expect(first > 0 && first < 0.1, "dt should be plausible frame time")
        }
    }

    actor TickExpectation {
        var dts: [CFTimeInterval] = []
        func fulfill(with dt: CFTimeInterval) { dts.append(dt) }
    }
}
