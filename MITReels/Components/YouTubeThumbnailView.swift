import SwiftUI

/// Lightweight YouTube poster image with fallback resolution support.
struct YouTubeThumbnailView: View {
    let videoId: String

    @State private var sourceIndex = 0

    private var thumbnailSources: [URL] {
        [
            URL(string: "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"),
            URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"),
            URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")
        ].compactMap(\.self)
    }

    var body: some View {
        Group {
            if let url = thumbnailSources[safe: sourceIndex] {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        if sourceIndex < thumbnailSources.count - 1 {
                            Color.clear
                                .task(id: sourceIndex) {
                                    sourceIndex += 1
                                }
                        } else {
                            placeholder
                        }
                    case .empty:
                        placeholder
                    @unknown default:
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
