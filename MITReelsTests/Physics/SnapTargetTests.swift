import Testing
@testable import MITReels

/// Tests the snap-to-index policy. Pure function, no state.
///
/// Single-step policy: a flick advances by at most one page in the velocity
/// direction. No inertial multi-page projection — that's where Apple's default
/// paging feels mushy.
struct SnapTargetTests {
    @Test func zeroVelocityBelowMidpointRoundsDown() {
        let idx = SnapTarget.nextIndex(
            from: 450, velocity: 0, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 0)
    }

    @Test func zeroVelocityAboveMidpointRoundsUp() {
        let idx = SnapTarget.nextIndex(
            from: 551, velocity: 0, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 1)
    }

    @Test func forwardFlickAdvancesOneFromCurrent() {
        // offset=200, round(200/1000)=0, velocity above threshold → 0 + 1 = 1
        let idx = SnapTarget.nextIndex(
            from: 200, velocity: 501, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 1)
    }

    @Test func backwardFlickClampsAtZero() {
        // offset=200, round(200/1000)=0, backward flick → -1, clamp → 0
        let idx = SnapTarget.nextIndex(
            from: 200, velocity: -501, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 0)
    }

    @Test func veryLargeForwardVelocityStillOnlyAdvancesOnePage() {
        // Even with huge velocity, single-step policy caps at +1.
        let idx = SnapTarget.nextIndex(
            from: 300, velocity: 10000, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 1)
    }

    @Test func clampsAtLastIndex() {
        // offset=9000, round(9000/1000)=9, +1 = 10, clamp → 9 (itemCount-1)
        let idx = SnapTarget.nextIndex(
            from: 9000, velocity: 1000, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 9)
    }

    @Test func belowFlickThresholdSnapsToNearest() {
        // |velocity| < flickThreshold (default 500) → use rounded position.
        let idx = SnapTarget.nextIndex(
            from: 400, velocity: 300, pageHeight: 1000, itemCount: 10
        )
        #expect(idx == 0) // round(0.4) = 0
    }

    @Test func emptyItemCountReturnsZero() {
        let idx = SnapTarget.nextIndex(
            from: 0, velocity: 0, pageHeight: 1000, itemCount: 0
        )
        #expect(idx == 0)
    }

    @Test func zeroPageHeightReturnsZero() {
        let idx = SnapTarget.nextIndex(
            from: 100, velocity: 100, pageHeight: 0, itemCount: 10
        )
        #expect(idx == 0)
    }
}
