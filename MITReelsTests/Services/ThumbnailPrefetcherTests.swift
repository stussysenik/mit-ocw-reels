import Testing
import Foundation
@testable import MITReels

@MainActor
struct ThumbnailPrefetcherTests {

    @Test func countLimitIs64() {
        #expect(ThumbnailPrefetcher.shared.cacheCountLimit == 64)
    }

    @Test func idsAroundReturnsWindowClampedToBounds() {
        let ids = (0..<50).map { "id\($0)" }
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 10, window: 25, in: ids)
        // Span is [10-25 ... 10+25] clamped to [0, 49] → indices 0...35.
        #expect(window.first == "id0")
        #expect(window.last == "id35")
        #expect(window.count == 36)
    }

    @Test func idsAroundHandlesEmptyArray() {
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 0, window: 25, in: [])
        #expect(window.isEmpty)
    }

    @Test func idsAroundHandlesCenterPastEnd() {
        let ids = ["a", "b", "c"]
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 100, window: 25, in: ids)
        #expect(window.isEmpty)
    }

    @Test func idsAroundCenterWithFullWindowAvailable() {
        let ids = (0..<100).map { "id\($0)" }
        let window = ThumbnailPrefetcher.idsAround(centerIndex: 50, window: 25, in: ids)
        #expect(window.first == "id25")
        #expect(window.last == "id75")
        #expect(window.count == 51) // 25 + 1 (center) + 25
    }
}
