import SwiftUI

/// Per-school course browser with list/grid toggle, search, and department filter.
///
/// Navigated to from CoursesView's School Hub when user taps a school card.
/// Courses are grouped by department within the school. Users can:
/// - Switch between list and grid views via toolbar picker
/// - Filter by department via tappable section headers (list) or pill bar (grid)
/// - Search across title, courseNumber, department
struct SchoolDetailView: View {
    let school: MITSchool
    let courses: [Course]

    @State private var searchText = ""
    @State private var selectedDepartment: String? = nil
    @AppStorage("courseViewMode") private var viewMode = "list"

    // MARK: - Cached Computed Data (O(1) per render)

    @State private var cachedGroups: [(department: String, courses: [Course])] = []
    @State private var cachedDepartments: [String] = []

    /// O(1) per render — updated in recomputeGroups() and toggleDepartment().
    @State private var cachedDisplayedCourses: [Course] = []

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
        .onAppear { recomputeGroups() }
        .onChange(of: searchText) { _, _ in recomputeGroups() }
    }

    // MARK: - Data Computation

    private func recomputeGroups() {
        let sorted = courses.sorted { $0.courseNumber < $1.courseNumber }
        let filtered: [Course]
        if searchText.isEmpty {
            filtered = sorted
        } else {
            filtered = sorted.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.courseNumber.localizedCaseInsensitiveContains(searchText)
                || $0.department.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter out courses with empty department names
        let withDept = filtered.filter { !$0.department.isEmpty }

        let byDept = Dictionary(grouping: withDept, by: \.department)
        cachedGroups = byDept
            .sorted { $0.key < $1.key }
            .map { (department: $0.key, courses: $0.value) }
        cachedDepartments = cachedGroups.map(\.department)

        // Clear department filter if it no longer exists in filtered results
        if let sel = selectedDepartment, !cachedDepartments.contains(sel) {
            selectedDepartment = nil
        }

        updateDisplayedCourses()
    }

    private func updateDisplayedCourses() {
        if let dept = selectedDepartment {
            cachedDisplayedCourses = cachedGroups.first(where: { $0.department == dept })?.courses ?? []
        } else {
            cachedDisplayedCourses = cachedGroups.flatMap(\.courses)
        }
    }

    private func toggleDepartment(_ dept: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDepartment = selectedDepartment == dept ? nil : dept
            updateDisplayedCourses()
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            ForEach(cachedGroups, id: \.department) { dept in
                Section {
                    if selectedDepartment == nil || selectedDepartment == dept.department {
                        ForEach(dept.courses, id: \.courseNumber) { course in
                            NavigationLink(destination: CourseReelsView(course: course)) {
                                courseRow(course)
                            }
                            .listRowBackground(CarbonColor.layer01)
                            .listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    Button { toggleDepartment(dept.department) } label: {
                        HStack {
                            Text(dept.department)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(school.color)

                            Spacer()

                            if selectedDepartment == dept.department {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(CarbonColor.textPlaceholder)
                            }

                            Text("\(dept.courses.count)")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(CarbonColor.textPlaceholder)
                        }
                    }
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
            VStack(spacing: 0) {
                // Department filter pills
                if cachedDepartments.count > 1 {
                    departmentFilterBar
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm)
                ], spacing: Spacing.sm) {
                    ForEach(cachedDisplayedCourses, id: \.courseNumber) { course in
                        NavigationLink(destination: CourseReelsView(course: course)) {
                            CourseGridItemView(course: course, school: school)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
        }
        .background(CarbonColor.background)
    }

    private var departmentFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(cachedDepartments, id: \.self) { dept in
                    let isSelected = selectedDepartment == dept
                    Button { toggleDepartment(dept) } label: {
                        Text(dept)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isSelected ? .white : CarbonColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(school.color)
                                    : AnyShapeStyle(CarbonColor.layerHover)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
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
