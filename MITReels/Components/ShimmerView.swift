import SwiftUI

/// A shimmer loading placeholder for the video area.
///
/// Uses a repeating linear gradient animation that slides across the
/// rounded rectangle, giving users a visual cue that content is loading.
/// Built with Carbon Design tokens for consistent styling.
struct ShimmerView: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(CarbonColor.layerHover)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.6), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: animating ? geo.size.width : -geo.size.width)
                    .mask(Rectangle())
                )
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        animating = true
                    }
                }
        }
    }
}
