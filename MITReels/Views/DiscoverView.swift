import SwiftUI
import SwiftData

/// Discover tab — randomized lecture reels in a doom-scroll vertical paging feed.
///
/// Uses iOS 17+ `ScrollView` with `.scrollTargetBehavior(.paging)` for native
/// snap-to-page. One scroll = one page. Haptic feedback on each page change.
/// White background matches the NASA-inspired light aesthetic.
struct DiscoverView: View {
    @Query private var lectures: [Lecture]

    @State private var shuffledLectures: [Lecture] = []
    @State private var visibleId: String?

    @AppStorage("autoplayEnabled") private var autoplayEnabled = true

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        Group {
            if shuffledLectures.isEmpty {
                VStack(spacing: Spacing.md) {
                    ProgressView()
                        .tint(CarbonColor.interactive)
                    Text("Loading lectures...")
                        .font(.subheadline)
                        .foregroundStyle(CarbonColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CarbonColor.reelBackground)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(shuffledLectures, id: \.youtubeId) { lecture in
                            ReelView(
                                lecture: lecture,
                                isVisible: visibleId == lecture.youtubeId,
                                autoplayEnabled: autoplayEnabled
                            )
                            .containerRelativeFrame(.vertical)
                            .id(lecture.youtubeId)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $visibleId)
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .vertical)
                .background(CarbonColor.reelBackground)
            }
        }
        .onAppear {
            haptic.prepare()
            if shuffledLectures.isEmpty && !lectures.isEmpty {
                shuffledLectures = lectures.shuffled()
            }
        }
        .onChange(of: lectures.count) { _, newCount in
            if newCount > 0 && shuffledLectures.isEmpty {
                shuffledLectures = lectures.shuffled()
            }
        }
        .onChange(of: visibleId) { _, _ in
            haptic.impactOccurred()
            haptic.prepare()
        }
    }
}

#if DEBUG
#Preview {
    DiscoverView()
        .modelContainer(PreviewSampleData.container)
}
#endif
