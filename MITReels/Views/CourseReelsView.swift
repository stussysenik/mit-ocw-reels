import SwiftUI

/// Course-specific lecture reels — same doom-scroll paging but filtered to one course.
///
/// Navigated to from CoursesView when user taps a specific course.
/// Each reel shows a "LECTURE N" label via `ReelView(lectureIndex:)` since
/// the course context is already visible in the navigation bar.
struct CourseReelsView: View {
    let course: Course
    /// Optional starting lecture — when set, scrolls to this lecture on appear (from Discover feed).
    var initialLectureId: String? = nil
    @State private var visibleId: String?
    @State private var cachedLectures: [Lecture] = []
    @State private var hasScrolled = false
    @AppStorage("autoplayEnabled") private var autoplayEnabled = true
    @AppStorage("captionsEnabled") private var captionsEnabled = true

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        Group {
            if cachedLectures.isEmpty {
                ContentUnavailableView(
                    "No Lectures",
                    systemImage: "video.slash",
                    description: Text("This course has no lecture videos yet.")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(cachedLectures.enumerated()),
                            id: \.element.youtubeId
                        ) { index, lecture in
                            ReelView(
                                lecture: lecture,
                                lectureIndex: index,
                                isVisible: visibleId == lecture.youtubeId,
                                autoplayEnabled: autoplayEnabled,
                                captionsEnabled: captionsEnabled
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
        .onAppear {
            haptic.prepare()
            cachedLectures = (course.lectures ?? []).uniqued(by: { $0.youtubeId.lowercased() })
            if let initialId = initialLectureId, visibleId == nil {
                visibleId = initialId
            }
        }
        .onChange(of: visibleId) { old, _ in
            guard hasScrolled else { hasScrolled = true; return }
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
