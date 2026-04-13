import SwiftUI
import SwiftData

/// Discover tab — randomized lecture reels in a doom-scroll vertical paging feed.
///
/// Uses iOS 17+ `ScrollView` with `.scrollTargetBehavior(.paging)` for native
/// snap-to-page. One scroll = one page. Haptic feedback on each page change.
/// White background matches the NASA-inspired light aesthetic.
///
/// Feed computation is fully off-loaded to a `FeedEngine` actor that maintains a
/// probabilistic sliding-window buffer. Each batch of 10 items reflects the
/// latest interaction weights — a thumbs-up at position 5 influences position 15.
///
/// Tapping the metadata line navigates to the full course lecture sequence.
/// OCW links below each reel open the course page, syllabus, and readings.
struct DiscoverView: View {
    @Query private var lectures: [Lecture]

    @State private var displayLectures: [Lecture] = []
    @SceneStorage("discoverVisibleId") private var visibleId: String?
    /// Bridge between SlidingLoop's Int binding and the String-keyed app state.
    /// visibleId remains the persisted source of truth; visibleIndex is derived.
    @State private var visibleIndex: Int = 0
    @State private var nextId: String?
    @State private var hasScrolled = false
    @State private var navigateToCourse: Course?
    @State private var navigateToLectureId: String?
    @State private var showSourceFilter = false
    @State private var rebuildTask: Task<Void, Never>?
    @State private var lastBuiltSources: Set<String> = []
    @State private var feedEngine = FeedEngine()
    /// Tracks when each reel became visible — used for soft signal (skip speed / long watch).
    @State private var reelAppearTime: Date?

    /// Map Lecture @Model objects to Sendable FeedItems for the actor boundary.
    private var feedItems: [FeedItem] {
        lectures.filter { $0.isFeedEligible }.map {
            FeedItem(youtubeId: $0.youtubeId, sourceId: $0.sourceId,
                     department: $0.department, courseNumber: $0.courseNumber)
        }
    }

