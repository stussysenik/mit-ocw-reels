import Foundation

/// The four kinds of source a user can point the loop at. No AI processing is
/// performed on any of them — they are classified and rendered as-is.
enum SourceKind: String, Codable, Sendable, CaseIterable {
    case youtubeVideo
    case youtubePlaylist
    case image
    case webPage
}

/// The result of classifying a pasted reference. `ref` is the *canonical*
/// reference for the kind — a bare YouTube video id (11 chars) or playlist id
/// for the YouTube kinds, and the normalized absolute URL string for image /
/// web-page kinds. Keeping the canonical form here means the persistence and
/// rendering layers never re-parse the raw paste.
struct ParsedSource: Equatable, Sendable {
    let kind: SourceKind
    let ref: String
}

/// Why a pasted reference was rejected. Each case maps to a specific,
/// user-facing reason so the Build UI can explain the rejection precisely
/// rather than failing silently.
enum SourceParseError: Equatable, Error, Sendable {
    /// The input was empty or only whitespace.
    case empty
    /// The input is not a URL (contains spaces, or has no recognizable host).
    case notAURL
    /// A YouTube channel / user / handle URL — not a single video or playlist.
    case youtubeChannelUnsupported
    /// A URL whose host/scheme we don't support (e.g. ftp://, a non-web scheme).
    case unsupportedHost(String)
    /// A URL we couldn't classify into any supported kind.
    case unrecognized

    /// A specific, user-facing reason, per the build-mode spec
    /// ("Reject an unsupported reference").
    var userMessage: String {
        switch self {
        case .empty:
            return "Paste a link to add a source."
        case .notAURL:
            return "That doesn't look like a link."
        case .youtubeChannelUnsupported:
            return "Channels aren't supported yet — paste a video or playlist link."
        case .unsupportedHost(let host):
            return "“\(host)” isn't a supported source yet."
        case .unrecognized:
            return "Couldn't recognize that link."
        }
    }
}
