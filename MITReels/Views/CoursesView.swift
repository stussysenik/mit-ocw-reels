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
    @State private var cachedSourceData: [(source: UniversitySource, courses: [Course], lectureCount: Int, departments: [String])] = []
    @AppStorage("autoplayEnabled") private var autoplayEnabled = true
    @AppStorage("captionsEnabled") private var captionsEnabled = true
    @AppStorage("hdOnWifi") private var hdOnWifi = true
    @AppStorage("courseViewMode") private var courseViewMode = "list"
    @StateObject private var sourcePrefs = SourcePreferences.shared
    @StateObject private var feedPrefs = FeedPreferences.shared

    private func recomputeSchoolData() {
        // MIT courses only — filtered to sourceId == "mit"
        let mitCourses = courses.filter { $0.sourceId == "mit" }
        let filtered = searchText.isEmpty
            ? mitCourses
            : mitCourses.filter {
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

        recomputeSourceData()
    }

    private func recomputeSourceData() {
        let enabledIds = sourcePrefs.enabledSourceIds
        let nonMitCourses = courses.filter { $0.sourceId != "mit" && enabledIds.contains($0.sourceId) }
        let filtered = searchText.isEmpty
            ? nonMitCourses
            : nonMitCourses.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.courseNumber.localizedCaseInsensitiveContains(searchText)
                || $0.department.localizedCaseInsensitiveContains(searchText)
                || ($0.source.shortName.localizedCaseInsensitiveContains(searchText))
            }

        let bySource = Dictionary(grouping: filtered, by: \.sourceId)
        cachedSourceData = bySource.compactMap { (sourceId, sourceCourses) -> (source: UniversitySource, courses: [Course], lectureCount: Int, departments: [String])? in
            guard let source = UniversitySource(rawValue: sourceId) else { return nil }
            // Skip expensive lectures?.count relationship loading — estimate from course count
            let departments = Array(Set(sourceCourses.map(\.department))).filter { !$0.isEmpty }.sorted()
            return (source: source, courses: sourceCourses, lectureCount: sourceCourses.count * 3, departments: departments)
        }
        .sorted { $0.source.displayName < $1.source.displayName }
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
                        // MIT Schools
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

                        // More Sources — non-MIT universities
                        if !cachedSourceData.isEmpty {
                            HStack {
                                Text("More Sources")
                                    .font(.headline)
                                    .foregroundStyle(CarbonColor.textPrimary)
                                Spacer()
                            }
                            .padding(.top, Spacing.sm)

                            ForEach(cachedSourceData, id: \.source) { data in
                                NavigationLink(destination: SourceDetailView(
                                    source: data.source,
                                    courses: data.courses
                                )) {
                                    SourceCardView(
                                        source: data.source,
                                        courseCount: data.courses.count,
                                        lectureCount: data.lectureCount,
                                        departments: data.departments
                                    )
                                }
                                .buttonStyle(.plain)
                            }
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
            .sheet(isPresented: $showSettings, onDismiss: {
                recomputeSourceData()
            }) {
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

                    Toggle(isOn: $captionsEnabled) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "captions.bubble")
                                .foregroundStyle(CarbonColor.interactive)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Captions")
                                    .font(.body)
                                    .foregroundStyle(CarbonColor.textPrimary)
                                Text("Show English subtitles on lecture videos")
                                    .font(.caption)
                                    .foregroundStyle(CarbonColor.textSecondary)
                            }
                        }
                    }
                    .tint(CarbonColor.interactive)
                    .accessibilityIdentifier("captionsToggle")

                    Toggle(isOn: $hdOnWifi) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "wifi")
                                .foregroundStyle(CarbonColor.interactive)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HD on WiFi")
                                    .font(.body)
                                    .foregroundStyle(CarbonColor.textPrimary)
                                Text("Highest quality on WiFi, lower on cellular")
                                    .font(.caption)
                                    .foregroundStyle(CarbonColor.textSecondary)
                            }
                        }
                    }
                    .tint(CarbonColor.interactive)
                } header: {
                    Text("Playback").sectionHeader()
                }

                SourceFilterSection(sourcePrefs: sourcePrefs)

                Section {
                    Picker("Default View", selection: $courseViewMode) {
                        Label("List", systemImage: "list.bullet").tag("list")
                        Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Course Browser").sectionHeader()
                }

                algorithmSection
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
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var algorithmSection: some View {
        let srcWeights = feedPrefs.adjustedSourceWeights
        let topicWeights = feedPrefs.adjustedTopicWeights

        if !srcWeights.isEmpty || !topicWeights.isEmpty {
            Section {
                ForEach(srcWeights, id: \.id) { item in
                    HStack {
                        if let src = UniversitySource(rawValue: item.id) {
                            Circle().fill(src.brandColor).frame(width: 8, height: 8)
                            Text(src.shortName).font(.body).foregroundStyle(CarbonColor.textPrimary)
                        } else {
                            Text(item.id).font(.body).foregroundStyle(CarbonColor.textPrimary)
                        }
                        Spacer()
                        Text(String(format: "%.1fx", item.weight))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(item.weight > 1.0 ? .green : .red)
                    }
                }
                ForEach(topicWeights, id: \.id) { item in
                    HStack {
                        Image(systemName: "tag").foregroundStyle(CarbonColor.textSecondary)
                        Text(item.id).font(.body).foregroundStyle(CarbonColor.textPrimary)
                        Spacer()
                        Text(String(format: "%.1fx", item.weight))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(item.weight > 1.0 ? .green : .red)
                    }
                }
                Button("Reset to Defaults", role: .destructive) {
                    feedPrefs.resetToDefaults()
                }
            } header: {
                Text("Feed Algorithm").sectionHeader()
            }
        }
    }
}

#if DEBUG
#Preview {
    CoursesView()
        .modelContainer(PreviewSampleData.container)
}
#endif
