#if DEBUG
import SwiftUI

/// 20-cell tuning harness for `SlidingLoop`. DEBUG only.
///
/// Run in Xcode Preview OR as the root view in a one-off scheme to tune
/// `Spring.response` by feel. No real content — just alternating colors and
/// big index numbers so it's obvious which page you're on.
///
/// Expected landing: response ∈ [0.25, 0.32]. Start at 0.28.
struct SlidingLoopPreviewHarness: View {
    private struct PreviewItem: Identifiable {
        let id: Int
        let color: Color
    }

    @State private var visibleIndex: Int = 0
    private let items: [PreviewItem] = (0..<20).map { i in
        PreviewItem(id: i, color: Color(
            hue: Double(i % 10) / 10.0,
            saturation: 0.7,
            brightness: 0.9
        ))
    }

    var body: some View {
        SlidingLoop(items: items, visibleIndex: $visibleIndex) { item, isVisible in
            ZStack {
                item.color.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("\(item.id)")
                        .font(.system(size: 140, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(isVisible ? "VISIBLE" : "…")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Text("idx: \(visibleIndex) / \(items.count - 1)")
                .font(.caption.monospaced())
                .padding(8)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
                .padding()
        }
    }
}

#Preview {
    SlidingLoopPreviewHarness()
}
#endif
