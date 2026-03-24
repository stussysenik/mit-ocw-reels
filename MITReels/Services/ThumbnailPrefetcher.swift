import UIKit

/// Directional thumbnail prefetcher inspired by Flutter `precacheImage` and TikTok's
/// preload-5-ahead strategy. Downloads YouTube `hqdefault.jpg` thumbnails into an
/// in-memory `NSCache` so `CachedThumbnailView` can display them in O(1) — zero
/// network wait when the user scrolls to a preloaded reel.
///
/// Three-tier lookup: NSCache (O(1), ~0ms) → URLCache (disk, ~5ms) → Network (~200ms).
/// Prefetch window: [currentIdx - 1 ... currentIdx + 5] — 7 thumbnails always warm.
@MainActor
final class ThumbnailPrefetcher {
    static let shared = ThumbnailPrefetcher()

    /// Decoded UIImage cache — O(1) lookup, no disk IO, no network.
    private let imageCache = NSCache<NSString, UIImage>()
    /// In-flight download tasks keyed by videoId — prevents duplicate fetches.
    private var inFlight: [String: Task<Void, Never>] = [:]
    /// How many reels ahead/behind to prefetch.
    private let lookAhead = 5
    private let lookBehind = 1
    /// Dedicated session — no cookies, short timeout, background-friendly.
    private let session: URLSession

    private init() {
        imageCache.countLimit = 30              // ~15 MB for 480x360 JPEGs
        imageCache.totalCostLimit = 20_000_000  // 20 MB hard cap

        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpShouldUsePipelining = true
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// O(1) cache lookup. Returns nil if the thumbnail hasn't been prefetched yet.
    func cachedImage(for videoId: String) -> UIImage? {
        imageCache.object(forKey: videoId as NSString)
    }

    /// Fetch a single thumbnail, caching the result. Used as fallback by `CachedThumbnailView`
    /// when the prefetcher hasn't warmed this videoId yet.
    func fetchAndCache(videoId: String) async -> UIImage? {
        // Check cache first (may have been prefetched between caller's check and now)
        if let cached = imageCache.object(forKey: videoId as NSString) { return cached }

        guard let url = Self.thumbnailURL(for: videoId) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            imageCache.setObject(image, forKey: videoId as NSString, cost: data.count)
            return image
        } catch {
            return nil
        }
    }

    /// Move the prefetch window to center on `currentId`. Cancels out-of-window tasks,
    /// starts new ones for thumbnails entering the window.
    func prefetch(lectures: [Lecture], currentId: String?) {
        guard let currentId,
              let idx = lectures.firstIndex(where: { $0.youtubeId == currentId }) else { return }

        let lo = max(0, idx - lookBehind)
        let hi = min(lectures.count - 1, idx + lookAhead)
        let windowIds = Set(lectures[lo...hi].map { $0.youtubeId })

        // Cancel tasks that fell outside the window
        for (videoId, task) in inFlight where !windowIds.contains(videoId) {
            task.cancel()
            inFlight.removeValue(forKey: videoId)
        }

        // Start new fetches for uncached IDs in the window
        for videoId in windowIds {
            guard imageCache.object(forKey: videoId as NSString) == nil,
                  inFlight[videoId] == nil else { continue }
            inFlight[videoId] = Task { [weak self] in
                guard let self else { return }
                _ = await self.fetchAndCache(videoId: videoId)
                self.inFlight.removeValue(forKey: videoId)
            }
        }
    }

    /// Prefetch thumbnails by ID list — O(1) per ID, no index search.
    /// Used by FeedEngine integration where the engine provides exact IDs.
    func prefetchByIds(_ ids: [String]) {
        let windowIds = Set(ids)
        // Cancel tasks that fell outside the window
        for (videoId, task) in inFlight where !windowIds.contains(videoId) {
            task.cancel()
            inFlight.removeValue(forKey: videoId)
        }
        // Start new fetches for uncached IDs
        for videoId in windowIds {
            guard imageCache.object(forKey: videoId as NSString) == nil,
                  inFlight[videoId] == nil else { continue }
            inFlight[videoId] = Task { [weak self] in
                guard let self else { return }
                _ = await self.fetchAndCache(videoId: videoId)
                self.inFlight.removeValue(forKey: videoId)
            }
        }
    }

    /// Warm the first N thumbnails on feed build — ensures instant display on launch.
    func warmUp(lectures: [Lecture]) {
        prefetch(lectures: lectures, currentId: lectures.first?.youtubeId)
    }

    /// Cancel all in-flight tasks on memory pressure. NSCache auto-evicts entries.
    func handleMemoryWarning() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
        imageCache.removeAllObjects()
    }

    // MARK: - Helpers

    private static func thumbnailURL(for videoId: String) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")
    }
}
