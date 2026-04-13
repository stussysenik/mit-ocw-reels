import UIKit
import SwiftUI
import QuartzCore

/// `UIScrollView` subclass that owns the physics-driven paging loop.
///
/// The host view:
/// - Delegates scroll callbacks to a `SlidingLoopStateMachine`.
/// - Runs a `DisplayLinkDriver` only while the machine is settling.
/// - Writes `contentOffset` via `setContentOffset(_:animated: false)` on each
///   tick, which keeps UIScrollView's internal state (delegate callbacks,
///   VoiceOver, content inset handling) consistent.
/// - Hosts each cell as its own `UIHostingController<AnyView>` positioned at
///   `y = index * pageHeight`. No recycling in pass 1.
///
/// The host view is non-generic. The SwiftUI wrapper in `SlidingLoop.swift`
/// erases the `Content` type into `AnyView` before handing off.
@MainActor
final class SlidingLoopHostScrollView: UIScrollView, UIScrollViewDelegate {
    // MARK: - Configuration

    /// Called when the scroll settles on a new visible index.
    var onVisibleIndexChanged: ((Int) -> Void)?

    // MARK: - Physics

    private var machine = SlidingLoopStateMachine(response: 0.28)
    private let displayLink = DisplayLinkDriver()

    // MARK: - Cell hosting

    private(set) var hostingControllers: [UIHostingController<AnyView>] = []
    private var itemCount: Int = 0
    private var lastKnownPageHeight: CGFloat = 0

    private(set) var visibleIndex: Int = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        delegate = self
        isPagingEnabled = false
        decelerationRate = .fast
        bounces = true
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never

        displayLink.onTick = { [weak self] dt in
            self?.handleTick(dt: dt)
        }
    }

    // MARK: - Hosting controller management

    /// Full replacement of the hosted cells. Called from the SwiftUI wrapper
    /// when the items array changes identity.
    func replaceCells(
        with newControllers: [UIHostingController<AnyView>],
        parent: UIViewController
    ) {
        // Tear down old
        for hc in hostingControllers {
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
        }
        hostingControllers.removeAll()

        // Attach new
        for hc in newControllers {
            parent.addChild(hc)
            hc.view.backgroundColor = .clear
            addSubview(hc.view)
            hc.didMove(toParent: parent)
            hostingControllers.append(hc)
        }
        itemCount = newControllers.count
        machine.itemCount = itemCount
        setNeedsLayout()
    }

    /// Update a single cell's rootView in place — used when `visibleIndex`
    /// changes so SwiftUI content sees the new `isVisible` flag without a
    /// full cell rebuild.
    func updateCell(at index: Int, with view: AnyView) {
        guard hostingControllers.indices.contains(index) else { return }
        hostingControllers[index].rootView = view
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let pageHeight = bounds.height
        let width = bounds.width
        guard pageHeight > 0 else { return }
        machine.pageHeight = Double(pageHeight)

        contentSize = CGSize(width: width, height: CGFloat(itemCount) * pageHeight)

        for (i, hc) in hostingControllers.enumerated() {
            hc.view.frame = CGRect(
                x: 0,
                y: CGFloat(i) * pageHeight,
                width: width,
                height: pageHeight
            )
        }

        if lastKnownPageHeight == 0 {
            // First layout — sync scroll offset to the current visibleIndex.
            // Covers the "scene storage restores a non-zero index before the
            // view has a height" case.
            machine.hardSnap(to: visibleIndex)
            setContentOffset(
                CGPoint(x: 0, y: CGFloat(visibleIndex) * pageHeight),
                animated: false
            )
        } else if lastKnownPageHeight != pageHeight {
            // Page height changed (rotation / split-screen resize) — re-snap.
            machine.hardSnap(to: visibleIndex)
            setContentOffset(
                CGPoint(x: 0, y: CGFloat(visibleIndex) * pageHeight),
                animated: false
            )
        }
        lastKnownPageHeight = pageHeight
    }

    // MARK: - External control

    /// Jump to a specific index without animation (called from bootstrap
    /// and from external advance-on-dislike code).
    func jump(to index: Int) {
        let clamped = max(0, min(itemCount - 1, index))
        guard clamped != visibleIndex else { return }
        visibleIndex = clamped
        machine.hardSnap(to: clamped)
        let y = CGFloat(clamped) * bounds.height
        setContentOffset(CGPoint(x: 0, y: y), animated: false)
        onVisibleIndexChanged?(clamped)
    }

    // MARK: - Tick

    private func handleTick(dt: CFTimeInterval) {
        let (offset, settledIndex) = machine.tick(dt: dt)
        setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        if let idx = settledIndex {
            displayLink.stop()
            updateVisibleIndex(to: max(0, min(itemCount - 1, idx)))
        }
    }

    private func updateVisibleIndex(to index: Int) {
        guard index != visibleIndex else { return }
        visibleIndex = index
        onVisibleIndexChanged?(index)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        machine.didScroll(
            offset: Double(scrollView.contentOffset.y),
            at: CACurrentMediaTime()
        )
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if displayLink.isRunning {
            displayLink.stop()
        }
        machine.willBeginDragging()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // 1. Kill Apple's deceleration by anchoring its target to now.
        targetContentOffset.pointee = scrollView.contentOffset

        // 2. Hand off to our state machine. It primes the spring internally.
        _ = machine.willEndDragging(offset: Double(scrollView.contentOffset.y))

        // 3. Start the tick.
        displayLink.start()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // No-op — we never use setContentOffset(_:, animated: true).
    }
}
