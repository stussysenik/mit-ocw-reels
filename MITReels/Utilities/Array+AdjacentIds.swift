import Foundation

extension Array where Element == Lecture {
    /// Returns the YouTube ID of the lecture after the given visible ID.
    func nextId(after visibleId: String?) -> String? {
        guard let vid = visibleId,
              let idx = firstIndex(where: { $0.youtubeId == vid }),
              idx + 1 < count else { return nil }
        return self[idx + 1].youtubeId
    }
}

extension Sequence {
    /// Efraimidis-Spirakis weighted shuffle — higher-weighted elements appear earlier.
    /// The `weight` closure returns a raw weight; values are clamped to [0.1, 3.0].
    func weightedShuffle(by weight: (Element) -> Double) -> [Element] {
        map { elem in
            let w = Swift.min(3.0, Swift.max(0.1, weight(elem)))
            let key = pow(Double.random(in: 0.001...1.0), 1.0 / w)
            return (elem, key)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }
}
