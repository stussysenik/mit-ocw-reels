import SwiftUI
import SwiftData

/// Courses tab — browse all courses grouped by department.
/// NavigationStack with search bar. Tap a course to enter its lecture reels feed.
struct CoursesView: View {
    @Query(sort: \Course.department) private var courses: [Course]
    @State private var searchText = ""

    /// Group courses by department for sectioned list
    private var groupedCourses: [(department: String, courses: [Course])] {
        let filtered = searchText.isEmpty
            ? courses
            : courses.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.courseNumber.localizedCaseInsensitiveContains(searchText)
                || $0.department.localizedCaseInsensitiveContains(searchText)
            }

        let grouped = Dictionary(grouping: filtered, by: \.department)
        return grouped
            .sorted { $0.key < $1.key }
            .map { (department: $0.key, courses: $0.value.sorted { $0.courseNumber < $1.courseNumber }) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedCourses, id: \.department) { group in
                    Section(group.department) {
                        ForEach(group.courses, id: \.courseNumber) { course in
                            NavigationLink(destination: CourseReelsView(course: course)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(course.courseNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fontDesign(.monospaced)
                                    Text(course.title)
                                        .font(.body)
                                        .lineLimit(2)
                                    if let count = course.lectures?.count, count > 0 {
                                        Text("\(count) lecture\(count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Courses")
            .searchable(text: $searchText, prompt: "Search courses...")
            .overlay {
                if courses.isEmpty {
                    ContentUnavailableView(
                        "No Courses",
                        systemImage: "book.closed",
                        description: Text("Course data is loading...")
                    )
                }
            }
        }
    }
}
