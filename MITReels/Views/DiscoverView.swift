import SwiftUI
import SwiftData

/// Discover tab — random lecture reels in a TikTok-style vertical paging feed.
/// Uses iOS 17+ ScrollView with .scrollTargetBehavior(.paging) for native snap-to-page.
/// Filters by enabled sources from SourceSettings.
struct DiscoverView: View {
    @Query private var lectures: [Lecture]
    @State private var shuffledLectures: [Lecture] = []
    private var settings = SourceSettings.shared

    /// Lectures filtered to enabled sources only
    private var filteredLectures: [Lecture] {
        lectures.filter { settings.isEnabled($0.source) }
    }

    var body: some View {
        Group {
            if shuffledLectures.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading lectures...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
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
                .refreshable {
                    shuffledLectures = filteredLectures.shuffled()
                }
            }
        }
        .onAppear {
            if shuffledLectures.isEmpty && !filteredLectures.isEmpty {
                shuffledLectures = filteredLectures.shuffled()
            }
        }
        .onChange(of: lectures.count) { _, newCount in
            if newCount > 0 && shuffledLectures.isEmpty {
                shuffledLectures = filteredLectures.shuffled()
            }
        }
    }
}
