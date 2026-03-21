import Foundation
import SwiftData

/// A course from MIT OpenCourseWare containing lecture videos.
/// SwiftData @Model with CloudKit-compatible defaults on every property.
@Model
final class Course {
    var courseNumber: String = ""
    var title: String = ""
    var department: String = ""
    var semester: String = ""
    var year: Int = 0
    var source: String = "mit-ocw"

    /// CloudKit requires optional relationship with @Relationship inverse
    @Relationship(deleteRule: .cascade, inverse: \Lecture.course)
    var lectures: [Lecture]? = []

    init(
        courseNumber: String,
        title: String,
        department: String,
        semester: String = "",
        year: Int = 0,
        source: String = "mit-ocw"
    ) {
        self.courseNumber = courseNumber
        self.title = title
        self.department = department
        self.semester = semester
        self.year = year
        self.source = source
    }
}
