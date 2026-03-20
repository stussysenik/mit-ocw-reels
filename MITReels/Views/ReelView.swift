import SwiftUI

/// A single full-screen reel displaying a YouTube lecture video.
/// VStack layout: video centered, course info pinned at bottom.
/// WKWebView renders above SwiftUI overlays, so we use VStack (not ZStack) to avoid overlap.
struct ReelView: View {
    let lecture: Lecture

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            // YouTube video player — centered with 16:9 aspect ratio
            YouTubePlayerView(videoId: lecture.youtubeId)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)

            Spacer(minLength: 16)

            // Course info card pinned at bottom
            VStack(alignment: .leading, spacing: 8) {
                Text(lecture.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)

                Text(lecture.courseName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(lecture.courseNumber, systemImage: "book.closed.fill")
                    Label(lecture.department, systemImage: "building.2.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !lecture.topicName.isEmpty {
                    Text(lecture.topicName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}
