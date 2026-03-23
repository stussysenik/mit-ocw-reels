import Testing
@testable import MITReels

/// Verify YouTubeAPIClient URL construction, quota tracking, and error handling.
struct YouTubeAPIClientTests {

    @Test func clientInitializesWithZeroQuota() async {
        let client = YouTubeAPIClient(apiKey: "test-key")
        let used = await client.quotaUsed
        #expect(used == 0)
    }

    @Test func quotaRemainingStartsAtDailyLimit() async {
        let client = YouTubeAPIClient(apiKey: "test-key")
        let remaining = await client.quotaRemaining
        #expect(remaining == 10_000)
    }

    @Test func emptyApiKeyThrowsNoAPIKeyError() async {
        let client = YouTubeAPIClient(apiKey: "")
        do {
            _ = try await client.fetchPlaylists(channelId: "UCtest")
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is YouTubeAPIError)
        }
    }

    @Test func youtubePlaylistModelFields() {
        let playlist = YouTubePlaylist(id: "PLtest", title: "Test Playlist", itemCount: 10)
        #expect(playlist.id == "PLtest")
        #expect(playlist.title == "Test Playlist")
        #expect(playlist.itemCount == 10)
    }

    @Test func youtubeVideoModelFields() {
        let video = YouTubeVideo(videoId: "abc123def45", title: "Lecture 1", playlistId: "PLtest", playlistTitle: "CS229")
        #expect(video.videoId == "abc123def45")
        #expect(video.title == "Lecture 1")
        #expect(video.playlistTitle == "CS229")
    }
}
