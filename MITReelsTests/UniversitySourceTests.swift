import Testing
@testable import MITReels

/// Verify the UniversitySource registry is complete and consistent.
struct UniversitySourceTests {

    @Test func allSourcesHaveDisplayName() {
        for source in UniversitySource.allCases {
            #expect(!source.displayName.isEmpty, "Missing displayName for \(source.rawValue)")
        }
    }

    @Test func allSourcesHaveShortName() {
        for source in UniversitySource.allCases {
            #expect(!source.shortName.isEmpty, "Missing shortName for \(source.rawValue)")
        }
    }

    @Test func allSourcesHaveSystemImage() {
        for source in UniversitySource.allCases {
            #expect(!source.systemImage.isEmpty, "Missing systemImage for \(source.rawValue)")
        }
    }

    @Test func allSourcesHaveYoutubeChannelId() {
        for source in UniversitySource.allCases {
            #expect(!source.youtubeChannelId.isEmpty, "Missing channelId for \(source.rawValue)")
        }
    }

    @Test func mitRawValueMatchesLectureDefault() {
        #expect(UniversitySource.mit.rawValue == "mit")
    }

    @Test func allCasesCountIs56() {
        #expect(UniversitySource.allCases.count == 56)
    }

    @Test func mitUsesOcwSitemap() {
        #expect(UniversitySource.mit.contentType == .ocwSitemap)
    }

    @Test func nonMitUsesYoutubeApi() {
        for source in UniversitySource.allCases where source != .mit {
            #expect(source.contentType == .youtubeAPI, "\(source.rawValue) should use youtubeAPI")
        }
    }

    @Test func isUniversityClassification() {
        #expect(UniversitySource.stanford.isUniversity == true)
        #expect(UniversitySource.threeBlue1Brown.isUniversity == false)
        #expect(UniversitySource.khanAcademy.isUniversity == false)
    }

    @Test func rawValueRoundTrips() {
        for source in UniversitySource.allCases {
            #expect(UniversitySource(rawValue: source.rawValue) == source)
        }
    }
}
