import Foundation
import SwiftUI

/// Manages which content sources are enabled for display.
/// Persisted via UserDefaults as a [String: Bool] dictionary.
@Observable
class SourceSettings {
    static let shared = SourceSettings()

    struct Source: Identifiable {
        let id: String
        let name: String
        let icon: String
        let description: String
        var isEnabled: Bool
    }

    var sources: [Source]

    private let defaultsKey = "enabledSources"

    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: "enabledSources") as? [String: Bool] ?? [:]

        sources = [
            Source(
                id: "mit-ocw",
                name: "MIT OpenCourseWare",
                icon: "building.columns",
                description: "Free lecture videos from MIT",
                isEnabled: saved["mit-ocw"] ?? true
            ),
            Source(
                id: "yale",
                name: "Yale Open Courses",
                icon: "book.closed",
                description: "Open Yale courses",
                isEnabled: saved["yale"] ?? false
            ),
            Source(
                id: "harvard",
                name: "Harvard",
                icon: "graduationcap",
                description: "Harvard online learning",
                isEnabled: saved["harvard"] ?? false
            ),
            Source(
                id: "stanford",
                name: "Stanford Online",
                icon: "sparkles",
                description: "Stanford free courses",
                isEnabled: saved["stanford"] ?? false
            ),
            Source(
                id: "oxford",
                name: "Oxford",
                icon: "building",
                description: "Oxford academic lectures",
                isEnabled: saved["oxford"] ?? false
            ),
        ]
    }

    func isEnabled(_ sourceId: String) -> Bool {
        sources.first { $0.id == sourceId }?.isEnabled ?? false
    }

    func setEnabled(_ sourceId: String, _ enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == sourceId }) else { return }
        sources[index].isEnabled = enabled
        persist()
    }

    private func persist() {
        let dict = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.isEnabled) })
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }
}
