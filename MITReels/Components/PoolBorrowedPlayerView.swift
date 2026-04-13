import SwiftUI
import UIKit

/// Thin SwiftUI wrapper that borrows a pool-owned WebView based on the
/// cell's relative position from the current visible center. The pool
/// owns the WebView; this representable just re-parents it.
///
/// Keying: the cell passes its `relativePosition` computed from
/// `visibleIndex - cellIndex`. The pool returns the WebView for that
/// slot. When the cell recycles (scrolls out of the ±2 window), the
/// pool returns nil and the representable presents an empty container.
struct PoolBorrowedPlayerView: UIViewRepresentable {
    let relativePosition: Int

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isOpaque = false
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // Remove any previously attached WebView (from a prior shift).
        for sub in container.subviews { sub.removeFromSuperview() }

        guard let slot = ReelPlayerPool.shared.playerView(forRelativePosition: relativePosition) else {
            return
        }

        // Re-parent the pool's WebView into our container.
        slot.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(slot)
        NSLayoutConstraint.activate([
            slot.topAnchor.constraint(equalTo: container.topAnchor),
            slot.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            slot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            slot.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
