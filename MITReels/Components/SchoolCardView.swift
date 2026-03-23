import SwiftUI

/// Gradient card representing one MIT School in the School Hub.
///
/// Shows school icon, name, course/lecture counts, and department pills.
/// Used as NavigationLink content in CoursesView.
struct SchoolCardView: View {
    let school: MITSchool
    let courseCount: Int
    let lectureCount: Int
    let departments: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                Image(systemName: school.systemImage)
                    .font(.title2)
                Text(school.shortName)
                    .font(.title3.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)

            // Stats
            HStack(spacing: Spacing.md) {
                Label("\(courseCount) courses", systemImage: "book.closed")
                Label("\(lectureCount) lectures", systemImage: "play.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))

            // Department pills
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
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [school.color, school.gradientEndColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview {
    SchoolCardView(
        school: .engineering,
        courseCount: 12,
        lectureCount: 87,
        departments: ["EECS", "Mechanical Eng", "Civil Eng"]
    )
    .padding()
}
