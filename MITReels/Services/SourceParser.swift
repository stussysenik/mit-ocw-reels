import Foundation

/// Pure, total classifier for a pasted source reference.
///
/// `parse` is referentially transparent: the same input always yields the same
/// `Result`, with no I/O, no network, and no global state. This is what makes
/// the build-mode "add a source" flow deterministic and exhaustively testable.
///
/// Classification order (first match wins):
///   1. Empty / whitespace            → `.empty`
///   2. Contains whitespace           → `.notAURL` (URLs never contain spaces)
///   3. Normalize a scheme-less host  → prepend `https://`
///   4. YouTube host → video / playlist / channel(unsupported)
///   5. http(s) URL with image extension → `.image`
///   6. Any other http(s) URL         → `.webPage`
///   7. Otherwise                     → `.notAURL` / `.unsupportedHost`
enum SourceParser {
    /// File extensions we treat as a directly-renderable image source.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "avif",
    ]

    /// Hosts (suffix-matched) that route into the YouTube classifier.
    private static let youtubeHosts: Set<String> = [
        "youtube.com", "youtu.be", "youtube-nocookie.com",
    ]

    static func parse(_ rawInput: String) -> Result<ParsedSource, SourceParseError> {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        // URLs never contain interior whitespace. Reject prose like
        // "youtube channel of foo" before we try to coerce it into a URL.
        guard !trimmed.contains(where: \.isWhitespace) else { return .failure(.notAURL) }

        guard let url = normalizedURL(from: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return .failure(.notAURL)
        }

        // Only web schemes are supported as sources.
        guard scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedHost(url.scheme ?? trimmed))
        }

        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if isYouTubeHost(bareHost) {
            return classifyYouTube(url: url, bareHost: bareHost)
        }

        // Non-YouTube web URL: image by extension, else a web page.
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            return .success(ParsedSource(kind: .image, ref: url.absoluteString))
        }
        return .success(ParsedSource(kind: .webPage, ref: url.absoluteString))
    }

    // MARK: - YouTube

    private static func isYouTubeHost(_ bareHost: String) -> Bool {
        // Match the host itself or any subdomain of it (m., music., etc.).
        youtubeHosts.contains { bareHost == $0 || bareHost.hasSuffix(".\($0)") }
    }

    /// Classify a known-YouTube URL into video / playlist / channel.
    ///
    /// A `watch?v=` URL is a *video* even when it also carries a `list=`
    /// parameter (the user pasted a video that happens to sit in a playlist).
    /// A bare `playlist?list=` URL is a playlist. Channels/users/handles are
    /// explicitly unsupported.
    private static func classifyYouTube(url: URL, bareHost: String)
        -> Result<ParsedSource, SourceParseError> {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            (components?.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let v = item.value else { return nil }
                return (item.name, v)
            },
            uniquingKeysWith: { first, _ in first }
        )
        // Drop the leading "/" and split into non-empty path segments.
        let segments = url.path.split(separator: "/").map(String.init)
        let first = segments.first?.lowercased()

        // youtu.be/<id> short links: the id is the first path segment.
        if bareHost == "youtu.be" {
            if let id = segments.first, let valid = validVideoId(id) {
                return .success(ParsedSource(kind: .youtubeVideo, ref: valid))
            }
            return .failure(.unrecognized)
        }

        // Channel / user / handle forms carry no single playable item.
        if let first, first == "channel" || first == "c" || first == "user" || first.hasPrefix("@") {
            return .failure(.youtubeChannelUnsupported)
        }

        // /watch?v=<id> (video wins even if a list= is also present)
        if first == "watch", let id = query["v"], let valid = validVideoId(id) {
            return .success(ParsedSource(kind: .youtubeVideo, ref: valid))
        }
        // /shorts/<id> and /embed/<id> path-style video links.
        if (first == "shorts" || first == "embed"), segments.count >= 2,
           let valid = validVideoId(segments[1]) {
            return .success(ParsedSource(kind: .youtubeVideo, ref: valid))
        }
        // /playlist?list=<id> — a real playlist.
        if first == "playlist", let list = query["list"], !list.isEmpty {
            return .success(ParsedSource(kind: .youtubePlaylist, ref: list))
        }

        return .failure(.unrecognized)
    }

    /// A YouTube video id is exactly 11 chars from the URL-safe base64 alphabet.
    /// Returns the id when valid, else `nil`.
    private static func validVideoId(_ candidate: String) -> String? {
        guard candidate.count == 11 else { return nil }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return candidate.unicodeScalars.allSatisfy(allowed.contains) ? candidate : nil
    }

    // MARK: - URL normalization

    /// Build a URL from the trimmed input, prepending `https://` for a
    /// scheme-less but host-shaped string like `example.com/page` or
    /// `youtu.be/abc`. Returns `nil` when the input can't be a URL at all.
    private static func normalizedURL(from trimmed: String) -> URL? {
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        // Scheme-less: only coerce when it looks like a host (has a dot and a
        // non-empty TLD), so plain words don't become bogus URLs.
        let head = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
        guard head.contains("."),
              let tld = head.split(separator: ".").last,
              tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }) else {
            return nil
        }
        return URL(string: "https://\(trimmed)")
    }
}
