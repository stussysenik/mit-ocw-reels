import Testing
import SwiftData
@testable import MITReels

/// Tests for OCW slug parsing and lecture filtering logic.
struct OCWScraperTests {

    // MARK: - Lecture Filtering

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Course.self, Lecture.self, configurations: config)
    }

    @Test @MainActor func filterValidLectures_excludesPDFs() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let pdfLecture = Lecture(
            title: "decomposers.pdf",
            youtubeId: "abc123def45",
            courseNumber: "12.000",
            courseName: "Solving Complex Problems",
            department: "EAPS"
        )
        let validLecture = Lecture(
            title: "Introduction to Algorithms",
            youtubeId: "HtSuA80QTyo",
            courseNumber: "6.006",
            courseName: "Introduction to Algorithms",
            department: "EECS"
        )
        context.insert(pdfLecture)
        context.insert(validLecture)

        let all = [pdfLecture, validLecture]
        let filtered = DiscoverView.filterValidLectures(all)

        #expect(filtered.count == 1)
        #expect(filtered.first?.title == "Introduction to Algorithms")
    }

    @Test @MainActor func filterValidLectures_excludesEmptyYoutubeId() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let emptyIdLecture = Lecture(
            title: "Some Lecture",
            youtubeId: "",
            courseNumber: "6.006",
            courseName: "Intro to Algorithms",
            department: "EECS"
        )
        context.insert(emptyIdLecture)

        let filtered = DiscoverView.filterValidLectures([emptyIdLecture])
        #expect(filtered.isEmpty)
    }

    @Test @MainActor func filterValidLectures_excludesEmptyCourseNumber() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let orphanLecture = Lecture(
            title: "Orphan Lecture",
            youtubeId: "abc123def45",
            courseNumber: "",
            courseName: "Unknown Course",
            department: ""
        )
        context.insert(orphanLecture)

        let filtered = DiscoverView.filterValidLectures([orphanLecture])
        #expect(filtered.isEmpty)
    }

    @Test @MainActor func filterValidLectures_keepsValidLectures() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let lecture = Lecture(
            title: "Geometry of Linear Equations",
            youtubeId: "J7DzL2_Na80",
            courseNumber: "18.06",
            courseName: "Linear Algebra",
            department: "Mathematics"
        )
        context.insert(lecture)

        let filtered = DiscoverView.filterValidLectures([lecture])
        #expect(filtered.count == 1)
    }

    // MARK: - Display Label Logic

    @Test func displayLabel_validCourseNumber() {
        // Course number with a dot should display as-is
        let num = "6.006"
        let isEmpty = num.isEmpty || (!num.contains(".") && num.count > 8)
        #expect(!isEmpty)
    }

    @Test func displayLabel_garbledCourseNumber() {
        // Long string without dots should be detected as garbled
        let num = "MITRES6012INTROD"
        let isGarbled = num.isEmpty || (!num.contains(".") && num.count > 8)
        #expect(isGarbled)
    }

    @Test func displayLabel_emptyCourseNumber() {
        let num = ""
        let isGarbled = num.isEmpty || (!num.contains(".") && num.count > 8)
        #expect(isGarbled)
    }

    @Test func displayLabel_shortAlphaNumber() {
        // Short strings like "RES" without dots but ≤8 chars are OK
        let num = "MAS.S62"
        let isGarbled = num.isEmpty || (!num.contains(".") && num.count > 8)
        #expect(!isGarbled)
    }

    // MARK: - Course Page URL Extraction

    @Test func courseBaseString_extractsFromResourceURL() {
        let ocwUrl = "https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-spring-2020/resources/abc123/"
        let result = ReelView.courseBaseString(from: ocwUrl)
        #expect(result == "https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-spring-2020/")
    }

    @Test func courseBaseString_returnsNilForEmpty() {
        #expect(ReelView.courseBaseString(from: "") == nil)
    }

    @Test func courseBaseString_returnsNilForNoResources() {
        #expect(ReelView.courseBaseString(from: "https://ocw.mit.edu/courses/6-006/") == nil)
    }
}
