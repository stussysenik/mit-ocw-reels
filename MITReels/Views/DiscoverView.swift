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
    @State private var showSourceFilter = false

    @AppStorage("autoplayEnabled") private var autoplayEnabled = true
    @AppStorage("captionsEnabled") private var captionsEnabled = true
    @StateObject private var sourcePrefs = SourcePreferences.shared
    @StateObject private var feedPrefs = FeedPreferences.shared

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        NavigationStack {
            feedContent
            .navigationBarHidden(true)
            .navigationDestination(isPresented: Binding(
                get: { navigateToCourse != nil },
                set: { if !$0 { navigateToCourse = nil; navigateToLectureId = nil } }
            )) {
                if let course = navigateToCourse {
                    CourseReelsView(course: course, initialLectureId: navigateToLectureId)
                }
            }
            .sheet(isPresented: $showSourceFilter, onDismiss: rebuildFeed) {
                sourceFilterSheet
            }
        }
        .onAppear {
            haptic.prepare()
            if shuffledLectures.isEmpty && !lectures.isEmpty { rebuildFeed() }
        }
        .onChange(of: lectures.count) { _, n in if n > 0 { rebuildFeed() } }
        .onChange(of: sourcePrefs.enabledSourceIds) { _, _ in rebuildFeed() }
        .onChange(of: feedPrefs.blockedIds.count) { _, _ in rebuildFeed() }
        .onChange(of: visibleId) { old, _ in
            guard hasScrolled else { hasScrolled = true; return }
            haptic.impactOccurred()
            haptic.prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            haptic.impactOccurred()
            showSourceFilter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoEndedNotification)) { note in
            guard let endedId = note.object as? String, endedId == visibleId,
                  let idx = shuffledLectures.firstIndex(where: { $0.youtubeId == endedId }),
                  idx + 1 < shuffledLectures.count else { return }
            withAnimation { visibleId = shuffledLectures[idx + 1].youtubeId }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            URLCache.shared.removeAllCachedResponses()
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
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
                let nextId: String? = {
                    guard let vid = visibleId,
                          let idx = shuffledLectures.firstIndex(where: { $0.youtubeId == vid }),
                          idx + 1 < shuffledLectures.count else { return nil }
                    return shuffledLectures[idx + 1].youtubeId
                }()
                LazyVStack(spacing: 0) {
                    ForEach(shuffledLectures, id: \.youtubeId) { lecture in
                        ReelView(
                            lecture: lecture,
                            isVisible: visibleId == lecture.youtubeId,
                            isNext: lecture.youtubeId == nextId,
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

    // MARK: - Source Filter Sheet

    private var sourceFilterSheet: some View {
        NavigationStack {
            List {
                SourceFilterSection(sourcePrefs: sourcePrefs)
            }
            .navigationTitle("Filter Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSourceFilter = false }
                        .foregroundStyle(CarbonColor.interactive)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private static let feedLimit = 200

    private func rebuildFeed() {
        guard !lectures.isEmpty else { return }
        shuffledLectures = Self.filterValidLectures(lectures, enabledSources: sourcePrefs.enabledSourceIds, feedPrefs: feedPrefs)
    }

    /// Weighted course-breadth algorithm. O(n) filter → O(n) group → O(k log k) sort.
    static func filterValidLectures(_ lectures: [Lecture], enabledSources: Set<String>, feedPrefs: FeedPreferences) -> [Lecture] {
        let blocked = feedPrefs.blockedIds
        var valid: [Lecture] = []
        var seen = Set<String>()
        for lecture in lectures {
            let idLower = lecture.youtubeId.lowercased()
            let titleLower = lecture.title.lowercased()
            guard !blocked.contains(lecture.youtubeId),
                  enabledSources.contains(lecture.sourceId),
                  lecture.youtubeId.count == 11,
                  !lecture.courseNumber.isEmpty,
                  !titleLower.hasSuffix(".pdf"),
                  !titleLower.contains("3play"),
                  !titleLower.contains("caption file"),
                  seen.insert(idLower).inserted else { continue }
            valid.append(lecture)
        }
        let byCourse = Dictionary(grouping: valid) { "\($0.sourceId)_\($0.courseNumber)" }
        let sampled = byCourse.values.compactMap { $0.randomElement() }
        let scored = sampled.map { ($0, Double.random(in: 0...1) / feedPrefs.weight(for: $0.sourceId, topic: $0.department)) }
        return Array(scored.sorted { $0.1 < $1.1 }.prefix(feedLimit).map(\.0))
    }
}

#if DEBUG
#Preview {
    DiscoverView()
        .modelContainer(PreviewSampleData.container)
}
#endif
