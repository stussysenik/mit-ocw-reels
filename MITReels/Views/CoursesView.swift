import SwiftUI
import SwiftData

/// Courses tab — School Hub landing page.
///
/// Displays 5 MIT School cards with gradient backgrounds, course/lecture
/// counts, and department pills. Tapping a card navigates to
/// SchoolDetailView for that school's courses.
///
/// Follows the MIT Registrar's five-school hierarchy:
/// Engineering, Science, Architecture & Planning, Humanities, Cross-Disciplinary.
struct CoursesView: View {
    @Query(sort: \Course.department) private var courses: [Course]
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var cachedSchoolData: [(school: MITSchool, courses: [Course], lectureCount: Int, departments: [String])] = []
    @AppStorage("autoplayEnabled") private var autoplayEnabled = true
    @AppStorage("courseViewMode") private var courseViewMode = "list"

    private func recomputeSchoolData() {
        let filtered = searchText.isEmpty
            ? courses
            : courses.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.courseNumber.localizedCaseInsensitiveContains(searchText)
                || $0.department.localizedCaseInsensitiveContains(searchText)
                || MITSchool.from(courseNumber: $0.courseNumber).shortName
                    .localizedCaseInsensitiveContains(searchText)
            }

        cachedSchoolData = MITSchool.allCases.compactMap { school in
            let schoolCourses = filtered.filter {
                MITSchool.from(courseNumber: $0.courseNumber) == school
            }
            guard !schoolCourses.isEmpty else { return nil }
            let lectureCount = schoolCourses.reduce(0) { $0 + ($1.lectures?.count ?? 0) }
            let departments = Array(Set(schoolCourses.map(\.department))).filter { !$0.isEmpty }.sorted()
            return (school: school, courses: schoolCourses, lectureCount: lectureCount, departments: departments)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if cachedSchoolData.isEmpty {
                    ContentUnavailableView(
                        "No Courses",
                        systemImage: "book.closed",
                        description: Text(courses.isEmpty ? "Course data is loading..." : "No results for \"\(searchText)\"")
                    )
                    .tint(CarbonColor.interactive)
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    VStack(spacing: Spacing.md) {
                        ForEach(cachedSchoolData, id: \.school) { data in
                            NavigationLink(destination: SchoolDetailView(
                                school: data.school,
                                courses: data.courses
                            )) {
                                SchoolCardView(
                                    school: data.school,
                                    courseCount: data.courses.count,
                                    lectureCount: data.lectureCount,
                                    departments: data.departments
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
            }
            .background(CarbonColor.background)
            .navigationTitle("Courses")
            .searchable(text: $searchText, prompt: "Search courses or schools...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(CarbonColor.textSecondary)
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
            .onAppear { recomputeSchoolData() }
            .onChange(of: searchText) { _, _ in recomputeSchoolData() }
            .onChange(of: courses.count) { _, _ in recomputeSchoolData() }
        }
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $autoplayEnabled) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "play.circle")
                                .foregroundStyle(CarbonColor.interactive)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Autoplay Videos")
                                    .font(.body)
                                    .foregroundStyle(CarbonColor.textPrimary)
                                Text("Automatically play videos when scrolling")
                                    .font(.caption)
                                    .foregroundStyle(CarbonColor.textSecondary)
                            }
                        }
                    }
                    .tint(CarbonColor.interactive)
                    .accessibilityIdentifier("autoplayToggle")
                } header: {
                    Text("Playback")
                        .font(.caption2)
                        .foregroundStyle(CarbonColor.textLabel)
                        .textCase(.uppercase)
                        .tracking(1)
                }

                Section {
                    Picker("Default View", selection: $courseViewMode) {
                        Label("List", systemImage: "list.bullet").tag("list")
                        Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Course Browser")
                        .font(.caption2)
                        .foregroundStyle(CarbonColor.textLabel)
                        .textCase(.uppercase)
                        .tracking(1)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                        .foregroundStyle(CarbonColor.interactive)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#if DEBUG
#Preview {
    CoursesView()
        .modelContainer(PreviewSampleData.container)
}
#endif
