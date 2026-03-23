import SwiftUI

/// Lightweight YouTube poster image using hqdefault (480x360).
///
/// Uses a single `hqdefault.jpg` URL — reliable for all valid YouTube videos.
/// `maxresdefault.jpg` is skipped because YouTube returns HTTP 200 with a tiny
/// 120x90 gray placeholder when no custom thumbnail exists, causing AsyncImage
/// to silently succeed with an invisible image.
///
/// O(1) rendering: thumbnail URL is a `let`, not a computed property.
struct YouTubeThumbnailView: View {
    let videoId: String

    /// Single reliable URL — set once in init, never recomputed.
    private let thumbnailURL: URL?

    init(videoId: String) {
        self.videoId = videoId
        self.thumbnailURL = URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")
    }

    var body: some View {
        Group {
            if let url = thumbnailURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
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
    YouTubeThumbnailView(videoId: "nykOeWgQcHM")
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
}
