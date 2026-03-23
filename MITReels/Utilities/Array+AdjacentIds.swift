import Foundation

extension Array where Element == Lecture {
    /// Returns the (prev, next) YouTube IDs adjacent to the given visible ID.
    func adjacentIds(for visibleId: String?) -> (prev: String?, next: String?) {
        guard let vid = visibleId,
              let idx = firstIndex(where: { $0.youtubeId == vid }) else {
            return (nil, nil)
        }
        return (
            prev: idx > 0 ? self[idx - 1].youtubeId : nil,
            next: idx + 1 < count ? self[idx + 1].youtubeId : nil
        )
    }
}
