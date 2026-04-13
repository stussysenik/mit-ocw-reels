import Testing
import Foundation
@testable import MITReels

/// Unit tests for `ReelPlayerPool`. These cover the slot-assignment state
/// machine logic — NOT the real WebView warm-up, which requires a live
/// `WKWebView` roundtrip through YouTube's iframe API and would be flaky
/// under CI. WebView interactions are verified manually via the
/// `SlidingLoopPreview` harness and Instruments/Maestro in Phase 6.
@MainActor
struct ReelPlayerPoolTests {

    private func makeLectures(_ count: Int) -> [Lecture] {
        // Lecture is a SwiftData @Model — its init takes named params.
        // No ModelContainer needed for plain instance creation; we never
        // `context.insert` these instances.
        (0..<count).map { i in
            Lecture(
                title: "Lecture \(i)",
                youtubeId: String(format: "vid%08d", i),
                courseNumber: "0.0",
                courseName: "Test",
                department: ""
            )
        }
    }

    @Test func shiftAssignsSlotsAroundCenter() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)

        pool.shift(toCenterIndex: 10, in: lectures)

        #expect(pool.lectureId(forRelativePosition: -2) == "vid00000008")
        #expect(pool.lectureId(forRelativePosition: -1) == "vid00000009")
        #expect(pool.lectureId(forRelativePosition:  0) == "vid00000010")
        #expect(pool.lectureId(forRelativePosition:  1) == "vid00000011")
        #expect(pool.lectureId(forRelativePosition:  2) == "vid00000012")
    }

    @Test func shiftForwardByOneRecyclesFarBack() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)

        pool.shift(toCenterIndex: 10, in: lectures)
        pool.shift(toCenterIndex: 11, in: lectures)

        #expect(pool.lectureId(forRelativePosition: -2) == "vid00000009")
        #expect(pool.lectureId(forRelativePosition:  2) == "vid00000013")
    }

    @Test func shiftBackwardReusesCachedAssignments() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)

        pool.shift(toCenterIndex: 10, in: lectures)
        pool.shift(toCenterIndex: 11, in: lectures)
        pool.shift(toCenterIndex: 10, in: lectures)  // backward

        #expect(pool.lectureId(forRelativePosition: 0) == "vid00000010")
    }

    @Test func shiftAtBoundaryLeavesSlotsEmpty() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(5)

        pool.shift(toCenterIndex: 0, in: lectures)
        #expect(pool.lectureId(forRelativePosition: -2) == nil)
        #expect(pool.lectureId(forRelativePosition: -1) == nil)
        #expect(pool.lectureId(forRelativePosition:  0) == "vid00000000")
    }

    @Test func handleMemoryPressureRecyclesFarSlots() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let lectures = makeLectures(20)
        pool.shift(toCenterIndex: 10, in: lectures)

        pool.handleMemoryPressure()

        // Far slots cleared; near slots retained.
        #expect(pool.lectureId(forRelativePosition: -2) == nil)
        #expect(pool.lectureId(forRelativePosition:  2) == nil)
        #expect(pool.lectureId(forRelativePosition: -1) == "vid00000009")
        #expect(pool.lectureId(forRelativePosition:  1) == "vid00000011")
    }

    @Test func playerViewReturnsNilForOutOfRangePosition() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        #expect(pool.playerView(forRelativePosition: 3) == nil)
        #expect(pool.playerView(forRelativePosition: -3) == nil)
    }

    @Test func playerViewReturnsSameInstanceAcrossCalls() {
        let pool = ReelPlayerPool()
        pool.warmUp()
        let a = pool.playerView(forRelativePosition: 0)
        let b = pool.playerView(forRelativePosition: 0)
        #expect(a === b)
    }
}
