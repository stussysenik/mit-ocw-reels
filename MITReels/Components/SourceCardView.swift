import SwiftUI

/// Gradient card representing a non-MIT lecture source in the "More Sources" section.
///
/// Mirrors SchoolCardView's layout: icon, name, counts, department pills.
/// Uses the source's brand color gradient for the card background.
struct SourceCardView: View {
    let source: UniversitySource
    let courseCount: Int
    let lectureCount: Int
    let departments: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: source.systemImage)
                    .font(.title2)
                Text(source.shortName)
                    .font(.title3.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)

            HStack(spacing: Spacing.md) {
                Label("\(courseCount) courses", systemImage: "book.closed")
                Label("\(lectureCount) lectures", systemImage: "play.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))

            if !departments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(departments, id: \.self) { dept in
                            Text(dept)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [source.brandColor, source.gradientEndColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}
