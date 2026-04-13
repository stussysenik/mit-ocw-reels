import Foundation

/// Pure-function snap-to-index policy.
///
/// Given a current scroll offset, a velocity estimate, and page geometry,
/// returns the index the scroller should settle on. Single-step: at most
/// one page advance per call. Clamps to `[0, itemCount - 1]`.
enum SnapTarget {
    /// - Parameters:
    ///   - offset: Current scroll offset in points.
    ///   - velocity: Measured velocity in points/sec (positive = forward).
    ///   - pageHeight: Height of a single page in points.
    ///   - itemCount: Total number of pages.
    ///   - flickThreshold: Velocity magnitude above which we advance by one
    ///     page rather than snapping to the nearest. Default 500 pts/sec.
    static func nextIndex(
        from offset: Double,
        velocity: Double,
        pageHeight: Double,
        itemCount: Int,
        flickThreshold: Double = 500
    ) -> Int {
        guard itemCount > 0, pageHeight > 0 else { return 0 }
        let current = Int((offset / pageHeight).rounded())
        let raw: Int
        if abs(velocity) < flickThreshold {
            raw = current
        } else if velocity > 0 {
            raw = current + 1
        } else {
            raw = current - 1
        }
        return max(0, min(itemCount - 1, raw))
    }
}
