import SwiftUI
import SwiftData

/// App entry point — configures SwiftData ModelContainer and seeds data on first launch.
///
/// Three-phase content pipeline:
///   1. Synchronous seed from bundled seed_data.json (instant content on first launch)
///   2. Background oEmbed validation removes unavailable videos from seed data
///   3. Background OCW scraper expands the catalog (only validated videos inserted)
@main
struct MITReelsApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Course.self, Lecture.self)
            MITReelsApp.seedDataIfNeeded(context: container.mainContext)
            MITReelsApp.startBackgroundValidation(container: container)
            MITReelsApp.startBackgroundScrape(container: container)
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

    // MARK: - Background Video Validation

    /// Validates existing seed data videos via YouTube oEmbed API.
    /// Removes lectures whose videos are no longer available.
    /// Runs once per app install (tracked via UserDefaults).
    private static func startBackgroundValidation(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: "seedDataValidated") else { return }

        Task.detached(priority: .utility) {
            let scraper = OCWScraper()

            // Extract plain data on MainActor — never read @Model off-actor
            let videoEntries: [(id: String, needsInstructor: Bool)] = await MainActor.run {
                let descriptor = FetchDescriptor<Lecture>()
                let all = (try? container.mainContext.fetch(descriptor)) ?? []
                return all.map { ($0.youtubeId, $0.instructor.isEmpty) }
            }

            // Validate concurrently (bounded to 8) instead of sequentially
            var invalidIds: [String] = []
            var instructorUpdates: [(id: String, name: String)] = []

            await withTaskGroup(of: (String, Bool, OEmbedResult?).self) { group in
                var inFlight = 0
                for entry in videoEntries {
                    if inFlight >= 8 {
                        if let (id, needed, result) = await group.next() {
                            if result == nil { invalidIds.append(id) }
                            else if needed, let r = result { instructorUpdates.append((id, r.authorName)) }
                        }
                        inFlight -= 1
                    }
                    group.addTask {
                        let result = await scraper.validateVideo(entry.id)
                        return (entry.id, entry.needsInstructor, result)
                    }
                    inFlight += 1
                }
                for await (id, needed, result) in group {
                    if result == nil { invalidIds.append(id) }
                    else if needed, let r = result { instructorUpdates.append((id, r.authorName)) }
                }
            }

            // Apply all mutations on MainActor in one batch
            await MainActor.run {
                let descriptor = FetchDescriptor<Lecture>()
                let all = (try? container.mainContext.fetch(descriptor)) ?? []
                let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.youtubeId.lowercased(), $0) })

                let invalidSet = Set(invalidIds.map { $0.lowercased() })
                for id in invalidSet {
                    if let lecture = lookup[id] { container.mainContext.delete(lecture) }
                }

                for (id, name) in instructorUpdates {
                    if let lecture = lookup[id.lowercased()] { lecture.instructor = name }
                }

                try? container.mainContext.save()
                UserDefaults.standard.set(true, forKey: "seedDataValidated")
                print("Validation: checked \(videoEntries.count) videos, \(invalidIds.count) removed")
            }
        }
    }

    // MARK: - Background Scraper

    /// Kicks off the OCW scraper in a detached Task after seed data is loaded.
    /// Merges newly discovered lectures into SwiftData, deduplicating by youtubeId.
    /// Only validated (oEmbed-confirmed) videos are inserted.
    /// Throttled to once every 24 hours via UserDefaults timestamp.
    private static func startBackgroundScrape(container: ModelContainer) {
        let lastScrape = UserDefaults.standard.double(forKey: "lastScrapeTimestamp")
        let hoursSinceLastScrape = (Date().timeIntervalSince1970 - lastScrape) / 3600

        guard hoursSinceLastScrape > 24 || lastScrape == 0 else {
            print("OCWScraper: skipping, last scrape \(Int(hoursSinceLastScrape))h ago")
            return
        }

        Task.detached(priority: .utility) {
            do {
                let scraper = OCWScraper()
                let scraped = try await scraper.scrapeAll()
                print("OCWScraper: discovered \(scraped.count) validated lectures")

                await MainActor.run {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastScrapeTimestamp")
                    mergeScrapedData(scraped, into: container.mainContext)
                }
            } catch {
                print("OCWScraper failed: \(error)")
            }
        }
    }

    /// Merge scraped lectures into SwiftData, skipping duplicates by youtubeId.
    @MainActor
    private static func mergeScrapedData(_ scraped: [ScrapedLecture], into context: ModelContext) {
        let descriptor = FetchDescriptor<Lecture>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingIds = Set(existing.map { $0.youtubeId.lowercased() })

        let courseDescriptor = FetchDescriptor<Course>()
        let existingCourses = (try? context.fetch(courseDescriptor)) ?? []
        var courseMap: [String: Course] = [:]
        for course in existingCourses {
            courseMap[course.courseNumber] = course
        }

        var inserted = 0
        for item in scraped {
            guard !existingIds.contains(item.youtubeId.lowercased()) else { continue }
            guard !item.courseNumber.isEmpty else { continue }

            let lecture = Lecture(
                title: item.title,
                youtubeId: item.youtubeId,
                courseNumber: item.courseNumber,
                courseName: item.courseName,
                department: item.department,
                semester: item.semester,
                year: item.year,
                ocwUrl: item.ocwUrl,
                topicName: item.topicName,
                instructor: item.instructor
            )
            context.insert(lecture)

            if let course = courseMap[item.courseNumber] {
                lecture.course = course
            } else {
                let course = Course(
                    courseNumber: item.courseNumber,
                    title: item.courseName,
                    department: item.department,
                    semester: item.semester,
                    year: item.year
                )
                context.insert(course)
                courseMap[item.courseNumber] = course
                lecture.course = course
            }

            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
            print("OCWScraper: merged \(inserted) new lectures")
        }
    }

    // MARK: - Seed Data Loader

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
