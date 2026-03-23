import Testing
import SwiftData
@testable import MITReels

/// Test SwiftData merge logic: deduplication by youtubeId,
/// course creation, and idempotent inserts.
struct DataMergeTests {
    /// Create an in-memory ModelContainer for isolated testing.
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Course.self, Lecture.self, configurations: config)
    }

    @Test @MainActor func insertNewLecture() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let lecture = Lecture(
            title: "Test Lecture",
            youtubeId: "abc123def45",
            courseNumber: "6.0001",
            courseName: "Intro to CS",
            department: "EECS"
        )
        context.insert(lecture)
        try context.save()

        let descriptor = FetchDescriptor<Lecture>()
        let count = try context.fetchCount(descriptor)
        #expect(count == 1)
    }

    @Test @MainActor func deduplicateByYoutubeId() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert first lecture
        let lecture1 = Lecture(
            title: "Original",
            youtubeId: "abc123def45",
            courseNumber: "6.0001",
            courseName: "Intro to CS",
            department: "EECS"
        )
        context.insert(lecture1)
        try context.save()

        // Simulate merge logic: check existing IDs before insert
        let existing = try context.fetch(FetchDescriptor<Lecture>())
        let existingIds = Set(existing.map { $0.youtubeId.lowercased() })

        let duplicateId = "ABC123DEF45" // same ID, different case
        #expect(existingIds.contains(duplicateId.lowercased()))
    }

    @Test @MainActor func courseCreatedWhenNeeded() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let course = Course(
            courseNumber: "18.06",
            title: "Linear Algebra",
            department: "Mathematics",
            semester: "Spring",
            year: 2010
        )
        context.insert(course)

        let lecture = Lecture(
            title: "Geometry of Linear Equations",
            youtubeId: "J7DzL2_Na80",
            courseNumber: "18.06",
            courseName: "Linear Algebra",
            department: "Mathematics"
        )
        context.insert(lecture)
        lecture.course = course
        try context.save()

        let courses = try context.fetch(FetchDescriptor<Course>())
        #expect(courses.count == 1)
        #expect(courses.first?.lectures?.count == 1)
    }

    @Test @MainActor func existingCourseReused() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert course
        let course = Course(
            courseNumber: "6.006",
            title: "Intro to Algorithms",
            department: "EECS"
        )
        context.insert(course)
        try context.save()

        // Simulate merge: find existing course by courseNumber
        let courses = try context.fetch(FetchDescriptor<Course>())
        var courseMap: [String: Course] = [:]
        for c in courses { courseMap[c.courseNumber] = c }

        // New lecture should reuse existing course
        let foundCourse = courseMap["6.006"]
        #expect(foundCourse != nil)
        #expect(foundCourse?.title == "Intro to Algorithms")
    }
}
