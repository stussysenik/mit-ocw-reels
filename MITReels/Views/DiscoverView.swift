import SwiftUI
import SwiftData

/// Discover tab — random lecture reels in a TikTok-style vertical paging feed.
/// Uses iOS 17+ ScrollView with .scrollTargetBehavior(.paging) for native snap-to-page.
struct DiscoverView: View {
    @Query private var lectures: [Lecture]
    @State private var shuffledLectures: [Lecture] = []

    var body: some View {
        Group {
            if shuffledLectures.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading lectures...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(shuffledLectures, id: \.youtubeId) { lecture in
                            ReelView(lecture: lecture)
                                .containerRelativeFrame(.vertical)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            if shuffledLectures.isEmpty && !lectures.isEmpty {
                shuffledLectures = lectures.shuffled()
            }
        }
        .onChange(of: lectures.count) { _, newCount in
            if newCount > 0 && shuffledLectures.isEmpty {
                shuffledLectures = lectures.shuffled()
            }
        }
    }
}
