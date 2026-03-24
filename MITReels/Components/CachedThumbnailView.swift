import SwiftUI

/// YouTube thumbnail with three-tier loading: NSCache (O(1)) → URLCache (disk) → Network.
///
/// Replaces `YouTubeThumbnailView` which used bare `AsyncImage` — no caching between
/// offscreen/onscreen transitions, re-fetching from network every time a cell reappeared.
/// `ThumbnailPrefetcher` warms the NSCache ahead of scroll, so this view typically
/// hits Tier 1 (instant) for the current and nearby reels.
struct CachedThumbnailView: View {
    let videoId: String
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var retryCount = 0
    /// Max retry attempts for thumbnail fetch — covers transient network failures.
    private static let maxRetries = 2

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .clipped()
        .onAppear { loadImage() }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: videoId) { _, _ in
            image = nil
            retryCount = 0
            loadImage()
        }
    }

    private func loadImage() {
        // Tier 1: NSCache hit — O(1), ~0ms
        if let cached = ThumbnailPrefetcher.shared.cachedImage(for: videoId) {
            image = cached
            return
        }
        // Tier 2+3: URLCache (disk) or network — async with retry
        loadTask?.cancel()
        let currentVideoId = videoId
        loadTask = Task {
            let img = await ThumbnailPrefetcher.shared.fetchAndCache(videoId: currentVideoId)
            guard !Task.isCancelled, currentVideoId == videoId else { return }
            if let img {
                await MainActor.run { image = img }
            } else if retryCount < Self.maxRetries {
                // Retry after a short delay — covers transient network failures
                try? await Task.sleep(for: .milliseconds(500 * (retryCount + 1)))
                guard !Task.isCancelled, currentVideoId == videoId else { return }
                await MainActor.run {
                    retryCount += 1
                    loadImage()
                }
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [CarbonColor.layerHover, CarbonColor.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "play.rectangle.fill")
                .font(.title3)
                .foregroundStyle(CarbonColor.textLabel)
        }
    }
}

#Preview {
    CachedThumbnailView(videoId: "nykOeWgQcHM")
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
}
