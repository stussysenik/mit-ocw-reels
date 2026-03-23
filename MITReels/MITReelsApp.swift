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
        // Cap URL cache to prevent unbounded memory growth from thumbnails
        URLCache.shared.memoryCapacity = 50 * 1024 * 1024   // 50 MB
        URLCache.shared.diskCapacity = 100 * 1024 * 1024     // 100 MB

        do {
            container = try ModelContainer(for: Course.self, Lecture.self)
            MITReelsApp.seedDataIfNeeded(context: container.mainContext)
            MITReelsApp.seedMultiSourceIfNeeded(context: container.mainContext)
            MITReelsApp.startBackgroundValidation(container: container)
            MITReelsApp.startBackgroundScrape(container: container)
            MITReelsApp.startYouTubeFetch(container: container)
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

            // Validate concurrently (bounded to 4 to limit peak memory)
            var invalidIds: [String] = []
            var instructorUpdates: [(id: String, name: String)] = []

            await withTaskGroup(of: (String, Bool, OEmbedResult?).self) { group in
                var inFlight = 0
                for entry in videoEntries {
                    if inFlight >= 4 {
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
                let lookup = Dictionary(all.map { ($0.youtubeId.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

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

    // MARK: - Multi-Source Seed Data Loader

    /// Seeds non-MIT lecture sources from multi_source_seed.json.
    /// Guarded by "multiSourceSeeded_v4" UserDefaults flag — runs once per install.
    @MainActor
    private static func seedMultiSourceIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: "multiSourceSeeded_v4") else { return }

        guard let url = Bundle.main.url(forResource: "multi_source_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("multi_source_seed.json not found in bundle")
            return
        }

        guard let seed = try? JSONDecoder().decode(MultiSourceSeedData.self, from: data) else {
            print("Failed to decode multi_source_seed.json")
            return
        }

        var courseMap: [String: Course] = [:]
        // Fetch existing courses to avoid duplicates
        let courseDescriptor = FetchDescriptor<Course>()
        let existingCourses = (try? context.fetch(courseDescriptor)) ?? []
        for course in existingCourses {
            courseMap["\(course.sourceId)_\(course.courseNumber)"] = course
        }

        for seedCourse in seed.courses {
            let key = "\(seedCourse.sourceId)_\(seedCourse.courseNumber)"
            guard courseMap[key] == nil else { continue }
            let course = Course(
                courseNumber: seedCourse.courseNumber,
                title: seedCourse.title,
                department: seedCourse.department,
                semester: seedCourse.semester,
                year: seedCourse.year
            )
            course.sourceId = seedCourse.sourceId
            context.insert(course)
            courseMap[key] = course
        }

        // Dedup against existing lectures
        let lectureDescriptor = FetchDescriptor<Lecture>()
        let existingLectures = (try? context.fetch(lectureDescriptor)) ?? []
        let existingIds = Set(existingLectures.map { $0.youtubeId.lowercased() })

        var inserted = 0
        for seedLecture in seed.lectures {
            guard !existingIds.contains(seedLecture.youtubeId.lowercased()) else { continue }
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
            lecture.sourceId = seedLecture.sourceId
            context.insert(lecture)

            let key = "\(seedLecture.sourceId)_\(seedLecture.courseNumber)"
            if let course = courseMap[key] {
                lecture.course = course
            }
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: "multiSourceSeeded_v4")
        print("Multi-source seed: \(inserted) lectures across \(seed.courses.count) courses")
    }

    // MARK: - YouTube Fetch Pipeline

    /// Fetches lecture videos from enabled non-MIT sources via YouTube Data API v3.
    /// Per-source throttle: once every 24 hours.
    private static func startYouTubeFetch(container: ModelContainer) {
        let apiKey = APIKeys.youtube
        guard !apiKey.isEmpty else {
            print("YouTubeFetch: no API key configured, skipping")
            return
        }

        let preferences = SourcePreferences.shared
        let enabledNonMIT = preferences.enabledSourceIds.filter { $0 != "mit" }
        guard !enabledNonMIT.isEmpty else { return }

        Task.detached(priority: .utility) {
            let client = YouTubeAPIClient(apiKey: apiKey)

            for sourceId in enabledNonMIT {
                guard let source = UniversitySource(rawValue: sourceId),
                      source.contentType == .youtubeAPI else { continue }

                // Per-source 24h throttle
                let lastKey = "lastYTFetch_\(sourceId)"
                let last = UserDefaults.standard.double(forKey: lastKey)
                let hours = (Date().timeIntervalSince1970 - last) / 3600
                guard hours > 24 || last == 0 else { continue }

                do {
                    let videos = try await client.fetchAllVideos(for: source)
                    print("YouTubeFetch: \(source.displayName) → \(videos.count) videos")

                    await MainActor.run {
                        mergeYouTubeData(videos, source: source, into: container.mainContext)
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
                    }
                } catch {
                    print("YouTubeFetch failed for \(source.displayName): \(error)")
                }
            }
        }
    }

    /// Merge YouTube API videos into SwiftData, skipping duplicates by youtubeId.
    @MainActor
    private static func mergeYouTubeData(
        _ videos: [YouTubeVideo],
        source: UniversitySource,
        into context: ModelContext
    ) {
        let descriptor = FetchDescriptor<Lecture>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingIds = Set(existing.map { $0.youtubeId.lowercased() })

        let courseDescriptor = FetchDescriptor<Course>()
        let existingCourses = (try? context.fetch(courseDescriptor)) ?? []
        var courseMap: [String: Course] = [:]
        for course in existingCourses {
            courseMap["\(course.sourceId)_\(course.courseNumber)"] = course
        }

        var inserted = 0
        for video in videos {
            guard !existingIds.contains(video.videoId.lowercased()) else { continue }

            // Use playlist title as course name / number
            let courseNumber = video.playlistTitle
                .components(separatedBy: ":")
                .first?
                .trimmingCharacters(in: .whitespaces) ?? video.playlistTitle

            let lecture = Lecture(
                title: video.title,
                youtubeId: video.videoId,
                courseNumber: courseNumber,
                courseName: video.playlistTitle,
                department: "",
                semester: "",
                year: 0,
                ocwUrl: "",
                topicName: ""
            )
            lecture.sourceId = source.rawValue
            context.insert(lecture)

            let courseKey = "\(source.rawValue)_\(courseNumber)"
            if let course = courseMap[courseKey] {
                lecture.course = course
            } else {
                let course = Course(
                    courseNumber: courseNumber,
                    title: video.playlistTitle,
                    department: ""
                )
                course.sourceId = source.rawValue
                context.insert(course)
                courseMap[courseKey] = course
                lecture.course = course
            }

            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
            print("YouTubeFetch: merged \(inserted) new \(source.shortName) lectures")
        }
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

// MARK: - Multi-Source Seed Data Codable Types

private struct MultiSourceSeedData: Decodable {
    let lectures: [MultiSourceSeedLecture]
    let courses: [MultiSourceSeedCourse]
}

private struct MultiSourceSeedLecture: Decodable {
    let title: String
    let youtubeId: String
    let courseNumber: String
    let courseName: String
    let department: String
    let semester: String
    let year: Int
    let ocwUrl: String
    let topicName: String
    let sourceId: String
}

private struct MultiSourceSeedCourse: Decodable {
    let courseNumber: String
    let title: String
    let department: String
    let semester: String
    let year: Int
    let sourceId: String
}
