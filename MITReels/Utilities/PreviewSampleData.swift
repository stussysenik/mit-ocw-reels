#if DEBUG
import SwiftData
import SwiftUI

/// In-memory SwiftData container with sample MIT OCW data for Xcode Previews.
/// Provides reusable sample Course and Lecture objects so every view preview
/// can render realistic content without hitting disk or requiring seed_data.json.
@MainActor
struct PreviewSampleData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Course.self, Lecture.self, configurations: config)

        // --- Course 1: CS ---
        let course = Course(
            courseNumber: "6.0001",
            title: "Introduction to Computer Science and Programming Using Python",
            department: "Electrical Engineering and Computer Science",
            semester: "Fall",
            year: 2016
        )
        container.mainContext.insert(course)

        let lectures = [
            Lecture(
                title: "What is Computation?",
                youtubeId: "nykOeWgQcHM",
                courseNumber: "6.0001",
                courseName: "Introduction to CS and Programming Using Python",
                department: "Electrical Engineering and Computer Science",
                semester: "Fall",
                year: 2016,
                topicName: "Computer Science"
            ),
            Lecture(
                title: "Branching and Iteration",
                youtubeId: "0jljZRnHwOI",
                courseNumber: "6.0001",
                courseName: "Introduction to CS and Programming Using Python",
                department: "Electrical Engineering and Computer Science",
                semester: "Fall",
                year: 2016,
                topicName: "Computer Science"
            ),
        ]
        for lecture in lectures {
            container.mainContext.insert(lecture)
            lecture.course = course
            lecture.isValidated = true
        }

        // --- Course 2: Math ---
        let course2 = Course(
            courseNumber: "18.06",
            title: "Linear Algebra",
            department: "Mathematics",
            semester: "Spring",
            year: 2010
        )
        container.mainContext.insert(course2)

        let lecture3 = Lecture(
            title: "The Geometry of Linear Equations",
            youtubeId: "J7DzL2_Na80",
            courseNumber: "18.06",
            courseName: "Linear Algebra",
            department: "Mathematics",
            semester: "Spring",
            year: 2010,
            topicName: "Mathematics"
        )
        container.mainContext.insert(lecture3)
        lecture3.course = course2
        lecture3.isValidated = true

        // --- Course 3: Stanford CS229 (multi-source) ---
        let stanfordCourse = Course(
            courseNumber: "CS229",
            title: "Machine Learning",
            department: "Computer Science",
            semester: "",
            year: 2018
        )
        stanfordCourse.sourceId = "stanford"
        container.mainContext.insert(stanfordCourse)

        let stanfordLecture = Lecture(
            title: "Stanford CS229: Machine Learning - Lecture 1",
            youtubeId: "jGwO_UgTS7I",
            courseNumber: "CS229",
            courseName: "Machine Learning",
            department: "Computer Science",
            semester: "",
            year: 2018,
            topicName: "Machine Learning"
        )
        stanfordLecture.sourceId = "stanford"
        container.mainContext.insert(stanfordLecture)
        stanfordLecture.course = stanfordCourse
        stanfordLecture.isValidated = true

        return container
    }()

    static var sampleLecture: Lecture {
        try! container.mainContext.fetch(FetchDescriptor<Lecture>()).first!
    }

    static var sampleCourse: Course {
        try! container.mainContext.fetch(FetchDescriptor<Course>()).first!
    }

    static var sampleStanfordCourse: Course {
        try! container.mainContext.fetch(FetchDescriptor<Course>())
            .first(where: { $0.sourceId == "stanford" })!
    }
}
#endif
