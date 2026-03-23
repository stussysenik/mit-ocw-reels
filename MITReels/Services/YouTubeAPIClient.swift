import Foundation

// MARK: - YouTube Data API v3 Response Models

/// A playlist from a YouTube channel.
struct YouTubePlaylist: Codable, Hashable {
    let id: String
    let title: String
    let itemCount: Int
}

/// A video item from a YouTube playlist.
struct YouTubeVideo: Codable, Hashable {
    let videoId: String
    let title: String
    let playlistId: String
    let playlistTitle: String
}

/// Generic paged response wrapper for YouTube API.
private struct YouTubePagedResponse<T: Decodable>: Decodable {
    let items: [T]
    let nextPageToken: String?
    let pageInfo: PageInfo?

    struct PageInfo: Decodable {
        let totalResults: Int
        let resultsPerPage: Int
    }
}

/// Raw playlist item from YouTube API.
private struct RawPlaylistItem: Decodable {
    let id: String
    let snippet: Snippet

    struct Snippet: Decodable {
        let title: String
        let description: String
        let position: Int
        let resourceId: ResourceId
        let thumbnails: Thumbnails?

        struct ResourceId: Decodable {
            let kind: String
            let videoId: String?
        }

        struct Thumbnails: Decodable {
            let medium: Thumbnail?
            let high: Thumbnail?
            let `default`: Thumbnail?

            struct Thumbnail: Decodable {
                let url: String
            }
        }
    }
}

/// Raw playlist from YouTube API channels/playlists list.
private struct RawPlaylist: Decodable {
    let id: String
    let snippet: Snippet
    let contentDetails: ContentDetails?

    struct Snippet: Decodable {
        let title: String
        let description: String
    }

    struct ContentDetails: Decodable {
        let itemCount: Int
    }
}

// MARK: - Errors

enum YouTubeAPIError: Error {
    case invalidURL
    case quotaExhausted
    case httpError(Int)
    case noAPIKey
    case decodingError(Error)
}

// MARK: - YouTubeAPIClient

/// On-device YouTube Data API v3 client for fetching university lecture playlists.
///
/// Actor-isolated for thread safety. Tracks daily quota usage.
/// Free tier: 10,000 units/day. playlistItems.list = 1 unit/request (50 items).
actor YouTubeAPIClient {

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://www.googleapis.com/youtube/v3"

    /// Daily quota consumed (resets at midnight Pacific).
    private(set) var quotaUsed: Int = 0

    /// Maximum daily quota for free tier.
    let dailyQuota = 10_000

    var quotaRemaining: Int { dailyQuota - quotaUsed }

    init(apiKey: String, maxConcurrency: Int = 4) {
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrency
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "MITReels/1.0 (iOS; educational)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetch all playlists from a YouTube channel.
    /// Cost: 1 unit per page (50 playlists/page).
    func fetchPlaylists(channelId: String, maxResults: Int = 50) async throws -> [YouTubePlaylist] {
        guard !apiKey.isEmpty else { throw YouTubeAPIError.noAPIKey }
        guard quotaRemaining > 0 else { throw YouTubeAPIError.quotaExhausted }

        var allPlaylists: [YouTubePlaylist] = []
        var pageToken: String? = nil

        repeat {
            var components = URLComponents(string: "\(baseURL)/playlists")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "channelId", value: channelId),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "key", value: apiKey),
            ]
            if let token = pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: token))
            }

            guard let url = components.url else { throw YouTubeAPIError.invalidURL }

            let response: YouTubePagedResponse<RawPlaylist> = try await fetchAndDecode(url)
            quotaUsed += 1

            let playlists = response.items.map { raw in
                YouTubePlaylist(
                    id: raw.id,
                    title: raw.snippet.title,
                    itemCount: raw.contentDetails?.itemCount ?? 0
                )
            }
            allPlaylists.append(contentsOf: playlists)
            pageToken = response.nextPageToken
        } while pageToken != nil && quotaRemaining > 0

        return allPlaylists
    }

    /// Fetch all video items from a playlist.
    /// Cost: 1 unit per page (50 videos/page).
    func fetchPlaylistItems(
        playlistId: String,
        playlistTitle: String = "",
        maxResults: Int = 50
    ) async throws -> [YouTubeVideo] {
        guard !apiKey.isEmpty else { throw YouTubeAPIError.noAPIKey }
        guard quotaRemaining > 0 else { throw YouTubeAPIError.quotaExhausted }

        var allVideos: [YouTubeVideo] = []
        var pageToken: String? = nil

        repeat {
            var components = URLComponents(string: "\(baseURL)/playlistItems")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "playlistId", value: playlistId),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "key", value: apiKey),
            ]
            if let token = pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: token))
            }

            guard let url = components.url else { throw YouTubeAPIError.invalidURL }

            let response: YouTubePagedResponse<RawPlaylistItem> = try await fetchAndDecode(url)
            quotaUsed += 1

            let videos = response.items.compactMap { raw -> YouTubeVideo? in
                guard raw.snippet.resourceId.kind == "youtube#video",
                      let videoId = raw.snippet.resourceId.videoId,
                      !videoId.isEmpty else { return nil }

                return YouTubeVideo(
                    videoId: videoId,
                    title: raw.snippet.title,
                    playlistId: playlistId,
                    playlistTitle: playlistTitle
                )
            }
            allVideos.append(contentsOf: videos)
            pageToken = response.nextPageToken
        } while pageToken != nil && quotaRemaining > 0

        return allVideos
    }

    /// Convenience: fetch all playlists from a source, then all videos from each.
    /// Filters to playlists that look like course lectures (>3 items).
    func fetchAllVideos(for source: UniversitySource) async throws -> [YouTubeVideo] {
        let playlists = try await fetchPlaylists(channelId: source.youtubeChannelId)

        // Filter to playlists with meaningful lecture content
        let lecturePlaylists = playlists.filter { $0.itemCount >= 3 }

        var allVideos: [YouTubeVideo] = []
        for playlist in lecturePlaylists {
            guard quotaRemaining > 0 else { break }
            do {
                let videos = try await fetchPlaylistItems(
                    playlistId: playlist.id,
                    playlistTitle: playlist.title
                )
                allVideos.append(contentsOf: videos)
            } catch {
                // Skip individual playlist failures
                continue
            }
        }

        return allVideos.uniqued(by: { $0.videoId.lowercased() })
    }

    // MARK: - Private

    private func fetchAndDecode<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.httpError(0)
        }
        guard http.statusCode == 200 else {
            throw YouTubeAPIError.httpError(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw YouTubeAPIError.decodingError(error)
        }
    }
}
