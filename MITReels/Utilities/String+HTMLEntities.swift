import Foundation

extension String {
    /// Decodes common HTML entities found in YouTube/OCW data. ~100x faster than
    /// `NSAttributedString(.html)` which spins up a WebKit parser internally.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        return replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
