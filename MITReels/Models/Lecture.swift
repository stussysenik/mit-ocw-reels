import Foundation
import SwiftData

/// A single lecture video from a university open courseware source.
/// SwiftData @Model with CloudKit-compatible defaults on every property.
/// CloudKit requires: all props have defaults, no @Attribute(.unique), optional relationships with inverses.
@Model
final class Lecture {
    var title: String = ""
    var youtubeId: String = ""
    var courseNumber: String = ""
    var courseName: String = ""
    var department: String = ""
    var semester: String = ""
    var year: Int = 0
    var ocwUrl: String = ""
    var topicName: String = ""
    var instructor: String = ""
    /// UniversitySource.rawValue — defaults to "mit" for backward compatibility.
    var sourceId: String = "mit"

    /// Convenience accessor for the typed source enum.
    var source: UniversitySource {
        UniversitySource(rawValue: sourceId) ?? .mit
    }

    /// Inverse relationship — CloudKit requires optional + inverse on both sides
    var course: Course?

    init(
        title: String,
        youtubeId: String,
        courseNumber: String,
        courseName: String,
        department: String,
        semester: String = "",
        year: Int = 0,
        ocwUrl: String = "",
        topicName: String = "",
        instructor: String = ""
    ) {
        self.title = title
        self.youtubeId = youtubeId
        self.courseNumber = courseNumber
        self.courseName = courseName
        self.department = department
        self.semester = semester
        self.year = year
        self.ocwUrl = ocwUrl
        self.topicName = topicName
        self.instructor = instructor
    }
}
