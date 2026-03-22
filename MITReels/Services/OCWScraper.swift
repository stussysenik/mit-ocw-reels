import Foundation

// MARK: - Data Models

/// Lecture video discovered from MIT OCW, matching SwiftData Lecture model shape.
struct ScrapedLecture: Codable, Hashable {
    let title: String
    let youtubeId: String
    let courseNumber: String
    let courseName: String
    let department: String
    let semester: String
    let year: Int
    let ocwUrl: String
    let topicName: String
    let instructor: String
}

/// YouTube oEmbed response — used to validate video availability and extract metadata.
struct OEmbedResult: Decodable {
    let title: String
    let authorName: String
    let thumbnailUrl: String

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case thumbnailUrl = "thumbnail_url"
    }
}

// MARK: - OCW Scraper

/// On-device MIT OCW video catalog scraper.
///
/// Uses a three-phase pipeline:
///   1. Parse sitemap index → fetch all course sitemaps (parallel)
///   2. Extract YouTube IDs from resource page transcript filenames (parallel)
///   3. Validate each video via YouTube oEmbed API (only valid videos pass)
///
/// Designed for Swift concurrency: URLSession + async/await + TaskGroup.
/// Zero external dependencies — Foundation only.
actor OCWScraper {

    // MARK: - Configuration

    private let sitemapIndexURL = URL(string: "https://ocw.mit.edu/sitemap.xml")!
    private let maxConcurrency: Int
    private let session: URLSession

    /// Tracks progress for UI updates.
    private(set) var coursesProcessed = 0
    private(set) var totalCourses = 0
    private(set) var videosFound = 0

    init(maxConcurrency: Int = 8) {
        self.maxConcurrency = maxConcurrency

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrency
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "MITReels/1.0 (iOS; educational)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Scrape the full MIT OCW catalog. Returns only validated, playable lectures.
    func scrapeAll() async throws -> [ScrapedLecture] {
        // Phase 1: Get all course sitemap URLs
        let courseSitemaps = try await fetchSitemapIndex()
        totalCourses = courseSitemaps.count

        // Phase 2+3: Scrape each course in parallel with bounded concurrency
        var allLectures: [ScrapedLecture] = []

        try await withThrowingTaskGroup(of: [ScrapedLecture].self) { group in
            var inFlight = 0

            for entry in courseSitemaps {
                if inFlight >= maxConcurrency {
                    if let lectures = try await group.next() {
                        allLectures.append(contentsOf: lectures)
                    }
                    inFlight -= 1
                }

                group.addTask { [self] in
                    try await self.scrapeCourse(entry)
                }
                inFlight += 1
            }

            for try await lectures in group {
                allLectures.append(contentsOf: lectures)
            }
        }

        return allLectures.uniqued(by: { $0.youtubeId.lowercased() })
    }

    /// Validate a single YouTube video ID via oEmbed. Returns nil if unavailable.
    func validateVideo(_ youtubeId: String) async -> OEmbedResult? {
        await validateYoutubeVideo(youtubeId)
    }

    // MARK: - Sitemap Parsing

    private struct CourseSitemapEntry {
        let sitemapURL: URL
        let courseURL: URL
        let courseNumber: String
        let courseName: String
        let semester: String
        let year: Int
    }

    private func fetchSitemapIndex() async throws -> [CourseSitemapEntry] {
        let (data, _) = try await session.data(from: sitemapIndexURL)
        let xml = String(data: data, encoding: .utf8) ?? ""

        let locs = extractXMLTags(xml, tag: "loc")

        return locs.compactMap { urlString -> CourseSitemapEntry? in
            guard urlString.contains("/courses/"),
                  urlString.hasSuffix("/sitemap.xml"),
                  let sitemapURL = URL(string: urlString) else { return nil }

            let slug = urlString
                .replacingOccurrences(of: "https://ocw.mit.edu/courses/", with: "")
                .replacingOccurrences(of: "/sitemap.xml", with: "")

            let parsed = parseCourseSlug(slug)
            let courseURL = URL(string: "https://ocw.mit.edu/courses/\(slug)/")!

            return CourseSitemapEntry(
                sitemapURL: sitemapURL,
                courseURL: courseURL,
                courseNumber: parsed.courseNumber,
                courseName: parsed.courseName,
                semester: parsed.semester,
                year: parsed.year
            )
        }
    }

    private func fetchCourseSitemap(_ url: URL) async throws -> [URL] {
        let (data, _) = try await session.data(from: url)
        let xml = String(data: data, encoding: .utf8) ?? ""
        let locs = extractXMLTags(xml, tag: "loc")

        return locs.compactMap { urlString -> URL? in
            guard urlString.contains("/resources/"),
                  !urlString.contains("video_galleries"),
                  !urlString.contains("video-galleries"),
                  !urlString.hasSuffix("/resources/"),
                  !urlString.hasSuffix("/resources") else { return nil }
            return URL(string: urlString)
        }
    }

    // MARK: - Course Scraping

    private func scrapeCourse(_ entry: CourseSitemapEntry) async throws -> [ScrapedLecture] {
        let resourceURLs: [URL]
        do {
            resourceURLs = try await fetchCourseSitemap(entry.sitemapURL)
        } catch {
            coursesProcessed += 1
            return []
        }

        var lectures: [ScrapedLecture] = []

        for url in resourceURLs {
            if let lecture = await scrapeResourcePage(url, course: entry) {
                lectures.append(lecture)
                videosFound += 1
            }
        }

        coursesProcessed += 1
        return lectures
    }

    /// Fetch a resource page, extract YouTube ID, and validate via oEmbed.
    /// Only returns a lecture if the video is confirmed playable.
    private func scrapeResourcePage(
        _ url: URL,
        course: CourseSitemapEntry
    ) async -> ScrapedLecture? {
        do {
            let (data, _) = try await session.data(from: url)
            let html = String(data: data, encoding: .utf8) ?? ""

            guard let youtubeId = extractYoutubeId(from: html) else { return nil }

            // Validate video exists and is playable via YouTube oEmbed API
            guard let oEmbed = await validateYoutubeVideo(youtubeId) else { return nil }

            let title = extractTitle(from: html)

            // Use oEmbed author_name as instructor (often "MIT OpenCourseWare")
            let instructor = oEmbed.authorName

            return ScrapedLecture(
                title: title,
                youtubeId: youtubeId,
                courseNumber: course.courseNumber,
                courseName: course.courseName,
                department: "",
                semester: course.semester,
                year: course.year,
                ocwUrl: url.absoluteString,
                topicName: "",
                instructor: instructor
            )
        } catch {
            return nil
        }
    }

    // MARK: - YouTube oEmbed Validation

    /// Validates a YouTube video ID via the public oEmbed API.
    /// Returns nil if the video is unavailable, deleted, or private.
    /// No API key required — this is a public endpoint.
    private func validateYoutubeVideo(_ youtubeId: String) async -> OEmbedResult? {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(youtubeId)&format=json"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(OEmbedResult.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Extraction

    /// Extract YouTube ID from transcript/caption filename in page HTML.
    /// Pattern: {32-char-hash}_{11-char-YouTubeID}.(srt|vtt|webvtt)
    /// Note: .pdf excluded — PDF transcript files are not video resources.
    private func extractYoutubeId(from html: String) -> String? {
        // Primary: transcript filename (srt/vtt only — not PDFs)
        if let range = html.range(of: #"[a-f0-9]{32}_([A-Za-z0-9_\-]{11})\.(srt|vtt|webvtt)"#,
                                  options: .regularExpression) {
            let match = String(html[range])
            let parts = match.split(separator: "_")
            if parts.count >= 2 {
                let idWithExt = String(parts.last ?? "")
                let id = idWithExt.components(separatedBy: ".").first ?? ""
                if id.count == 11 { return id }
            }
        }

        // Fallback: YouTube embed
        if let range = html.range(of: #"youtube\.com/embed/([A-Za-z0-9_\-]{11})"#,
                                  options: .regularExpression) {
            let match = String(html[range])
            return String(match.suffix(11))
        }

        return nil
    }

    /// Extract page title (first segment before "|").
    private func extractTitle(from html: String) -> String {
        guard let range = html.range(of: #"<title>([^<]+)</title>"#,
                                     options: .regularExpression) else {
            return "Unknown"
        }
        let match = String(html[range])
            .replacingOccurrences(of: "<title>", with: "")
            .replacingOccurrences(of: "</title>", with: "")
        return match.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
    }

    // MARK: - XML Helpers

    private func extractXMLTags(_ xml: String, tag: String) -> [String] {
        var results: [String] = []
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        var searchRange = xml.startIndex..<xml.endIndex
        while let openRange = xml.range(of: openTag, range: searchRange),
              let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex) {
            let content = String(xml[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(content)
            searchRange = closeRange.upperBound..<xml.endIndex
        }

        return results
    }

    // MARK: - Slug Parsing

    private struct ParsedSlug {
        let courseNumber: String
        let courseName: String
        let semester: String
        let year: Int
    }

    private func parseCourseSlug(_ slug: String) -> ParsedSlug {
        let semesterPattern = #"(spring|fall|january|summer|iap)-(\d{4})$"#

        var semester = ""
        var year = 0
        var nameSlug = slug

        if let range = slug.range(of: semesterPattern, options: .regularExpression) {
            let semStr = String(slug[range])
            let parts = semStr.split(separator: "-")
            if parts.count == 2 {
                semester = String(parts[0]).capitalized
                year = Int(parts[1]) ?? 0
            }
            nameSlug = String(slug[slug.startIndex..<range.lowerBound])
            if nameSlug.hasSuffix("-") {
                nameSlug = String(nameSlug.dropLast())
            }
        }

        let alphaPattern = #"^([a-z]+-[a-z]?\d[\d\w]*(?:-[\d\w]+)*)"#
        let numericPattern = #"^([\d]+-[\d\w]*)"#
        var courseNumber = ""
        var courseName = nameSlug

        if let range = nameSlug.range(of: alphaPattern, options: .regularExpression) {
            courseNumber = String(nameSlug[range])
                .uppercased()
                .replacingOccurrences(of: "-", with: ".")
            let remainder = String(nameSlug[range.upperBound...])
            if remainder.hasPrefix("-") {
                courseName = String(remainder.dropFirst())
            }
        } else if let range = nameSlug.range(of: numericPattern, options: .regularExpression) {
            courseNumber = String(nameSlug[range])
                .uppercased()
                .replacingOccurrences(of: "-", with: ".")
            let remainder = String(nameSlug[range.upperBound...])
            if remainder.hasPrefix("-") {
                courseName = String(remainder.dropFirst())
            }
        }

        let formattedName = courseName
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        return ParsedSlug(
            courseNumber: courseNumber,
            courseName: formattedName,
            semester: semester,
            year: year
        )
    }
}

