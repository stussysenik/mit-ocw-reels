import Foundation
import SwiftUI

/// Interaction types for real-time weight adaptation.
enum FeedInteraction {
    case thumbsUp
    case thumbsDown
    case fastSkip   // appeared < 1.5s — gentle negative
    case longWatch  // appeared > 30s — gentle positive
}

/// Lightweight, Sendable projection of a Lecture for crossing actor boundaries.
/// FeedEngine works entirely with FeedItems — no @Model objects inside the actor.
struct FeedItem: Sendable {
    let youtubeId: String
    let sourceId: String
    let department: String
    let courseNumber: String
}

/// Actor-isolated feed computation engine with a sliding-window pipeline.
///
/// Replaces the static 200-item shuffled array with a continuous probabilistic
/// sliding window. Batches of 10 items are computed using the latest interaction
/// weights, so a thumbs-up at position 5 influences what appears at position 15.
///
/// Velocity-aware: normal scrolling keeps 10 items buffered; a fast fling
/// expands the buffer to 25-30 items using a lightweight fast-path shuffle.
///
/// Thread safety: operates on `FeedItem` value types only — no @Model objects
/// cross the actor boundary. DiscoverView maps IDs back to Lecture for display.
actor FeedEngine {

    // MARK: - Configuration

    private let batchSize = 10
    private let normalDepth = 10
    private let maxDepth = 30
    private let refillThreshold = 3
    private let maxPerCourse = 3

    // MARK: - State

    private var buffer: [FeedItem] = []
    private var weights: WeightSnapshot = .init(sourceWeights: [:], topicWeights: [:], blockedIds: [])
    /// Session-local soft weight adjustments (not persisted).
    private var softSourceAdj: [String: Double] = [:]
    private var softTopicAdj: [String: Double] = [:]
    /// Tracks every youtubeId served this session — prevents repeats until pool exhaustion.
    private var seen: Set<String> = []
    /// Pre-filtered eligible items grouped by source, each course-capped.
    private var sourcePools: [String: [FeedItem]] = [:]
    private var enabledSources: Set<String> = []
    private var targetDepth: Int = 10
    /// Trailing history of consumed reels — allows backward scroll to recent items.
    private var history: [FeedItem] = []
    private let historyLimit = 5
    /// Published snapshot for DiscoverView to read — list of youtubeIds in display order.
    private var _displayWindow: [String] = []

    // MARK: - Public API

    /// One-time setup: filter eligible lectures, build source pools, fill initial buffer.
    func bootstrap(
        items: [FeedItem],
        feedPrefs: FeedPreferences,
        sourcePrefs: SourcePreferences
    ) async {
        self.weights = await feedPrefs.snapshot()
        self.enabledSources = await sourcePrefs.enabledSourceIds
        rebuildPools(from: items)
        buffer.removeAll()
        seen.removeAll()
        history.removeAll()
        softSourceAdj.removeAll()
        softTopicAdj.removeAll()
        targetDepth = normalDepth
        fillBuffer(toDepth: normalDepth)
        rebuildDisplay()
    }

    /// Call when the underlying lectures array changes (new seed data, validation removals).
    func updateItems(_ items: [FeedItem]) {
        rebuildPools(from: items)
        if buffer.count < targetDepth {
            fillBuffer(toDepth: targetDepth)
            rebuildDisplay()
        }
    }

    /// Called when user blocks a video — remove from buffer immediately.
    func blockVideo(id: String) {
        buffer.removeAll { $0.youtubeId == id }
        history.removeAll { $0.youtubeId == id }
        seen.insert(id)
        weights = WeightSnapshot(
            sourceWeights: weights.sourceWeights,
            topicWeights: weights.topicWeights,
            blockedIds: weights.blockedIds.union([id])
        )
        for (key, pool) in sourcePools {
            sourcePools[key] = pool.filter { $0.youtubeId != id }
        }
        fillBuffer(toDepth: targetDepth)
        rebuildDisplay()
    }

    /// User scrolled forward — consume head into history, refill tail with fresh batch.
    func advance() {
        if !buffer.isEmpty {
            let consumed = buffer.removeFirst()
            history.append(consumed)
            if history.count > historyLimit { history.removeFirst() }
        }
        if buffer.count <= refillThreshold {
            fillBuffer(toDepth: targetDepth)
        }
        rebuildDisplay()
    }

    /// Record a user interaction to adapt upcoming content.
    func recordInteraction(_ type: FeedInteraction, sourceId: String, department: String) {
        switch type {
        case .thumbsUp:
            softSourceAdj[sourceId, default: 0] += 0.1
            softTopicAdj[department, default: 0] += 0.1
        case .thumbsDown:
            softSourceAdj[sourceId, default: 0] -= 0.2
            softTopicAdj[department, default: 0] -= 0.2
        case .fastSkip:
            softTopicAdj[department, default: 0] -= 0.05
        case .longWatch:
            softTopicAdj[department, default: 0] += 0.05
        }
    }

    /// Update velocity — adjusts target queue depth for fling-scroll resilience.
    func updateVelocity(_ pointsPerSecond: CGFloat) {
        let absV = abs(pointsPerSecond)
        if absV > 2000 { targetDepth = maxDepth }
        else if absV > 1000 { targetDepth = 15 }
        else { targetDepth = normalDepth }
        if buffer.count < targetDepth {
            fillBuffer(toDepth: targetDepth)
            rebuildDisplay()
        }
    }

    /// Refresh weight snapshot from FeedPreferences (call after explicit thumbs up/down).
    func refreshWeights(_ feedPrefs: FeedPreferences) async {
        self.weights = await feedPrefs.snapshot()
    }

    /// The current display window — ordered list of youtubeIds (history + buffer).
    /// DiscoverView maps these back to Lecture objects for rendering.
    var displayWindow: [String] { _displayWindow }

    /// IDs of the next N buffer items for thumbnail prefetching.
    func prefetchIds(count: Int = 6) -> [String] {
        buffer.prefix(count).map(\.youtubeId)
    }

    // MARK: - Core Algorithm

    /// Recompute display window from history + buffer. Single source of truth.
    private func rebuildDisplay() {
        _displayWindow = (history + buffer).map(\.youtubeId)
    }

    /// Fill the buffer up to `depth` items using stratified weighted batch sampling.
    private func fillBuffer(toDepth depth: Int) {
        while buffer.count < depth {
            let batch = computeBatch()
            if batch.isEmpty { break }
            buffer.append(contentsOf: batch)
        }
    }

    /// Compute a single batch of items using stratified source-fair weighted sampling.
    /// The `retried` flag prevents infinite recursion when all pool items are blocked.
    private func computeBatch(retried: Bool = false) -> [FeedItem] {
        let activeSourceCount = max(sourcePools.filter { !$0.value.isEmpty }.count, 1)
        let perSource = max(batchSize / activeSourceCount, 1)
        var batch: [FeedItem] = []
        var overflow: [FeedItem] = []

        for (_, pool) in sourcePools {
            let unseen = pool.filter { !seen.contains($0.youtubeId) && !weights.blockedIds.contains($0.youtubeId) }
            guard !unseen.isEmpty else { continue }
            let shuffled = unseen.weightedShuffle(by: effectiveWeight)
            batch.append(contentsOf: shuffled.prefix(perSource))
            if shuffled.count > perSource {
                overflow.append(contentsOf: shuffled.dropFirst(perSource))
            }
        }

        let remaining = batchSize - batch.count
        if remaining > 0 && !overflow.isEmpty {
            batch.append(contentsOf: overflow.weightedShuffle(by: effectiveWeight).prefix(remaining))
        }

        batch.shuffle()
        for item in batch { seen.insert(item.youtubeId) }

        // Reset seen on pool exhaustion — retried flag prevents infinite recursion
        // when all remaining items are in blockedIds.
        if batch.isEmpty && !retried && !seen.isEmpty && !sourcePools.values.allSatisfy({ $0.isEmpty }) {
            seen.removeAll()
            return computeBatch(retried: true)
        }

        return batch
    }

    /// Combined base + session-local soft weight for an item.
    private func effectiveWeight(for item: FeedItem) -> Double {
        weights.weight(sourceId: item.sourceId, topic: item.department)
        + (softSourceAdj[item.sourceId] ?? 0)
        + (softTopicAdj[item.department] ?? 0)
    }

    /// Build source pools from feed items — filter eligible, group by source, apply per-course cap.
    private func rebuildPools(from items: [FeedItem]) {
        let blocked = weights.blockedIds
        let eligible = items.filter {
            !blocked.contains($0.youtubeId) && enabledSources.contains($0.sourceId)
        }
        let bySource = Dictionary(grouping: eligible) { $0.sourceId }
        sourcePools = [:]
        for (sourceId, sourceItems) in bySource {
            let byCourse = Dictionary(grouping: sourceItems) { $0.courseNumber }
            var pool: [FeedItem] = []
            for (_, group) in byCourse {
                pool.append(contentsOf: group.shuffled().prefix(maxPerCourse))
            }
            sourcePools[sourceId] = pool
        }
    }
}
