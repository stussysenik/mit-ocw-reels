import SwiftUI

/// Course-specific lecture reels — same TikTok-style paging but filtered to one course.
/// Navigated to from CoursesView when user taps a specific course.
struct CourseReelsView: View {
    let course: Course

    private var lectures: [Lecture] {
        course.lectures ?? []
    }

    var body: some View {
        Group {
            if lectures.isEmpty {
                ContentUnavailableView(
                    "No Lectures",
                    systemImage: "video.slash",
                    description: Text("This course has no lecture videos yet.")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(lectures, id: \.youtubeId) { lecture in
                            ReelView(lecture: lecture)
                                .containerRelativeFrame(.vertical)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(course.courseNumber)
        .navigationBarTitleDisplayMode(.inline)
    }
}
