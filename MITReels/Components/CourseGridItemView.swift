import SwiftUI

/// Compact grid card for a course in the 2-column grid view.
///
/// Shows a video placeholder, course number, title, and lecture count.
/// Used inside SchoolDetailView's grid mode.
struct CourseGridItemView: View {
    let course: Course
    let school: MITSchool

    private var thumbnailVideoId: String? {
        course.lectures?
            .first(where: { !$0.youtubeId.isEmpty })?
            .youtubeId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ZStack {
                if let thumbnailVideoId {
                    YouTubeThumbnailView(videoId: thumbnailVideoId)
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

            if let count = course.lectures?.count, count > 0 {
                Text("\(count) lecture\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(CarbonColor.textPlaceholder)
            }
        }
        .padding(Spacing.xs)
        .background(CarbonColor.layer01)
        .clipShape(RoundedRectangle(cornerRadius: Radius.search))
    }
}
