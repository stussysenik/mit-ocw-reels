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
    @SceneStorage("discoverVisibleId") private var visibleId: String?
    @State private var nextId: String?
    @State private var hasScrolled = false
    @State private var navigateToCourse: Course?
    @State private var navigateToLectureId: String?
    @State private var showSourceFilter = false
    @State private var rebuildTask: Task<Void, Never>?
    @State private var lastBuiltSources: Set<String> = []

    @Environment(\.scenePhase) private var scenePhase
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
            if shuffledLectures.isEmpty && !lectures.isEmpty {
                rebuildFeed()
            } else if sourcePrefs.enabledSourceIds != lastBuiltSources {
                rebuildFeed()
            }
            // Covers nil (first launch) AND stale (relaunch with new shuffle)
            if !shuffledLectures.isEmpty,
               visibleId == nil || !shuffledLectures.contains(where: { $0.youtubeId == visibleId }) {
                visibleId = shuffledLectures.first?.youtubeId
            }
        }
        .onChange(of: lectures.count) { old, n in
            guard n > old else { return }
            // Large batch (multi-source seed) → full rebuild for proportionate sampling
            if shuffledLectures.isEmpty || (n - old) > 100 { rebuildFeed() }
            else { appendNewLectures() }
        }
        .onChange(of: sourcePrefs.enabledSourceIds) { _, _ in debouncedRebuildFeed() }
        .onChange(of: feedPrefs.blockedIds.count) { _, _ in debouncedRebuildFeed() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { rebuildFeed() }
        }
        .onChange(of: visibleId) { old, new in
            guard hasScrolled else { hasScrolled = true; return }
            haptic.impactOccurred()
            haptic.prepare()
            // Defer preload updates to after scroll animation settles
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                nextId = shuffledLectures.nextId(after: visibleId)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: ReelView.dislikeAdvanceNotification)) { note in
            guard let dislikedId = note.object as? String, dislikedId == visibleId,
                  let idx = shuffledLectures.firstIndex(where: { $0.youtubeId == dislikedId }),
                  idx + 1 < shuffledLectures.count else { return }
            withAnimation { visibleId = shuffledLectures[idx + 1].youtubeId }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            URLCache.shared.removeAllCachedResponses()
            WKWebViewPool.shared.handleMemoryWarning()
        }
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoUnavailableNotification)) { note in
            guard let videoId = note.object as? String else { return }
            if videoId == visibleId,
               let idx = shuffledLectures.firstIndex(where: { $0.youtubeId == videoId }) {
                let next = idx + 1 < shuffledLectures.count ? idx + 1
                         : idx - 1 >= 0 ? idx - 1 : nil
                if let next {
                    withAnimation { visibleId = shuffledLectures[next].youtubeId }
                }
            }
            shuffledLectures.removeAll { $0.youtubeId == videoId }
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
                LazyVStack(spacing: 0) {
                    ForEach(shuffledLectures, id: \.youtubeId) { lecture in
                        ReelView(
                            lecture: lecture,
                            isVisible: visibleId == lecture.youtubeId,
                            isNearby: lecture.youtubeId == nextId,
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
    /// Max lectures from any single course in one feed — prevents large courses from dominating.
    private static let maxPerCourse = 3

    private func debouncedRebuildFeed() {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            rebuildFeed()
        }
    }

    private func rebuildFeed() {
        guard !lectures.isEmpty else { return }
        let sources = sourcePrefs.enabledSourceIds
        shuffledLectures = Self.filterValidLectures(lectures, enabledSources: sources, feedPrefs: feedPrefs)
        lastBuiltSources = sources
    }

    /// Append newly-arrived lectures without reshuffling the existing feed.
    /// Respects per-course and per-source diversity against existing content.
    private func appendNewLectures() {
        let existing = Set(shuffledLectures.map { $0.youtubeId.lowercased() })
        let blocked = feedPrefs.blockedIds
        let enabled = sourcePrefs.enabledSourceIds

        // Track current counts per course and source
        var courseCounts: [String: Int] = [:]
        var sourceCounts: [String: Int] = [:]
        for lecture in shuffledLectures {
            courseCounts["\(lecture.sourceId)_\(lecture.courseNumber)", default: 0] += 1
            sourceCounts[lecture.sourceId, default: 0] += 1
        }
        let sourceShare = Self.feedLimit / max(enabled.count, 1)

        var fresh = lectures.filter {
            $0.isFeedEligible
            && !existing.contains($0.youtubeId.lowercased())
            && !blocked.contains($0.youtubeId)
            && enabled.contains($0.sourceId)
        }
        guard !fresh.isEmpty, shuffledLectures.count < Self.feedLimit else { return }
        fresh.shuffle()

        var toAppend: [Lecture] = []
        for lecture in fresh {
            guard toAppend.count + shuffledLectures.count < Self.feedLimit else { break }
            let courseKey = "\(lecture.sourceId)_\(lecture.courseNumber)"
            guard (courseCounts[courseKey] ?? 0) < Self.maxPerCourse else { continue }
            guard (sourceCounts[lecture.sourceId] ?? 0) < sourceShare else { continue }
            courseCounts[courseKey, default: 0] += 1
            sourceCounts[lecture.sourceId, default: 0] += 1
            toAppend.append(lecture)
        }
        shuffledLectures.append(contentsOf: toAppend)
    }

    /// Stratified feed: proportionate source share → per-course cap → weighted shuffle.
    ///
    /// Each enabled source gets an equal base share of the feed (`feedLimit / sourceCount`).
    /// Within each source, no course contributes more than `maxPerCourse` lectures.
    /// Leftover slots from small sources spill over to larger ones.
    /// Final ordering uses Efraimidis-Spirakis weighted sampling so thumbs-up/down
    /// bias which lectures appear when a source has more candidates than its share.
    static func filterValidLectures(_ lectures: [Lecture], enabledSources: Set<String>, feedPrefs: FeedPreferences) -> [Lecture] {
        let blocked = feedPrefs.blockedIds
        let eligible = lectures
            .filter { $0.isFeedEligible && !blocked.contains($0.youtubeId) && enabledSources.contains($0.sourceId) }
            .uniqued(by: { $0.youtubeId.lowercased() })

        // Group by source, then apply per-course cap within each source
        let bySource = Dictionary(grouping: eligible) { $0.sourceId }
        var sourcePools: [String: [Lecture]] = [:]
        for (sourceId, sourceLectures) in bySource {
            let byCourse = Dictionary(grouping: sourceLectures) { $0.courseNumber }
            var pool: [Lecture] = []
            for (_, group) in byCourse {
                pool.append(contentsOf: group.shuffled().prefix(maxPerCourse))
            }
            sourcePools[sourceId] = pool
        }

        // Fair share per source, then redistribute unused slots
        let sourceCount = max(sourcePools.count, 1)
        let baseShare = feedLimit / sourceCount
        var result: [Lecture] = []
        var overflow: [Lecture] = []

        for (_, pool) in sourcePools {
            let sorted = pool.weightedShuffle(using: feedPrefs)

            result.append(contentsOf: sorted.prefix(baseShare))
            if sorted.count > baseShare {
                overflow.append(contentsOf: sorted.dropFirst(baseShare))
            }
        }

        // Fill remaining slots from overflow (weighted shuffle across all sources)
        let remaining = feedLimit - result.count
        if remaining > 0 && !overflow.isEmpty {
            let spillover = Array(overflow.weightedShuffle(using: feedPrefs).prefix(remaining))
            result.append(contentsOf: spillover)
        }

        // Final shuffle so sources aren't grouped in blocks
        result.shuffle()
        return result
    }
}

#if DEBUG
#Preview {
    DiscoverView()
        .modelContainer(PreviewSampleData.container)
}
#endif
