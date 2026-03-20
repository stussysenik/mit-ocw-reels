import SwiftUI

/// Root view — TabView with two tabs:
/// 1. Discover: random lecture reels (TikTok-style vertical feed)
/// 2. Courses: browse by department → drill into course-specific reels
struct ContentView: View {
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
        .tint(.red)
        .preferredColorScheme(.light)
    }
}
