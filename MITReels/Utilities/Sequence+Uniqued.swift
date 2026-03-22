import Foundation

extension Sequence {
    /// Returns an array with duplicate elements removed, preserving order.
    /// Uses the provided closure to extract the key for uniqueness comparison.
    func uniqued<T: Hashable>(by key: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert(key($0)).inserted }
    }
}
