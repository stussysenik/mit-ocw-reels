import SwiftUI

/// Draggable timeline scrubber for video playback.
///
/// Shows a thin progress line (3pt) during playback that expands to 6pt + thumb
/// when the user drags. Sends `onSeek(seconds)` when the user lifts their finger.
/// Uses MIT Cardinal (CarbonColor.interactive) for the filled track.
struct TimelineScrubber: View {
    @Binding var currentTime: Double
    let duration: Double
    var onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragTime: Double = 0

    var body: some View {
        GeometryReader { geo in
            let displayTime = isDragging ? dragTime : currentTime
            let progress = duration > 0 ? min(1, max(0, displayTime / duration)) : 0

            VStack(spacing: 0) {
                Spacer()

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(CarbonColor.textTertiary.opacity(0.3))
                        .frame(height: isDragging ? 6 : 3)

                    // Filled track
                    Capsule()
                        .fill(CarbonColor.interactive)
                        .frame(width: max(0, geo.size.width * progress), height: isDragging ? 6 : 3)

                    // Thumb — visible when dragging
                    if isDragging {
                        Circle()
                            .fill(CarbonColor.interactive)
                            .frame(width: 14, height: 14)
                            .shadow(color: CarbonColor.interactive.opacity(0.3), radius: 4)
                            .offset(x: max(0, min(geo.size.width - 14, geo.size.width * progress - 7)))
                    }
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let pct = max(0, min(1, value.location.x / geo.size.width))
                            dragTime = pct * duration
                        }
                        .onEnded { value in
                            let pct = max(0, min(1, value.location.x / geo.size.width))
                            onSeek(pct * duration)
                            isDragging = false
                        }
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, Spacing.md)
    }
}

#if DEBUG
#Preview {
    VStack {
        Spacer()
        TimelineScrubber(
            currentTime: .constant(30),
            duration: 120,
            onSeek: { time in print("Seek to \(time)") }
        )
    }
    .background(Color.black.opacity(0.1))
}
#endif
