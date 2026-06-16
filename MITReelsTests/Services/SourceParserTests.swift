import Testing
import Foundation
@testable import MITReels

/// Table-driven coverage for the pure `SourceParser`. Every supported kind, the
/// scheme-less normalization path, and each rejection reason are exercised.
///
/// The parser is referentially transparent, so these cases fully characterize
/// its behavior — there is no hidden state or I/O to mock.
struct SourceParserTests {
    // MARK: - Accepted: YouTube videos

    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ",
        "http://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "youtu.be/dQw4w9WgXcQ",                                  // scheme-less
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc123", // video wins over list
    ])
    func classifiesYouTubeVideo(_ input: String) {
        let result = SourceParser.parse(input)
        #expect(result == .success(ParsedSource(kind: .youtubeVideo, ref: "dQw4w9WgXcQ")))
    }

    // MARK: - Accepted: YouTube playlists

    @Test func classifiesPlaylist() {
        let result = SourceParser.parse("https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
        #expect(result == .success(ParsedSource(
            kind: .youtubePlaylist,
            ref: "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"
        )))
    }

    // MARK: - Accepted: images

    @Test(arguments: [
        "https://example.com/photo.png",
        "https://cdn.site.org/a/b/c/image.JPEG",
        "https://example.com/pic.webp",
        "https://example.com/animation.gif?cachebust=1",        // query after extension
    ])
    func classifiesImage(_ input: String) {
        let result = SourceParser.parse(input)
        #expect((try? result.get())?.kind == .image)
    }

    // MARK: - Accepted: web pages

    @Test(arguments: [
        "https://en.wikipedia.org/wiki/MIT_OpenCourseWare",
        "http://example.com",
        "example.com/page",                                      // scheme-less normalization
        "https://ocw.mit.edu/courses/",
    ])
    func classifiesWebPage(_ input: String) {
        let result = SourceParser.parse(input)
        #expect((try? result.get())?.kind == .webPage)
    }

    // MARK: - Rejected: with specific reasons

    @Test func rejectsEmpty() {
        #expect(SourceParser.parse("   \n  ") == .failure(.empty))
        #expect(SourceParser.parse("") == .failure(.empty))
    }

    @Test(arguments: [
        "https://www.youtube.com/channel/UCabc123",
        "https://www.youtube.com/c/SomeCreator",
        "https://www.youtube.com/user/legacyName",
        "https://www.youtube.com/@handleName",
    ])
    func rejectsYouTubeChannels(_ input: String) {
        #expect(SourceParser.parse(input) == .failure(.youtubeChannelUnsupported))
    }

    @Test(arguments: [
        "just some prose",                                       // whitespace → not a URL
        "hello",                                                 // no host shape
        "youtube channel of foo",
    ])
    func rejectsNonURLs(_ input: String) {
        #expect(SourceParser.parse(input) == .failure(.notAURL))
    }

    @Test func rejectsUnsupportedScheme() {
        if case .failure(.unsupportedHost) = SourceParser.parse("ftp://files.example.com/a.png") {
            // ok
        } else {
            Issue.record("Expected .unsupportedHost for ftp scheme")
        }
    }

    @Test(arguments: [
        "https://youtu.be/tooShort",                            // bad id length
        "https://www.youtube.com/watch?v=bad",                  // bad id length
        "https://www.youtube.com/",                             // no video/playlist
    ])
    func rejectsUnrecognizedYouTube(_ input: String) {
        let result = SourceParser.parse(input)
        #expect(result == .failure(.unrecognized))
    }

    // MARK: - Purity / totality

    /// Same input → same output, and parse never throws or traps for arbitrary
    /// strings (it is total). A light fuzz over odd inputs guards the totality.
    @Test func isTotalAndDeterministic() {
        let inputs = ["", " ", "::::", "https://", "http://?", "a.b", "🎬", "https://x.io/💥.png"]
        for input in inputs {
            let a = SourceParser.parse(input)
            let b = SourceParser.parse(input)
            #expect(a == b)  // deterministic
        }
    }
}
