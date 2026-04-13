import SwiftUI
import SwiftData

/// Root view — TabView with two tabs:
/// 1. Discover: random lecture reels (TikTok-style vertical feed)
/// 2. Courses: browse by department -> drill into course-specific reels
///
/// Design: Carbon interactive accent (MIT Cardinal) on tab bar.
/// Light mode only — Carbon White theme tokens assume a light surface.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "flame.fill")
                }

            CoursesView()
                .tabItem {
                    Label("Courses", systemImage: "book.fill")
                }
        }
        .tint(CarbonColor.interactive)
        .preferredColorScheme(.light)
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewSampleData.container)
}
#endif
