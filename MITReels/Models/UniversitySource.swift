import SwiftUI

/// Content source for lecture videos — each case is a university or educational channel.
///
/// Static enum (not @Model) because the source list ships with the app binary.
/// The `rawValue` string is stored as `sourceId` on Lecture and Course records.
/// MIT uses the existing OCWScraper; all others use the YouTube Data API v3.
enum UniversitySource: String, CaseIterable, Identifiable, Codable {
    case mit = "mit"
    case stanford = "stanford"
    case harvard = "harvard"
    case yale = "yale"
    case caltech = "caltech"
    case berkeley = "berkeley"
    case cmu = "cmu"
    case princeton = "princeton"
    case cornell = "cornell"
    case threeBlue1Brown = "3blue1brown"
    case khanAcademy = "khan_academy"
    case crashCourse = "crash_course"

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .mit: return "MIT OpenCourseWare"
        case .stanford: return "Stanford University"
        case .harvard: return "Harvard University"
        case .yale: return "Yale University"
        case .caltech: return "Caltech"
        case .berkeley: return "UC Berkeley"
        case .cmu: return "Carnegie Mellon"
        case .princeton: return "Princeton University"
        case .cornell: return "Cornell University"
        case .threeBlue1Brown: return "3Blue1Brown"
        case .khanAcademy: return "Khan Academy"
        case .crashCourse: return "CrashCourse"
        }
    }

    var shortName: String {
        switch self {
        case .mit: return "MIT"
        case .stanford: return "Stanford"
        case .harvard: return "Harvard"
        case .yale: return "Yale"
        case .caltech: return "Caltech"
        case .berkeley: return "Berkeley"
        case .cmu: return "CMU"
        case .princeton: return "Princeton"
        case .cornell: return "Cornell"
        case .threeBlue1Brown: return "3B1B"
        case .khanAcademy: return "Khan"
        case .crashCourse: return "Crash Course"
        }
    }

    var systemImage: String {
        switch self {
        case .mit: return "building.columns"
        case .stanford: return "graduationcap"
        case .harvard: return "book.closed"
        case .yale: return "theatermasks"
        case .caltech: return "atom"
        case .berkeley: return "leaf"
        case .cmu: return "cpu"
        case .princeton: return "building.2"
        case .cornell: return "mountain.2"
        case .threeBlue1Brown: return "function"
        case .khanAcademy: return "lightbulb"
        case .crashCourse: return "bolt.fill"
        }
    }

    // MARK: - Branding

    /// Primary brand color for badges and section accents.
    var brandColor: Color {
        switch self {
        case .mit: return Color(hex: 0xA31F34)         // MIT Cardinal
        case .stanford: return Color(hex: 0x8C1515)     // Stanford Cardinal
        case .harvard: return Color(hex: 0xA41034)      // Harvard Crimson
        case .yale: return Color(hex: 0x00356B)         // Yale Blue
        case .caltech: return Color(hex: 0xFF6C0C)      // Caltech Orange
        case .berkeley: return Color(hex: 0x003262)     // Berkeley Blue
        case .cmu: return Color(hex: 0xC41230)          // CMU Red
        case .princeton: return Color(hex: 0xE77500)    // Princeton Orange
        case .cornell: return Color(hex: 0xB31B1B)      // Cornell Red
        case .threeBlue1Brown: return Color(hex: 0x2B7CB3) // 3B1B Blue
        case .khanAcademy: return Color(hex: 0x14BF96)  // Khan Green
        case .crashCourse: return Color(hex: 0x2ECC71)  // Crash Course Green
        }
    }

    /// Lighter gradient endpoint for card backgrounds.
    var gradientEndColor: Color {
        switch self {
        case .mit: return Color(hex: 0xD4525E)
        case .stanford: return Color(hex: 0xB84545)
        case .harvard: return Color(hex: 0xD44060)
        case .yale: return Color(hex: 0x3A6E9E)
        case .caltech: return Color(hex: 0xFFA05C)
        case .berkeley: return Color(hex: 0x3A6E95)
        case .cmu: return Color(hex: 0xE44560)
        case .princeton: return Color(hex: 0xFFA540)
        case .cornell: return Color(hex: 0xD44545)
        case .threeBlue1Brown: return Color(hex: 0x5BACCF)
        case .khanAcademy: return Color(hex: 0x4EDBB8)
        case .crashCourse: return Color(hex: 0x5DECA0)
        }
    }

    // MARK: - YouTube Integration

    /// YouTube channel ID for API fetching.
    var youtubeChannelId: String {
        switch self {
        case .mit: return "UCEBb1b_L6zDS3xTUrIALZOw"
        case .stanford: return "UCBa5G_ESCn8Uf67UGNEbXvA"
        case .harvard: return "UCFhajVJFpFJaUqBfmQv7UbQ"
        case .yale: return "UC4EY_qnSeAP1xGsh61eASoA"
        case .caltech: return "UCXIFkVnqEbEBHtEjiqHCaJQ"
        case .berkeley: return "UCEVLABSfx4GqYzzFMJKjpPg"
        case .cmu: return "UCOWzl3JZ3q8CkNdNgumEcXw"
        case .princeton: return "UCirGJHNBb0kXnU1FvKnNF0A"
        case .cornell: return "UCnrAMLVfcRAO0PVXOOzx4NA"
        case .threeBlue1Brown: return "UCYO_jab_esuFRV4b17AJtAw"
        case .khanAcademy: return "UC4a-Gbdw7vOaccHmFo40b9g"
        case .crashCourse: return "UCX6b17PVsYBQ0ip5gyeme-Q"
        }
    }

    /// Fetch strategy — MIT uses its sitemap scraper; everything else uses YouTube API.
    enum ContentType {
        case ocwSitemap
        case youtubeAPI
    }

    var contentType: ContentType {
        switch self {
        case .mit: return .ocwSitemap
        default: return .youtubeAPI
        }
    }

    /// Whether this is a traditional university (vs educational creator).
    var isUniversity: Bool {
        switch self {
        case .threeBlue1Brown, .khanAcademy, .crashCourse: return false
        default: return true
        }
    }
}
