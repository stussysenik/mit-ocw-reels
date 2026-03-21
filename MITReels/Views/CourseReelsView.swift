import SwiftUI

/// Course-specific lecture reels — same doom-scroll paging but filtered to one course.
///
/// Navigated to from CoursesView when user taps a specific course.
/// Each reel shows a "LECTURE N" label via `ReelView(lectureIndex:)` since
/// the course context is already visible in the navigation bar.
struct CourseReelsView: View {
    let course: Course
    @State private var visibleId: String?
    @AppStorage("autoplayEnabled") private var autoplayEnabled = true

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private var lectures: [Lecture] {
        course.lectures ?? []
    }

    var body: some View {
        Group {
            if lectures.isEmpty {
                ContentUnavailableView(
                    "No Lectures",
                    systemImage: "video.slash",
                    description: Text("This course has no lecture videos yet.")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(lectures.enumerated()),
                            id: \.element.youtubeId
                        ) { index, lecture in
                            ReelView(
                                lecture: lecture,
                                lectureIndex: index,
                                isVisible: visibleId == lecture.youtubeId,
                                autoplayEnabled: autoplayEnabled
                            )
                            .containerRelativeFrame(.vertical)
                            .id(lecture.youtubeId)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $visibleId)
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .vertical)
                .background(CarbonColor.reelBackground)
            }
        }
        .navigationTitle(course.courseNumber)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { haptic.prepare() }
        .onChange(of: visibleId) { _, _ in
            haptic.impactOccurred()
            haptic.prepare()
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CourseReelsView(course: PreviewSampleData.sampleCourse)
    }
    .modelContainer(PreviewSampleData.container)
}
#endif
