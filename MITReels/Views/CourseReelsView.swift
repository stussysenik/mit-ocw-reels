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
    @State private var nextId: String?
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
                                isNearby: lecture.youtubeId == nextId,
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
            cachedLectures = (course.lectures ?? [])
                .filter { $0.isFeedEligible }
                .uniqued(by: { $0.youtubeId.lowercased() })
            ThumbnailPrefetcher.shared.warmUp(lectures: cachedLectures)
            if let initialId = initialLectureId, visibleId == nil {
                visibleId = initialId
            }
        }
        .onChange(of: visibleId) { old, new in
            guard hasScrolled else { hasScrolled = true; return }
            haptic.impactOccurred()
            haptic.prepare()
            ThumbnailPrefetcher.shared.prefetch(lectures: cachedLectures, currentId: visibleId)
            // Capture @State values before entering async Task to avoid Binding resolution
            let lectures = cachedLectures
            let vid = visibleId
            // Defer WebView preload updates to after scroll animation settles
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                nextId = lectures.nextId(after: vid)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoEndedNotification)) { note in
            guard let endedId = note.object as? String, endedId == visibleId,
                  let idx = cachedLectures.firstIndex(where: { $0.youtubeId == endedId }),
                  idx + 1 < cachedLectures.count else { return }
            withAnimation { visibleId = cachedLectures[idx + 1].youtubeId }
        }
        .onReceive(NotificationCenter.default.publisher(for: ReelView.dislikeAdvanceNotification)) { note in
            guard let dislikedId = note.object as? String, dislikedId == visibleId,
                  let idx = cachedLectures.firstIndex(where: { $0.youtubeId == dislikedId }),
                  idx + 1 < cachedLectures.count else { return }
            withAnimation { visibleId = cachedLectures[idx + 1].youtubeId }
        }
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoUnavailableNotification)) { note in
            guard let videoId = note.object as? String else { return }
            if videoId == visibleId,
               let idx = cachedLectures.firstIndex(where: { $0.youtubeId == videoId }) {
                let next = idx + 1 < cachedLectures.count ? idx + 1
                         : idx - 1 >= 0 ? idx - 1 : nil
                if let next {
                    withAnimation { visibleId = cachedLectures[next].youtubeId }
                }
            }
            cachedLectures.removeAll { $0.youtubeId == videoId }
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
