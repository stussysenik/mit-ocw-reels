import SwiftUI
import SwiftData

/// App entry point — configures SwiftData ModelContainer and seeds data on first launch.
/// Container is created explicitly in init() so seeding runs synchronously on mainContext,
/// ensuring @Query picks up the data immediately when views appear.
@main
struct MITReelsApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Course.self, Lecture.self)
            MITReelsApp.seedDataIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    // MARK: - Seed Data Loader

    /// Loads bundled seed_data.json into SwiftData on first launch.
    /// Uses mainContext so @Query sees the data immediately.
    /// Checks if any lectures exist — if so, skips seeding (idempotent).
    @MainActor
    private static func seedDataIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Lecture>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        guard let url = Bundle.main.url(forResource: "seed_data", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("seed_data.json not found in bundle")
            return
        }

        guard let seed = try? JSONDecoder().decode(SeedData.self, from: data) else {
            print("Failed to decode seed_data.json")
            return
        }

        // Insert courses first, build lookup by courseNumber
        var courseMap: [String: Course] = [:]
        for seedCourse in seed.courses {
            let course = Course(
                courseNumber: seedCourse.courseNumber,
                title: seedCourse.title,
                department: seedCourse.department,
                semester: seedCourse.semester,
                year: seedCourse.year
            )
            context.insert(course)
            courseMap[seedCourse.courseNumber] = course
        }

        // Insert lectures, linking to their parent course
        for seedLecture in seed.lectures {
            let lecture = Lecture(
                title: seedLecture.title,
                youtubeId: seedLecture.youtubeId,
                courseNumber: seedLecture.courseNumber,
                courseName: seedLecture.courseName,
                department: seedLecture.department,
                semester: seedLecture.semester,
                year: seedLecture.year,
                ocwUrl: seedLecture.ocwUrl,
                topicName: seedLecture.topicName
            )
            context.insert(lecture)

            if let course = courseMap[seedLecture.courseNumber] {
                lecture.course = course
            }
        }

        try? context.save()
        print("Seeded \(seed.lectures.count) lectures across \(seed.courses.count) courses")
    }
}

// MARK: - Seed Data Codable Types

private struct SeedData: Decodable {
    let lectures: [SeedLecture]
    let courses: [SeedCourse]
}

private struct SeedLecture: Decodable {
    let title: String
    let youtubeId: String
    let courseNumber: String
    let courseName: String
    let department: String
    let semester: String
    let year: Int
    let ocwUrl: String
    let topicName: String
}

private struct SeedCourse: Decodable {
    let courseNumber: String
    let title: String
    let department: String
    let semester: String
    let year: Int
}
