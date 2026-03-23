import Foundation
import SwiftData

/// A course from a university open courseware source containing lecture videos.
/// SwiftData @Model with CloudKit-compatible defaults on every property.
@Model
final class Course {
    var courseNumber: String = ""
    var title: String = ""
    var department: String = ""
    var semester: String = ""
    var year: Int = 0
    /// UniversitySource.rawValue — defaults to "mit" for backward compatibility.
    var sourceId: String = "mit"

    /// Convenience accessor for the typed source enum.
    var source: UniversitySource {
        UniversitySource(rawValue: sourceId) ?? .mit
    }

    /// CloudKit requires optional relationship with @Relationship inverse
    @Relationship(deleteRule: .cascade, inverse: \Lecture.course)
    var lectures: [Lecture]? = []

    init(
        courseNumber: String,
        title: String,
        department: String,
        semester: String = "",
        year: Int = 0
    ) {
        self.courseNumber = courseNumber
        self.title = title
        self.department = department
        self.semester = semester
        self.year = year
    }
}
