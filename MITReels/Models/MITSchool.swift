import SwiftUI

/// MIT's five Schools plus a cross-disciplinary bucket.
///
/// Maps OCW course number prefixes to their parent school, following the
/// MIT Registrar's official course numbering system.
///
/// Each school carries metadata for UI rendering: a short display name,
/// an SF Symbol, and an accent color for badges and section headers.
enum MITSchool: String, CaseIterable, Identifiable, Equatable {
    case engineering = "School of Engineering"
    case science = "School of Science"
    case architecturePlanning = "School of Architecture & Planning"
    case humanitiesArts = "School of Humanities, Arts, & Social Sciences"
    case crossDisciplinary = "Cross-Disciplinary"

    var id: String { rawValue }

    /// Short label for badges and pills.
    var shortName: String {
        switch self {
        case .engineering: return "Engineering"
        case .science: return "Science"
        case .architecturePlanning: return "Architecture"
        case .humanitiesArts: return "Humanities"
        case .crossDisciplinary: return "Cross-Disciplinary"
        }
    }

    /// SF Symbol representing each school's domain.
    var systemImage: String {
        switch self {
        case .engineering: return "gearshape.2"
        case .science: return "atom"
        case .architecturePlanning: return "building.2"
        case .humanitiesArts: return "text.book.closed"
        case .crossDisciplinary: return "square.grid.3x3"
        }
    }

    /// Accent color for badges and section headers — an OKLCH palette built at
    /// uniform perceptual lightness (see `SchoolPalette`).
    var color: Color { SchoolPalette.accent(for: self) }

    /// Maps a course number to its parent MIT School.
    ///
    /// Extracts the department prefix before the first dot, then matches
    /// against the Registrar's numbering:
    /// - Engineering: 1, 2, 3, 6, 10, 16, 22
    /// - Science: 5, 7, 8, 9, 12, 18
    /// - Architecture & Planning: 4, 11
    /// - SHASS: 14, 17, 21, 21A, 21H, 21L, 21M, 21W, 24
    /// - Cross-Disciplinary: MAS, RES, STS, HST, CMS, WGS
    static func from(courseNumber: String) -> MITSchool {
        let prefix = extractPrefix(courseNumber)
        switch prefix {
        case "1", "2", "3", "6", "10", "16", "22":
            return .engineering
        case "5", "7", "8", "9", "12", "18":
            return .science
        case "4", "11":
            return .architecturePlanning
        case "14", "17", "21", "21A", "21G", "21H", "21L", "21M", "21W", "24":
            return .humanitiesArts
        default:
            return .crossDisciplinary
        }
    }

    /// Extract the department prefix from a course number.
    ///
    /// Examples:
    /// - "6.006" → "6"
    /// - "18.03SC" → "18"
    /// - "21H.931" → "21H"
    /// - "MAS.S62" → "MAS"
    /// - "RES.15.005" → "RES"
    /// - "11.016J" → "11"
    private static func extractPrefix(_ courseNumber: String) -> String {
        let parts = courseNumber.split(separator: ".", maxSplits: 1)
        guard let first = parts.first else { return "" }
        return String(first)
    }
}

// MARK: - Course Level Classification

/// Classifies a course by difficulty level based on MIT numbering conventions.
///
/// MIT courses use the number after the department prefix dot to signal level:
/// - 0xx: introductory undergraduate
/// - 1xx–4xx: intermediate undergraduate
/// - 5xx–7xx: advanced/graduate
/// - 8xx+: graduate seminars
/// - S-prefix: special subjects
enum CourseLevel: String, Equatable {
    case introductory = "Introductory"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case graduate = "Graduate"
    case special = "Special"

    /// Classify based on the numeric portion after the department prefix.
    static func from(courseNumber: String) -> CourseLevel {
        let parts = courseNumber.split(separator: ".")
        guard parts.count >= 2 else { return .special }

        let afterDot = String(parts[1])

        // S-prefix = special subject (e.g., 18.S997)
        if afterDot.hasPrefix("S") || afterDot.hasPrefix("s") {
            return .special
        }

        // Extract leading digits
        let numericPart = afterDot.prefix(while: { $0.isNumber })
        guard let num = Int(numericPart) else { return .special }

        switch num {
        case 0..<100: return .introductory
        case 100..<500: return .intermediate
        case 500..<800: return .advanced
        default: return .graduate
        }
    }
}
