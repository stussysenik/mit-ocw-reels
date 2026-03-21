import Testing
@testable import MITReels

/// Verify MITSchool prefix mapping covers all 25 seed data courses
/// and CourseLevel classification follows MIT numbering conventions.
struct MITSchoolTests {

    // MARK: - School of Engineering

    @Test func eecsMapsToEngineering() {
        #expect(MITSchool.from(courseNumber: "6.006") == .engineering)
        #expect(MITSchool.from(courseNumber: "6.041SC") == .engineering)
        #expect(MITSchool.from(courseNumber: "6.100L") == .engineering)
        #expect(MITSchool.from(courseNumber: "6.262") == .engineering)
        #expect(MITSchool.from(courseNumber: "6.849") == .engineering)
    }

    @Test func mechEMapsToEngineering() {
        #expect(MITSchool.from(courseNumber: "2.627") == .engineering)
    }

    @Test func aeroAstroMapsToEngineering() {
        #expect(MITSchool.from(courseNumber: "16.01") == .engineering)
    }

    // MARK: - School of Science

    @Test func chemistryMapsToScience() {
        #expect(MITSchool.from(courseNumber: "5.07SC") == .science)
        #expect(MITSchool.from(courseNumber: "5.74") == .science)
    }

    @Test func biologyMapsToScience() {
        #expect(MITSchool.from(courseNumber: "7.05") == .science)
    }

    @Test func bcsMapsToScience() {
        #expect(MITSchool.from(courseNumber: "9.14") == .science)
    }

    @Test func mathMapsToScience() {
        #expect(MITSchool.from(courseNumber: "18.01SC") == .science)
        #expect(MITSchool.from(courseNumber: "18.03SC") == .science)
        #expect(MITSchool.from(courseNumber: "18.S997") == .science)
    }

    // MARK: - School of Architecture & Planning

    @Test func architectureMapsToArchPlanning() {
        #expect(MITSchool.from(courseNumber: "4.125") == .architecturePlanning)
    }

    @Test func urbanStudiesMapsToArchPlanning() {
        #expect(MITSchool.from(courseNumber: "11.016J") == .architecturePlanning)
        #expect(MITSchool.from(courseNumber: "11.382") == .architecturePlanning)
    }

    // MARK: - School of Humanities, Arts, & Social Sciences

    @Test func anthropologyMapsToHumanities() {
        #expect(MITSchool.from(courseNumber: "21A.S01") == .humanitiesArts)
    }

    @Test func historyMapsToHumanities() {
        #expect(MITSchool.from(courseNumber: "21H.931") == .humanitiesArts)
    }

    @Test func literatureMapsToHumanities() {
        #expect(MITSchool.from(courseNumber: "21L.004") == .humanitiesArts)
        #expect(MITSchool.from(courseNumber: "21L.432") == .humanitiesArts)
    }

    @Test func musicMapsToHumanities() {
        #expect(MITSchool.from(courseNumber: "21M.542") == .humanitiesArts)
    }

    @Test func linguisticsMapsToHumanities() {
        #expect(MITSchool.from(courseNumber: "24.08J") == .humanitiesArts)
    }

    // MARK: - Cross-Disciplinary

    @Test func mediaArtsMapsToXDisc() {
        #expect(MITSchool.from(courseNumber: "MAS.S62") == .crossDisciplinary)
    }

    @Test func ocwResourceMapsToXDisc() {
        #expect(MITSchool.from(courseNumber: "RES.15.005") == .crossDisciplinary)
    }

    // MARK: - CourseLevel Classification

    @Test func introductoryCourses() {
        #expect(CourseLevel.from(courseNumber: "6.006") == .introductory)
        #expect(CourseLevel.from(courseNumber: "18.01SC") == .introductory)
        #expect(CourseLevel.from(courseNumber: "18.03SC") == .introductory)
        #expect(CourseLevel.from(courseNumber: "5.07SC") == .introductory)
        #expect(CourseLevel.from(courseNumber: "5.74") == .introductory)
        #expect(CourseLevel.from(courseNumber: "16.01") == .introductory)
    }

    @Test func intermediateCourses() {
        #expect(CourseLevel.from(courseNumber: "6.262") == .intermediate)
        #expect(CourseLevel.from(courseNumber: "4.125") == .intermediate)
        #expect(CourseLevel.from(courseNumber: "21L.432") == .intermediate)
    }

    @Test func graduateCourses() {
        #expect(CourseLevel.from(courseNumber: "6.849") == .graduate)
        #expect(CourseLevel.from(courseNumber: "21H.931") == .graduate)
    }

    @Test func specialSubjects() {
        #expect(CourseLevel.from(courseNumber: "18.S997") == .special)
        #expect(CourseLevel.from(courseNumber: "21A.S01") == .special)
        #expect(CourseLevel.from(courseNumber: "MAS.S62") == .special)
    }

    // MARK: - Edge Cases

    @Test func jointCoursesSuffix() {
        // "J" suffix should not affect prefix extraction
        #expect(MITSchool.from(courseNumber: "11.016J") == .architecturePlanning)
        #expect(MITSchool.from(courseNumber: "24.08J") == .humanitiesArts)
    }

    @Test func scSuffix() {
        // "SC" (Scholar) suffix should not affect mapping
        #expect(MITSchool.from(courseNumber: "6.041SC") == .engineering)
        #expect(MITSchool.from(courseNumber: "18.01SC") == .science)
    }

    @Test func emptyCourseNumber() {
        #expect(MITSchool.from(courseNumber: "") == .crossDisciplinary)
        #expect(CourseLevel.from(courseNumber: "") == .special)
    }

    // MARK: - School Metadata

    @Test func allSchoolsHaveMetadata() {
        for school in MITSchool.allCases {
            #expect(!school.shortName.isEmpty)
            #expect(!school.systemImage.isEmpty)
            #expect(!school.rawValue.isEmpty)
        }
    }
}
