import Foundation

/// Supabase client for syncing lecture/course data from PostgreSQL backend.
/// MVP uses bundled seed data — this service enables background refresh from Supabase
/// when network is available. Supabase IS PostgreSQL with a REST API via PostgREST.
///
/// Setup:
/// 1. Create Supabase project at https://supabase.com
/// 2. Run the SQL below to create tables
/// 3. Replace the placeholder URL and anon key below
///
/// ```sql
/// CREATE TABLE courses (
///     id BIGSERIAL PRIMARY KEY,
///     course_number TEXT NOT NULL,
///     title TEXT NOT NULL,
///     department TEXT NOT NULL DEFAULT '',
///     semester TEXT DEFAULT '',
///     year INT DEFAULT 0,
///     created_at TIMESTAMPTZ DEFAULT now()
/// );
///
/// CREATE TABLE videos (
///     id BIGSERIAL PRIMARY KEY,
///     title TEXT NOT NULL,
///     youtube_id TEXT NOT NULL,
///     course_number TEXT NOT NULL,
///     course_name TEXT NOT NULL,
///     department TEXT NOT NULL DEFAULT '',
///     semester TEXT DEFAULT '',
///     year INT DEFAULT 0,
///     ocw_url TEXT DEFAULT '',
///     topic_name TEXT DEFAULT '',
///     created_at TIMESTAMPTZ DEFAULT now()
/// );
/// ```
final class SupabaseService {
    static let shared = SupabaseService()

    // MARK: - Configuration
    // Replace these with your actual Supabase project credentials
    private let baseURL = "https://YOUR_PROJECT.supabase.co"
    private let anonKey = "YOUR_ANON_KEY"

    private init() {}

    // MARK: - Fetch Videos

    /// Fetches all lecture videos from the Supabase `videos` table.
    /// Returns decoded array ready for SwiftData insertion.
    func fetchVideos() async throws -> [SupabaseVideo] {
        let url = URL(string: "\(baseURL)/rest/v1/videos?select=*&order=created_at.desc")!
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SupabaseError.fetchFailed
        }

        return try JSONDecoder().decode([SupabaseVideo].self, from: data)
    }

    /// Fetches all courses from the Supabase `courses` table.
    func fetchCourses() async throws -> [SupabaseCourse] {
        let url = URL(string: "\(baseURL)/rest/v1/courses?select=*&order=department")!
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SupabaseError.fetchFailed
        }

        return try JSONDecoder().decode([SupabaseCourse].self, from: data)
    }
}

// MARK: - Supabase Response Types

struct SupabaseVideo: Decodable {
    let title: String
    let youtubeId: String
    let courseNumber: String
    let courseName: String
    let department: String
    let semester: String
    let year: Int
    let ocwUrl: String
    let topicName: String

    enum CodingKeys: String, CodingKey {
        case title
        case youtubeId = "youtube_id"
        case courseNumber = "course_number"
        case courseName = "course_name"
        case department
        case semester
        case year
        case ocwUrl = "ocw_url"
        case topicName = "topic_name"
    }
}

struct SupabaseCourse: Decodable {
    let courseNumber: String
    let title: String
    let department: String
    let semester: String
    let year: Int

    enum CodingKeys: String, CodingKey {
        case courseNumber = "course_number"
        case title
        case department
        case semester
        case year
    }
}

enum SupabaseError: Error, LocalizedError {
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch data from Supabase"
        }
    }
}
