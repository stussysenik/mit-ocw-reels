import SwiftUI

/// Compact grid card for a course in the 2-column grid view.
///
/// Shows a video thumbnail, course number, title, lecture count, and semester.
/// Used inside SchoolDetailView's grid mode.
///
/// O(1) rendering: thumbnail video ID is cached on appear, not recomputed per render.
struct CourseGridItemView: View {
    let course: Course
    let school: MITSchool

    /// Cached on appear — avoids .filter().sorted() on every render.
    @State private var cachedThumbnailId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ZStack {
                if let thumbnailId = cachedThumbnailId {
                    YouTubeThumbnailView(videoId: thumbnailId)
                } else {
                    RoundedRectangle(cornerRadius: Radius.badge)
                        .fill(CarbonColor.layerHover)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            .overlay(alignment: .bottomLeading) {
                Label("Watch", systemImage: "play.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(Spacing.xs)
            }

            Text(course.courseNumber)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(school.color)

            Text(course.title)
                .font(.caption)
                .foregroundStyle(CarbonColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 4) {
                if let count = course.lectures?.count, count > 0 {
                    Text("\(count) lecture\(count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(CarbonColor.textPlaceholder)
                }

                if !course.semester.isEmpty && course.year > 0 {
                    Text("\u{00B7}")
                        .font(.caption2)
                        .foregroundStyle(CarbonColor.textTertiary)
                    Text("\(course.semester) \(String(course.year))")
                        .font(.caption2)
                        .foregroundStyle(CarbonColor.textPlaceholder)
                }
            }
        }
        .padding(Spacing.xs)
        .background(CarbonColor.layer01)
        .clipShape(RoundedRectangle(cornerRadius: Radius.search))
        .onAppear {
            cachedThumbnailId = course.lectures?
                .filter { !$0.youtubeId.isEmpty
                          && !$0.title.lowercased().hasSuffix(".pdf")
                          && $0.title != "Unknown" }
                .sorted { $0.title.count > $1.title.count }
                .first?
                .youtubeId
        }
    }
}
