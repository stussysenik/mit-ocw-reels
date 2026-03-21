import SwiftUI

/// Course-specific lecture reels — same TikTok-style paging but filtered to one course.
/// Sorted by lectureNumber for sequential viewing.
struct CourseReelsView: View {
    let course: Course

    private var lectures: [Lecture] {
        (course.lectures ?? []).sorted { $0.lectureNumber < $1.lectureNumber }
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
                #if os(iOS)
                .ignoresSafeArea(edges: .bottom)
                #endif
            }
        }
        .navigationTitle(course.courseNumber)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
