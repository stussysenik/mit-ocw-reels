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
        // URL cache for thumbnails + YouTube player JS — generous limits for media app
        URLCache.shared.memoryCapacity = 100 * 1024 * 1024  // 100 MB (~3K thumbnails)
        URLCache.shared.diskCapacity = 200 * 1024 * 1024    // 200 MB persistent

        do {
            container = try ModelContainer(for: Course.self, Lecture.self)
        } catch {
            // Schema migration failed — delete store and recreate from scratch
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            for ext in ["", ".wal", ".shm"] {
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension(ext))
            }
            UserDefaults.standard.removeObject(forKey: "seedDataValidated")
            UserDefaults.standard.removeObject(forKey: "multiSourceSeedCompleted")
            UserDefaults.standard.removeObject(forKey: "multiSourceSeeded_v8")
            container = try! ModelContainer(for: Course.self, Lecture.self)
        }

        // All heavy work deferred — UI renders immediately
        MITReelsApp.startInitialSetup(container: container)
    }

    /// Orchestrates startup tasks sequentially so each phase completes before the next.
    /// All SwiftData work happens in batched MainActor.run blocks — max ~50ms main thread hold.
    private static func startInitialSetup(container: ModelContainer) {
        // Warm up the zero-wait reel player pool immediately — no dependency on data
        Task { @MainActor in ReelPlayerPool.shared.warmUp() }

        Task.detached(priority: .userInitiated) {
            await seedDataIfNeeded(container: container)
            await migrateExistingLecturesToValidated(container: container)
            startMultiSourceSeed(container: container)
            startBackgroundValidation(container: container)
            startMultiSourceValidation(container: container)
            startBackgroundScrape(container: container)
            startYouTubeFetch(container: container)
            startPeriodicValidation(container: container)
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

                // Mark confirmed-valid lectures
                let validatedIds = Set(videoEntries.map { $0.id.lowercased() }).subtracting(invalidSet)
                for id in validatedIds {
                    if let lecture = lookup[id] { lecture.isValidated = true }
                }

                for (id, name) in instructorUpdates {
                    if let lecture = lookup[id.lowercased()] { lecture.instructor = name }
                }

                try? container.mainContext.save()
                UserDefaults.standard.set(true, forKey: "seedDataValidated")
            }
        }
    }

    // MARK: - Multi-Source Video Validation

    /// Validates multi-source seed lectures via YouTube oEmbed.
    /// Removes lectures whose videos are unavailable (deleted, private, region-locked).
    /// Runs once after multi-source seed completes (tracked via UserDefaults).
    private static func startMultiSourceValidation(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: "multiSourceValidated_v1") else { return }

        // Delay to let multi-source seed finish first
        Task.detached(priority: .background) {
            // Wait for multi-source seed to complete
            while !UserDefaults.standard.bool(forKey: "multiSourceSeeded_v8") {
                try? await Task.sleep(for: .seconds(2))
            }

            let scraper = OCWScraper()

            let videoIds: [String] = await MainActor.run {
                let descriptor = FetchDescriptor<Lecture>()
                let all = (try? container.mainContext.fetch(descriptor)) ?? []
                return all.filter { $0.sourceId != "mit" }.map { $0.youtubeId }
            }

            guard !videoIds.isEmpty else {
                await MainActor.run { UserDefaults.standard.set(true, forKey: "multiSourceValidated_v1") }
                return
            }

            var invalidIds: [String] = []

            // Validate in batches of 4 to avoid hammering the network
            await withTaskGroup(of: (String, Bool).self) { group in
                var inFlight = 0
                for id in videoIds {
                    if inFlight >= 4 {
                        if let (checkedId, isValid) = await group.next() {
                            if !isValid { invalidIds.append(checkedId) }
                        }
                        inFlight -= 1
                    }
                    group.addTask {
                        let result = await scraper.validateVideo(id)
                        return (id, result != nil)
                    }
                    inFlight += 1
                }
                for await (checkedId, isValid) in group {
                    if !isValid { invalidIds.append(checkedId) }
                }
            }

            // Delete invalid and mark valid lectures on MainActor
            await MainActor.run {
                let invalidSet = Set(invalidIds.map { $0.lowercased() })
                let validatedSet = Set(videoIds.map { $0.lowercased() }).subtracting(invalidSet)

                let descriptor = FetchDescriptor<Lecture>()
                let all = (try? container.mainContext.fetch(descriptor)) ?? []
                for lecture in all {
                    let idLower = lecture.youtubeId.lowercased()
                    if invalidSet.contains(idLower) {
                        container.mainContext.delete(lecture)
                    } else if validatedSet.contains(idLower) {
                        lecture.isValidated = true
                    }
                }

                try? container.mainContext.save()
                UserDefaults.standard.set(true, forKey: "multiSourceValidated_v1")
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

        guard hoursSinceLastScrape > 24 || lastScrape == 0 else { return }

        Task.detached(priority: .utility) {
            do {
                let scraper = OCWScraper()
                let scraped = try await scraper.scrapeAll()

                await MainActor.run {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastScrapeTimestamp")
                    mergeScrapedData(scraped, into: container.mainContext)
                }
            } catch { }
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
                title: item.title.decodingHTMLEntities(),
                youtubeId: item.youtubeId,
                courseNumber: item.courseNumber,
                courseName: item.courseName.decodingHTMLEntities(),
                department: item.department,
                semester: item.semester,
                year: item.year,
                ocwUrl: item.ocwUrl,
                topicName: item.topicName.decodingHTMLEntities(),
                instructor: item.instructor
            )
            lecture.isValidated = true  // OCW scraper validates via oEmbed before returning
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

        if inserted > 0 { try? context.save() }
    }

    // MARK: - Seed Data Loader

    /// Seeds initial lecture data from bundled JSON in batched MainActor.run blocks.
    /// Each batch holds the main thread for ~50ms max, yielding between batches.
    private static func seedDataIfNeeded(container: ModelContainer) async {
        let needsSeed: Bool = await MainActor.run {
            let descriptor = FetchDescriptor<Lecture>()
            return ((try? container.mainContext.fetchCount(descriptor)) ?? 0) == 0
        }
        guard needsSeed else { return }

        guard let url = Bundle.main.url(forResource: "seed_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode(SeedData.self, from: data) else { return }

        // Phase 1: Insert courses (small — ~25 records, one batch)
        let courseMap: [String: Course] = await MainActor.run {
            var map: [String: Course] = [:]
            for seedCourse in seed.courses {
                let course = Course(
                    courseNumber: seedCourse.courseNumber,
                    title: seedCourse.title,
                    department: seedCourse.department,
                    semester: seedCourse.semester,
                    year: seedCourse.year
                )
                container.mainContext.insert(course)
                map[seedCourse.courseNumber] = course
            }
            try? container.mainContext.save()
            return map
        }

        // Phase 2: Insert lectures in 200-item batches
        let batchSize = 200
        var batchStart = 0
        while batchStart < seed.lectures.count {
            let batchEnd = min(batchStart + batchSize, seed.lectures.count)
            let batch = Array(seed.lectures[batchStart..<batchEnd])

            await MainActor.run {
                for seedLecture in batch {
                    let lecture = Lecture(
                        title: seedLecture.title.decodingHTMLEntities(),
                        youtubeId: seedLecture.youtubeId,
                        courseNumber: seedLecture.courseNumber,
                        courseName: seedLecture.courseName.decodingHTMLEntities(),
                        department: seedLecture.department,
                        semester: seedLecture.semester,
                        year: seedLecture.year,
                        ocwUrl: seedLecture.ocwUrl,
                        topicName: seedLecture.topicName.decodingHTMLEntities()
                    )
                    lecture.isValidated = true
                    container.mainContext.insert(lecture)
                    if let course = courseMap[seedLecture.courseNumber] {
                        lecture.course = course
                    }
                }
                try? container.mainContext.save()
            }
            batchStart = batchEnd
        }
    }

    // MARK: - Validation Migration

    /// One-time migration: marks all existing lectures as validated.
    /// Trusts that prior one-time validators already confirmed these lectures.
    private static func migrateExistingLecturesToValidated(container: ModelContainer) async {
        let alreadyDone: Bool = await MainActor.run {
            UserDefaults.standard.bool(forKey: "lectureValidationMigrated_v1")
        }
        guard !alreadyDone else { return }

        await MainActor.run {
            let descriptor = FetchDescriptor<Lecture>()
            let all = (try? container.mainContext.fetch(descriptor)) ?? []
            guard !all.isEmpty else {
                UserDefaults.standard.set(true, forKey: "lectureValidationMigrated_v1")
                return
            }
            for lecture in all {
                lecture.isValidated = true
            }
            try? container.mainContext.save()
            UserDefaults.standard.set(true, forKey: "lectureValidationMigrated_v1")
        }
    }

    // MARK: - Multi-Source Seed Data Loader (Async)

    /// Seeds non-MIT lecture sources from multi_source_seed.json in a background task.
    /// Uses separate MainActor.run blocks per batch so UI renders between batches.
    private static func startMultiSourceSeed(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: "multiSourceSeeded_v8") else { return }

        Task.detached(priority: .utility) {
            guard let url = Bundle.main.url(forResource: "multi_source_seed", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let seed = try? JSONDecoder().decode(MultiSourceSeedData.self, from: data) else { return }

            // Phase 1: Insert courses (small — ~1800 records, fast)
            let courseMap: [String: Course] = await MainActor.run {
                let courseDescriptor = FetchDescriptor<Course>()
                let existingCourses = (try? container.mainContext.fetch(courseDescriptor)) ?? []
                var map: [String: Course] = [:]
                for course in existingCourses {
                    map["\(course.sourceId)_\(course.courseNumber)"] = course
                }
                for seedCourse in seed.courses {
                    let key = "\(seedCourse.sourceId)_\(seedCourse.courseNumber)"
                    guard map[key] == nil else { continue }
                    let course = Course(
                        courseNumber: seedCourse.courseNumber,
                        title: seedCourse.title,
                        department: seedCourse.department,
                        semester: seedCourse.semester,
                        year: seedCourse.year
                    )
                    course.sourceId = seedCourse.sourceId
                    container.mainContext.insert(course)
                    map[key] = course
                }
                try? container.mainContext.save()
                return map
            }

            // Phase 2: Get existing lecture IDs to dedup
            let existingIds: Set<String> = await MainActor.run {
                let d = FetchDescriptor<Lecture>()
                let all = (try? container.mainContext.fetch(d)) ?? []
                return Set(all.map { $0.youtubeId.lowercased() })
            }

            // Phase 3: Insert lectures in batches — each batch is a separate MainActor.run
            // This yields the main thread between batches so SwiftUI can render
            let batchSize = 200
            var totalInserted = 0
            let lectures = seed.lectures.filter { !existingIds.contains($0.youtubeId.lowercased()) }

            var batchStart = 0
            while batchStart < lectures.count {
                let batchEnd = min(batchStart + batchSize, lectures.count)
                let batch = Array(lectures[batchStart..<batchEnd])

                let inserted: Int = await MainActor.run {
                    var count = 0
                    for seedLecture in batch {
                        let lecture = Lecture(
                            title: seedLecture.title.decodingHTMLEntities(),
                            youtubeId: seedLecture.youtubeId,
                            courseNumber: seedLecture.courseNumber,
                            courseName: seedLecture.courseName.decodingHTMLEntities(),
                            department: seedLecture.department,
                            semester: seedLecture.semester,
                            year: seedLecture.year,
                            ocwUrl: seedLecture.ocwUrl,
                            topicName: seedLecture.topicName.decodingHTMLEntities()
                        )
                        lecture.sourceId = seedLecture.sourceId
                        lecture.isValidated = true
                        container.mainContext.insert(lecture)

                        let key = "\(seedLecture.sourceId)_\(seedLecture.courseNumber)"
                        if let course = courseMap[key] {
                            lecture.course = course
                        }
                        count += 1
                    }
                    try? container.mainContext.save()
                    return count
                }

                totalInserted += inserted
                batchStart = batchEnd
                // Yield — SwiftUI renders, no hang > 50ms per batch
            }

            await MainActor.run {
                UserDefaults.standard.set(true, forKey: "multiSourceSeeded_v8")
            }
        }
    }

    // MARK: - YouTube Fetch Pipeline

    /// Fetches lecture videos from enabled non-MIT sources via YouTube Data API v3.
    /// Per-source throttle: once every 24 hours.
    private static func startYouTubeFetch(container: ModelContainer) {
        let apiKey = APIKeys.youtube
        guard !apiKey.isEmpty else { return }

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

                    // oEmbed pre-validation — only insert confirmed-playable videos
                    let scraper = OCWScraper()
                    var validVideos: [YouTubeVideo] = []

                    await withTaskGroup(of: (YouTubeVideo, Bool).self) { group in
                        var inFlight = 0
                        for video in videos {
                            if inFlight >= 4 {
                                if let (checked, isValid) = await group.next() {
                                    if isValid { validVideos.append(checked) }
                                }
                                inFlight -= 1
                            }
                            group.addTask {
                                let result = await scraper.validateVideo(video.videoId)
                                return (video, result != nil)
                            }
                            inFlight += 1
                        }
                        for await (checked, isValid) in group {
                            if isValid { validVideos.append(checked) }
                        }
                    }

                    await MainActor.run {
                        mergeYouTubeData(validVideos, source: source, into: container.mainContext)
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
                    }
                } catch { }
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
                title: video.title.decodingHTMLEntities(),
                youtubeId: video.videoId,
                courseNumber: courseNumber,
                courseName: video.playlistTitle.decodingHTMLEntities(),
                department: "",
                semester: "",
                year: 0,
                ocwUrl: "",
                topicName: ""
            )
            lecture.sourceId = source.rawValue
            lecture.isValidated = true  // Pre-validated via oEmbed
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

        if inserted > 0 { try? context.save() }
    }
    // MARK: - Periodic Re-validation

    /// Re-validates all lectures via YouTube oEmbed every 7 days.
    /// Removes videos that have become private, deleted, or region-locked since last check.
    private static func startPeriodicValidation(container: ModelContainer) {
        let last = UserDefaults.standard.double(forKey: "lastPeriodicValidation")

        // First run: set baseline, don't validate (one-time validators handle first launch)
        guard last > 0 else {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPeriodicValidation")
            return
        }

        let daysSinceLast = (Date().timeIntervalSince1970 - last) / 86400
        guard daysSinceLast > 7 else { return }

        Task.detached(priority: .background) {
            let scraper = OCWScraper()
            let allIds: [String] = await MainActor.run {
                let d = FetchDescriptor<Lecture>()
                return ((try? container.mainContext.fetch(d)) ?? []).map { $0.youtubeId }
            }
            guard !allIds.isEmpty else { return }

            // Sample up to 500 random videos — sufficient to detect widespread unavailability
            let sampleSize = min(500, allIds.count)
            let videoIds = Array(allIds.shuffled().prefix(sampleSize))

            var invalidIds: [String] = []
            await withTaskGroup(of: (String, Bool).self) { group in
                var inFlight = 0
                for id in videoIds {
                    if inFlight >= 4 {
                        if let (checkedId, valid) = await group.next() {
                            if !valid { invalidIds.append(checkedId) }
                        }
                        inFlight -= 1
                    }
                    group.addTask { (id, await scraper.validateVideo(id) != nil) }
                    inFlight += 1
                }
                for await (checkedId, valid) in group {
                    if !valid { invalidIds.append(checkedId) }
                }
            }

            await MainActor.run {
                if !invalidIds.isEmpty {
                    let invalidSet = Set(invalidIds.map { $0.lowercased() })
                    let d = FetchDescriptor<Lecture>()
                    let all = (try? container.mainContext.fetch(d)) ?? []
                    for lecture in all where invalidSet.contains(lecture.youtubeId.lowercased()) {
                        container.mainContext.delete(lecture)
                    }
                    try? container.mainContext.save()
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPeriodicValidation")
            }
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