    /// Lookup table for mapping engine IDs back to Lecture objects for display.
    private var lectureById: [String: Lecture] {
        Dictionary(lectures.map { ($0.youtubeId, $0) }, uniquingKeysWith: { first, _ in first })
    }

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
            .sheet(isPresented: $showSourceFilter, onDismiss: {
                Task { await bootstrapEngine() }
            }) {
                sourceFilterSheet
            }
        }
        .onAppear {
            haptic.prepare()
            if displayLectures.isEmpty && !lectures.isEmpty {
                Task { await bootstrapEngine() }
            } else if sourcePrefs.enabledSourceIds != lastBuiltSources {
                Task { await bootstrapEngine() }
            }
            // syncDisplay() handles stale visibleId — no duplicate check needed here
        }
        .onChange(of: lectures.count) { old, n in
            guard n > old else { return }
            if displayLectures.isEmpty || (n - old) > 100 {
                Task { await bootstrapEngine() }
            } else {
                Task {
                    await feedEngine.updateItems(feedItems)
                    await syncDisplay()
                }
            }
        }
        .onChange(of: sourcePrefs.enabledSourceIds) { _, _ in debouncedRebuildFeed() }
        .onChange(of: feedPrefs.blockedIds.count) { _, _ in debouncedRebuildFeed() }
        .onChange(of: scenePhase) { _, phase in
            // Graceful resume: rebuild pools from current lectures but preserve
            // buffer, history, and session-local soft adjustments.
            if phase == .active {
                Task {
                    await feedEngine.updateItems(feedItems)
                    await syncDisplay()
                }
            }
        }
        .onChange(of: visibleId) { old, new in
            guard hasScrolled else { hasScrolled = true; return }
            haptic.impactOccurred()
            haptic.prepare()

            // Soft signal: measure time on previous reel
            reportSoftSignal(oldId: old)
            reelAppearTime = Date()

            // Only advance the buffer when scrolling forward past history.
            // Backward scrolls into history items should not consume buffer heads.
            let oldIdx = old.flatMap { id in displayLectures.firstIndex(where: { $0.youtubeId == id }) }
            let newIdx = new.flatMap { id in displayLectures.firstIndex(where: { $0.youtubeId == id }) }
            let isForward = if let o = oldIdx, let n = newIdx { n > o } else { true }

            if isForward {
                Task {
                    await feedEngine.advance()
                    await syncDisplay()
                }
            }

            // Prefetch thumbnails in a ±25 window around the current visible
            // index. Widened from the old forward-only ±6 so backward scrolls
            // hit a cached thumbnail too. The ±25 window matches the
            // ReelPlayerPool warm-up span and gives the "2ms floor" layer
            // full coverage over the rapid-interaction test range.
            let currentIndex = displayLectures.firstIndex { $0.youtubeId == new } ?? 0
            let windowIds = ThumbnailPrefetcher.idsAround(
                centerIndex: currentIndex,
                window: 25,
                in: displayLectures.map(\.youtubeId)
            )
            ThumbnailPrefetcher.shared.prefetchByIds(windowIds)

            // Defer WebView preload updates to after scroll animation settles
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                nextId = displayLectures.nextId(after: new)
            }
        }
        .onChange(of: visibleIndex) { _, new in
            guard new >= 0, new < displayLectures.count else { return }
            let newId = displayLectures[new].youtubeId
            if visibleId != newId {
                visibleId = newId
            }
        }
        .onChange(of: displayLectures.map(\.youtubeId)) { _, _ in
            // After bootstrap or buffer refresh, reconcile visibleIndex to
            // whatever visibleId points to (preserves SceneStorage restoration).
            if let vid = visibleId,
               let idx = displayLectures.firstIndex(where: { $0.youtubeId == vid }) {
                if visibleIndex != idx { visibleIndex = idx }
            } else if !displayLectures.isEmpty {
                visibleIndex = 0
            }
        }
        .modifier(ScrollVelocityModifier(feedEngine: feedEngine))
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            haptic.impactOccurred()
            showSourceFilter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoEndedNotification)) { note in
            guard let endedId = note.object as? String, endedId == visibleId,
                  let idx = displayLectures.firstIndex(where: { $0.youtubeId == endedId }),
                  idx + 1 < displayLectures.count else { return }
            visibleIndex = idx + 1
        }
        .onReceive(NotificationCenter.default.publisher(for: ReelView.dislikeAdvanceNotification)) { note in
            guard let dislikedId = note.object as? String, dislikedId == visibleId,
                  let idx = displayLectures.firstIndex(where: { $0.youtubeId == dislikedId }),
                  idx + 1 < displayLectures.count else { return }
            // Advance by index — SlidingLoop animates to the new index via its spring.
            visibleIndex = idx + 1
            Task {
                await feedEngine.blockVideo(id: dislikedId)
                await feedEngine.refreshWeights(feedPrefs)
                await syncDisplay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ReelView.likeNotification)) { _ in
            Task { await feedEngine.refreshWeights(feedPrefs) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            WKWebViewPool.shared.handleMemoryWarning()
            ThumbnailPrefetcher.shared.handleMemoryWarning()
        }
        .onReceive(NotificationCenter.default.publisher(for: YouTubePlayerView.Coordinator.videoUnavailableNotification)) { note in
            guard let videoId = note.object as? String else { return }
            if videoId == visibleId,
               let idx = displayLectures.firstIndex(where: { $0.youtubeId == videoId }) {
                let next = idx + 1 < displayLectures.count ? idx + 1
                         : idx - 1 >= 0 ? idx - 1 : nil
                if let next {
                    visibleIndex = next
                }
            }
            // Route through engine so syncDisplay stays the single source of truth
            Task {
                await feedEngine.blockVideo(id: videoId)
                await syncDisplay()
            }
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        if displayLectures.isEmpty {
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
            SlidingLoop(items: displayLectures, visibleIndex: $visibleIndex) { lecture, isVisible in
                ReelView(
                    lecture: lecture,
                    isVisible: isVisible,
                    isNearby: lecture.youtubeId == nextId,
                    autoplayEnabled: autoplayEnabled,
                    captionsEnabled: captionsEnabled,
                    onViewCourse: { tappedLecture in
                        navigateToLectureId = tappedLecture.youtubeId
                        navigateToCourse = tappedLecture.course
                    }
                )
            }
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

    // MARK: - Engine Integration

    private func bootstrapEngine() async {
        guard !lectures.isEmpty else { return }
        await feedEngine.bootstrap(
            items: feedItems,
            feedPrefs: feedPrefs,
            sourcePrefs: sourcePrefs
        )
        await syncDisplay()
        lastBuiltSources = sourcePrefs.enabledSourceIds
    }

    /// Pull the engine's display window (ID list) and map back to Lecture objects.
    @MainActor
    private func syncDisplay() async {
        let windowIds = await feedEngine.displayWindow
        let lookup = lectureById
        displayLectures = windowIds.compactMap { lookup[$0] }
        // Warm thumbnails using engine's ahead-window (O(1) per ID, no index search)
        let prefetchIds = await feedEngine.prefetchIds(count: 6)
        ThumbnailPrefetcher.shared.prefetchByIds(prefetchIds)
        // Fix visibleId if stale
        if !displayLectures.isEmpty,
           visibleId == nil || !displayLectures.contains(where: { $0.youtubeId == visibleId }) {
            visibleId = displayLectures.first?.youtubeId
        }
    }

    private func debouncedRebuildFeed() {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await bootstrapEngine()
        }
    }

    /// Report soft signal based on how long the user viewed the previous reel.
    private func reportSoftSignal(oldId: String?) {
        guard let oldId, let appear = reelAppearTime,
              let lecture = displayLectures.first(where: { $0.youtubeId == oldId }) else { return }
        let elapsed = Date().timeIntervalSince(appear)
        let interaction: FeedInteraction? = elapsed < 1.5 ? .fastSkip : elapsed > 30 ? .longWatch : nil
        if let interaction {
            Task { await feedEngine.recordInteraction(interaction, sourceId: lecture.sourceId, department: lecture.department) }
        }
    }
}

// MARK: - Velocity Detection (iOS 18+)

/// Bridges the iOS 18 `onScrollPhaseChange` API to `FeedEngine.updateVelocity`.
/// On iOS 17, velocity detection is unavailable — the engine uses its default depth.
private struct ScrollVelocityModifier: ViewModifier {
    let feedEngine: FeedEngine

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, newPhase, context in
                if newPhase == .decelerating, let v = context.velocity {
                    Task { await feedEngine.updateVelocity(v.dy) }
                } else if newPhase == .idle {
                    Task { await feedEngine.updateVelocity(0) }
                }
            }
        } else {
            content
        }
    }
}

#if DEBUG
#Preview {
    DiscoverView()
        .modelContainer(PreviewSampleData.container)
}
#endif
