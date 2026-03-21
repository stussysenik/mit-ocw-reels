import SwiftUI

/// A shimmer loading placeholder for the video area.
///
/// Uses a repeating linear gradient animation that slides across the
/// rounded rectangle, giving users a visual cue that content is loading.
/// Built with Carbon Design tokens for consistent styling.
struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CarbonColor.layerHover)
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.6), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(Rectangle())
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = UIScreen.main.bounds.width
                }
            }
    }
}
