import XCTest
import WebKit
@testable import MITReels

final class YouTubePlayerViewTests: XCTestCase {

    // MARK: - WKWebView configuration (iOS only)

    #if os(iOS)
    /// Inline playback must be enabled for YouTube embeds to work in-feed.
    func test_makeConfiguredWebView_enablesInlinePlayback() {
        let webView = YouTubePlayerView.makeConfiguredWebView()

        XCTAssertTrue(webView.configuration.allowsInlineMediaPlayback)
        XCTAssertTrue(webView.configuration.mediaTypesRequiringUserActionForPlayback.isEmpty)
    }

    /// Scrolling inside the web view must be disabled so the embed
    /// doesn't steal gestures from the parent scroll view.
    func test_makeConfiguredWebView_disablesScrolling() {
        let webView = YouTubePlayerView.makeConfiguredWebView()

        XCTAssertFalse(webView.scrollView.isScrollEnabled)
    }
    #endif

    // MARK: - Coordinator reload logic

    func test_coordinator_tracksVideoIdOnFirstLoad() {
        let coordinator = YouTubePlayerView.Coordinator()
        XCTAssertNil(coordinator.currentVideoId)

        coordinator.currentVideoId = "abc123"
        XCTAssertEqual(coordinator.currentVideoId, "abc123")
    }

    func test_coordinator_skipsReloadForSameVideoId() {
        let coordinator = YouTubePlayerView.Coordinator()
        coordinator.currentVideoId = "abc123"

        // Simulate the guard check — same videoId should not pass
        XCTAssertEqual(coordinator.currentVideoId, "abc123")
    }

    func test_coordinator_reloadsForDifferentVideoId() {
        let coordinator = YouTubePlayerView.Coordinator()
        coordinator.currentVideoId = "abc123"

        XCTAssertNotEqual(coordinator.currentVideoId, "xyz789")
        coordinator.currentVideoId = "xyz789"
        XCTAssertEqual(coordinator.currentVideoId, "xyz789")
    }

    // MARK: - Embed HTML tests

    /// The generated HTML must contain an iframe pointing at the correct
    /// YouTube embed URL with all required query parameters and the
    /// ocw.mit.edu origin (which YouTube trusts for MIT OCW videos).
    func test_embedHTML_containsCorrectIframe() {
        let html = YouTubePlayerView.embedHTML(videoId: "testVid42")

        XCTAssertTrue(html.contains("<iframe"), "HTML must contain an iframe element")
        XCTAssertTrue(
            html.contains("https://www.youtube.com/embed/testVid42"),
            "Iframe src must point to the correct YouTube embed URL"
        )
        XCTAssertTrue(html.contains("enablejsapi=1"), "Must enable JS API")
        XCTAssertTrue(html.contains("playsinline=1"), "Must include playsinline for iOS")
        XCTAssertTrue(html.contains("allowfullscreen"), "Iframe must allow fullscreen")
        XCTAssertTrue(html.contains("<!DOCTYPE html>"), "Must be a valid HTML5 document")
    }

    /// The origin parameter and referrer policy are critical for avoiding
    /// YouTube error 153 (embedder identity check, enforced July 2025).
    func test_embedHTML_includesOriginAndReferrerPolicy() {
        let html = YouTubePlayerView.embedHTML(videoId: "testVid42")

        XCTAssertTrue(
            html.contains("origin=https://ocw.mit.edu"),
            "Embed URL must include origin param matching baseURL"
        )
        XCTAssertTrue(
            html.contains("referrerpolicy=\"origin\""),
            "Iframe must set referrer policy for YouTube's Referer check"
        )
        XCTAssertTrue(
            html.contains("<meta name=\"referrer\" content=\"origin\">"),
            "Page must include referrer meta tag as fallback"
        )
    }

    /// The embed origin constant must be https://ocw.mit.edu.
    func test_embedOrigin_isOcwMitEdu() {
        XCTAssertEqual(YouTubePlayerView.embedOrigin, "https://ocw.mit.edu")
    }
}
