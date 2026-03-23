import Foundation

extension Array where Element == Lecture {
    /// Returns the YouTube ID of the lecture after the given visible ID.
    func nextId(after visibleId: String?) -> String? {
        guard let vid = visibleId,
              let idx = firstIndex(where: { $0.youtubeId == vid }),
              idx + 1 < count else { return nil }
        return self[idx + 1].youtubeId
    }

    /// Weighted shuffle using Efraimidis-Spirakis reservoir sampling.
    /// Higher-weighted lectures are more likely to appear earlier.
    @MainActor func weightedShuffle(using prefs: FeedPreferences) -> [Element] {
        map { ($0, pow(Double.random(in: 0.001...1.0), 1.0 / prefs.weight(for: $0.sourceId, topic: $0.department))) }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }
}
