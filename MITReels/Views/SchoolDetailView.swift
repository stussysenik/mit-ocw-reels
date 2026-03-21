import SwiftUI

/// Per-school course browser with list/grid toggle and search.
///
/// Navigated to from CoursesView's School Hub when user taps a school card.
/// Courses are grouped by department within the school. Users can switch
/// between list and grid views via a segmented picker in the toolbar.
struct SchoolDetailView: View {
    let school: MITSchool
    let courses: [Course]

    @State private var searchText = ""
    @AppStorage("courseViewMode") private var viewMode = "list"

    private var filteredCourses: [Course] {
        let sorted = courses.sorted { $0.courseNumber < $1.courseNumber }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.courseNumber.localizedCaseInsensitiveContains(searchText)
            || $0.department.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Courses grouped by department for the list view.
    private var groupedByDepartment: [(department: String, courses: [Course])] {
        let byDept = Dictionary(grouping: filteredCourses, by: \.department)
        return byDept
            .sorted { $0.key < $1.key }
            .map { (department: $0.key, courses: $0.value) }
    }

    var body: some View {
        Group {
            if viewMode == "grid" {
                gridView
            } else {
                listView
            }
        }
        .navigationTitle(school.shortName)
        .searchable(text: $searchText, prompt: "Search \(school.shortName)...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag("list")
                    Image(systemName: "square.grid.2x2").tag("grid")
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            ForEach(groupedByDepartment, id: \.department) { dept in
                Section {
                    ForEach(dept.courses, id: \.courseNumber) { course in
                        NavigationLink(destination: CourseReelsView(course: course)) {
                            courseRow(course)
                        }
                        .listRowBackground(CarbonColor.layer01)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(dept.department)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(school.color)
                }
            }
        }
        .listStyle(.plain)
        .background(CarbonColor.background)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ], spacing: Spacing.sm) {
                ForEach(filteredCourses, id: \.courseNumber) { course in
                    NavigationLink(destination: CourseReelsView(course: course)) {
                        CourseGridItemView(course: course, school: school)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(CarbonColor.background)
    }

    // MARK: - Course Row

    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(school.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(course.courseNumber)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(CarbonColor.textPrimary)

                Text(course.title)
                    .font(.body)
                    .foregroundStyle(CarbonColor.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let count = course.lectures?.count, count > 0 {
                        Text("\(count) lecture\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(CarbonColor.textPlaceholder)
                    }

                    if !course.semester.isEmpty && course.year > 0 {
                        Text("\u{00B7}")
                            .foregroundStyle(CarbonColor.textTertiary)
                        Text("\(course.semester) \(String(course.year))")
                            .font(.caption2)
                            .foregroundStyle(CarbonColor.textPlaceholder)
                    }

                    Text("\u{00B7}")
                        .foregroundStyle(CarbonColor.textTertiary)
                    Text(CourseLevel.from(courseNumber: course.courseNumber).rawValue)
                        .font(.caption2)
                        .foregroundStyle(CarbonColor.textPlaceholder)
                }
            }
            .padding(.leading, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
    }
}
