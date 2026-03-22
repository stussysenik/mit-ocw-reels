import SwiftUI
import SwiftData

/// Discover tab — randomized lecture reels in a doom-scroll vertical paging feed.
///
/// Uses iOS 17+ `ScrollView` with `.scrollTargetBehavior(.paging)` for native
/// snap-to-page. One scroll = one page. Haptic feedback on each page change.
/// White background matches the NASA-inspired light aesthetic.
///
/// Tapping the metadata line navigates to the full course lecture sequence.
/// OCW links below each reel open the course page, syllabus, and readings.
struct DiscoverView: View {
    @Query private var lectures: [Lecture]

    @State private var shuffledLectures: [Lecture] = []
    @State private var visibleId: String?
    @State private var hasScrolled = false
    @State private var navigateToCourse: Course?
    @State private var navigateToLectureId: String?

    @AppStorage("autoplayEnabled") private var autoplayEnabled = true
    @AppStorage("captionsEnabled") private var captionsEnabled = true

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        NavigationStack {
            Group {
                if shuffledLectures.isEmpty {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                            .tint(CarbonColor.interactive)
                        Text("Loading lectures...")
                            .font(.subheadline)
                            .foregroundStyle(CarbonColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CarbonColor.reelBackground)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(shuffledLectures, id: \.youtubeId) { lecture in
                                ReelView(
                                    lecture: lecture,
                                    isVisible: visibleId == lecture.youtubeId,
                                    autoplayEnabled: autoplayEnabled,
                                    captionsEnabled: captionsEnabled,
                                    onViewCourse: { tappedLecture in
                                        navigateToLectureId = tappedLecture.youtubeId
                                        navigateToCourse = tappedLecture.course
                                    }
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
            .navigationBarHidden(true)
            .navigationDestination(isPresented: Binding(
                get: { navigateToCourse != nil },
                set: { if !$0 { navigateToCourse = nil; navigateToLectureId = nil } }
            )) {
                if let course = navigateToCourse {
                    CourseReelsView(course: course, initialLectureId: navigateToLectureId)
                }
            }
        }
        .onAppear {
            haptic.prepare()
            if shuffledLectures.isEmpty && !lectures.isEmpty {
                shuffledLectures = Self.filterValidLectures(lectures).shuffled()
            }
        }
        .onChange(of: lectures.count) { _, newCount in
            if newCount > 0 && shuffledLectures.isEmpty {
                shuffledLectures = Self.filterValidLectures(lectures).shuffled()
            }
        }
        .onChange(of: visibleId) { old, _ in
            guard hasScrolled else { hasScrolled = true; return }
            haptic.impactOccurred()
            haptic.prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // Flush caches on memory pressure to prevent Jetsam kill
            URLCache.shared.removeAllCachedResponses()
        }
    }

    // MARK: - Helpers

    /// Filters out invalid lectures: PDFs, empty IDs, orphan records.
    /// Note: Does NOT filter by thumbnail quality — thumbnails are cosmetic.
    /// The video player has its own error state for truly unavailable videos.
    static func filterValidLectures(_ lectures: [Lecture]) -> [Lecture] {
        var seen = Set<String>()
        return lectures.filter { lecture in
            let id = lecture.youtubeId.lowercased()
            guard !id.isEmpty,
                  !seen.contains(id),
                  !lecture.courseNumber.isEmpty,
                  !lecture.title.lowercased().hasSuffix(".pdf"),
                  !lecture.title.lowercased().contains("3play"),
                  !lecture.title.lowercased().contains("caption file")
            else { return false }
            seen.insert(id)
            return true
        }
    }
}

#if DEBUG
#Preview {
    DiscoverView()
        .modelContainer(PreviewSampleData.container)
}
#endif
