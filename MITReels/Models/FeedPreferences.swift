import Foundation

/// Immutable snapshot of feed weights — copied once per batch to avoid repeated UserDefaults reads.
/// Lives alongside `FeedPreferences` which produces it via `snapshot()`.
struct WeightSnapshot: Sendable {
    let sourceWeights: [String: Double]
    let topicWeights: [String: Double]
    let blockedIds: Set<String>

    func weight(sourceId: String, topic: String) -> Double {
        (sourceWeights[sourceId] ?? 1.0) * (topicWeights[topic] ?? 1.0)
    }
}

/// Local feed recommendation engine — tracks thumbs-up/down signals to weight
/// source and topic preferences. Weights bias the Discovery feed's random sampling.
///
/// Weights range [0.1, 3.0] with default 1.0. Thumbs-up adds +0.1, thumbs-down subtracts -0.2.
/// A source at 2.0x is twice as likely to appear as one at 1.0x.
@MainActor
final class FeedPreferences: ObservableObject {
    static let shared = FeedPreferences()
    private init() {}

    private let blockedKey = "blockedVideoIds"
    private let sourceWeightsKey = "feedSourceWeights"
    private let topicWeightsKey = "feedTopicWeights"

    // MARK: - Blocked Videos

    var blockedIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: blockedKey); objectWillChange.send() }
    }

    // MARK: - Source Weights

    private var sourceWeights: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: sourceWeightsKey) as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: sourceWeightsKey) }
    }

    func sourceWeight(for sourceId: String) -> Double {
        sourceWeights[sourceId] ?? 1.0
    }

    // MARK: - Topic Weights

    private var topicWeights: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: topicWeightsKey) as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: topicWeightsKey) }
    }

    func topicWeight(for topic: String) -> Double {
        guard !topic.isEmpty else { return 1.0 }
        return topicWeights[topic] ?? 1.0
    }

    // MARK: - Combined Weight

    func weight(for sourceId: String, topic: String) -> Double {
        sourceWeight(for: sourceId) * topicWeight(for: topic)
    }

    // MARK: - Actions

    func thumbsUp(sourceId: String, topic: String) {
        adjustWeight(&sourceWeights, key: sourceWeightsKey, id: sourceId, delta: 0.1)
        if !topic.isEmpty { adjustWeight(&topicWeights, key: topicWeightsKey, id: topic, delta: 0.1) }
        objectWillChange.send() // Single send after all mutations
    }

    func thumbsDown(videoId: String, sourceId: String, topic: String) {
        // Block without triggering objectWillChange from the setter
        var blocked = Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
        blocked.insert(videoId)
        UserDefaults.standard.set(Array(blocked), forKey: blockedKey)
        adjustWeight(&sourceWeights, key: sourceWeightsKey, id: sourceId, delta: -0.2)
        if !topic.isEmpty { adjustWeight(&topicWeights, key: topicWeightsKey, id: topic, delta: -0.2) }
        objectWillChange.send() // Single send after all mutations
    }

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: blockedKey)
        UserDefaults.standard.removeObject(forKey: sourceWeightsKey)
        UserDefaults.standard.removeObject(forKey: topicWeightsKey)
        objectWillChange.send()
    }

    func resetSourceWeight(_ sourceId: String) {
        var w = sourceWeights; w.removeValue(forKey: sourceId)
        UserDefaults.standard.set(w, forKey: sourceWeightsKey)
        objectWillChange.send()
    }

    func resetTopicWeight(_ topic: String) {
        var w = topicWeights; w.removeValue(forKey: topic)
        UserDefaults.standard.set(w, forKey: topicWeightsKey)
        objectWillChange.send()
    }

    /// Non-default weights for display in settings. Returns (id, weight) pairs sorted by weight.
    var adjustedSourceWeights: [(id: String, weight: Double)] {
        sourceWeights.filter { abs($0.value - 1.0) > 0.01 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    var adjustedTopicWeights: [(id: String, weight: Double)] {
        topicWeights.filter { abs($0.value - 1.0) > 0.01 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    // MARK: - Snapshot

    /// Immutable copy of current weights for off-main-thread batch computation.
    /// Avoids N×UserDefaults reads per weighted shuffle — snapshot once, use many.
    func snapshot() -> WeightSnapshot {
        WeightSnapshot(
            sourceWeights: sourceWeights,
            topicWeights: topicWeights,
            blockedIds: blockedIds
        )
    }

    // MARK: - Private

    private func adjustWeight(_ dict: inout [String: Double], key: String, id: String, delta: Double) {
        let current = dict[id] ?? 1.0
        dict[id] = min(3.0, max(0.1, current + delta))
        UserDefaults.standard.set(dict, forKey: key)
    }
}
