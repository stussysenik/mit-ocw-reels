import Foundation

/// Reads API keys from Info.plist (populated via build settings in project.yml).
///
/// The actual key value is set in project.yml as YOUTUBE_API_KEY build setting,
/// which Xcode injects into the generated Info.plist. Not committed to git.
enum APIKeys {
    static var youtube: String {
        Bundle.main.infoDictionary?["YOUTUBE_API_KEY"] as? String ?? ""
    }
}
