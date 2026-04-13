import SwiftUI
import UIKit

/// SwiftUI-facing wrapper around `SlidingLoopHostScrollView`.
///
/// Usage:
///
///     SlidingLoop(items: items, visibleIndex: $visibleIndex) { item, isVisible in
///         ReelView(lecture: item, isVisible: isVisible, ...)
///     }
///
/// Rebuild policy: the `UIHostingController` list is rebuilt only when the
/// `items` array's id sequence changes. On every other call to
/// `updateUIViewController` we refresh cells in place so the SwiftUI content
/// sees the new `isVisible` flag without tearing down WKWebViews.
struct SlidingLoop<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    let items: [Item]
    @Binding var visibleIndex: Int
    @ViewBuilder let content: (Item, Bool) -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> SlidingLoopViewController {
        let vc = SlidingLoopViewController()
        let coordinator = context.coordinator
        vc.hostScrollView.onVisibleIndexChanged = { newIndex in
            // Update the binding through the coordinator's live parent snapshot.
            // SwiftUI will call updateUIViewController next, which refreshes
            // in-place cells with the new isVisible flags.
            if coordinator.parent.visibleIndex != newIndex {
                coordinator.parent.visibleIndex = newIndex
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: SlidingLoopViewController, context: Context) {
        // Keep the coordinator's snapshot of the parent struct current so the
        // scroll-callback closure always reads the latest binding.
        context.coordinator.parent = self

        let newIds = items.map { AnyHashable($0.id) }
        let structuralChange = context.coordinator.currentItemIds != newIds

        if structuralChange {
            let controllers: [UIHostingController<AnyView>] = items.enumerated().map { index, item in
                let isVisible = index == visibleIndex
                return UIHostingController(rootView: AnyView(content(item, isVisible)))
            }
            vc.hostScrollView.replaceCells(with: controllers, parent: vc)
            context.coordinator.currentItemIds = newIds

            if visibleIndex >= 0 && visibleIndex < items.count {
                vc.hostScrollView.jump(to: visibleIndex)
            }
        } else {
            // In-place refresh — update each cell's rootView with the latest
            // SwiftUI content, which reflects the new isVisible flag.
            for (index, item) in items.enumerated() {
                let isVisible = index == visibleIndex
                vc.hostScrollView.updateCell(at: index, with: AnyView(content(item, isVisible)))
            }
            // If the binding moved externally (e.g. dislike advance writes
            // visibleIndex directly), sync the scroll view.
            if vc.hostScrollView.visibleIndex != visibleIndex {
                vc.hostScrollView.jump(to: visibleIndex)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        var parent: SlidingLoop
        var currentItemIds: [AnyHashable] = []

        init(parent: SlidingLoop) {
            self.parent = parent
        }
    }
}

/// Container view controller that owns the scroll view and provides the
/// parent context that `UIHostingController` children require.
@MainActor
final class SlidingLoopViewController: UIViewController {
    let hostScrollView = SlidingLoopHostScrollView()

    override func loadView() {
        self.view = hostScrollView
    }
}
