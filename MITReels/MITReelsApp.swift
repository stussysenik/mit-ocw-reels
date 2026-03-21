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

    /// Loads bundled seed_data.json into SwiftData.
    /// Uses seed versioning: if the bundled seedVersion is higher than what's stored
    /// in UserDefaults, deletes all existing data and re-seeds.
    @MainActor
    private static func seedDataIfNeeded(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "seed_data", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("seed_data.json not found in bundle")
            return
        }

        guard let seed = try? JSONDecoder().decode(SeedData.self, from: data) else {
            print("Failed to decode seed_data.json")
            return
        }

        let storedVersion = UserDefaults.standard.integer(forKey: "seedDataVersion")
        let bundledVersion = seed.seedVersion ?? 1

        // Skip if already seeded with this version
        if storedVersion >= bundledVersion {
            let descriptor = FetchDescriptor<Lecture>()
            let existingCount = (try? context.fetchCount(descriptor)) ?? 0
            if existingCount > 0 { return }
        }

        // Clear existing data for re-seed
        if storedVersion > 0 {
            try? context.delete(model: Lecture.self)
            try? context.delete(model: Course.self)
        }

        // Insert courses first, build lookup by courseNumber
        var courseMap: [String: Course] = [:]
        for seedCourse in seed.courses {
            let course = Course(
                courseNumber: seedCourse.courseNumber,
                title: seedCourse.title,
                department: seedCourse.department,
                semester: seedCourse.semester,
                year: seedCourse.year,
                source: seedCourse.source ?? "mit-ocw"
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
                topicName: seedLecture.topicName,
                lectureNumber: seedLecture.lectureNumber ?? 0,
                source: seedLecture.source ?? "mit-ocw"
            )
            context.insert(lecture)

            if let course = courseMap[seedLecture.courseNumber] {
                lecture.course = course
            }
        }

        try? context.save()
        UserDefaults.standard.set(bundledVersion, forKey: "seedDataVersion")
        print("Seeded \(seed.lectures.count) lectures across \(seed.courses.count) courses (v\(bundledVersion))")
    }
}

// MARK: - Seed Data Codable Types

private struct SeedData: Decodable {
    let lectures: [SeedLecture]
    let courses: [SeedCourse]
    let seedVersion: Int?
    let sources: [SeedSource]?
}

private struct SeedSource: Decodable {
    let id: String
    let name: String
    let enabled: Bool
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
    let lectureNumber: Int?
    let source: String?
}

private struct SeedCourse: Decodable {
    let courseNumber: String
    let title: String
    let department: String
    let semester: String
    let year: Int
    let source: String?
}
