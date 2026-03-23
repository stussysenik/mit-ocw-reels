import Foundation

/// Persists user's enabled/disabled lecture source toggles via UserDefaults.
///
/// MIT is always enabled and cannot be disabled. All other sources default to off
/// until the user explicitly enables them in Settings.
///
/// Storage: comma-separated source IDs in UserDefaults key "enabledSourceIds".
final class SourcePreferences: ObservableObject {
    static let shared = SourcePreferences()

    private let key = "enabledSourceIds"

    /// The set of enabled source IDs. Always includes "mit".
    /// Default: all sources enabled so users see content immediately.
    var enabledSourceIds: Set<String> {
        get {
            if UserDefaults.standard.object(forKey: key) == nil {
                // First launch: enable all sources by default
                return Set(UniversitySource.allCases.map(\.rawValue))
            }
            let raw = UserDefaults.standard.string(forKey: key) ?? "mit"
            var ids = Set(raw.split(separator: ",").map { String($0) })
            ids.insert("mit") // MIT is always on
            return ids
        }
        set {
            var ids = newValue
            ids.insert("mit") // MIT cannot be disabled
            let raw = ids.sorted().joined(separator: ",")
            UserDefaults.standard.set(raw, forKey: key)
            objectWillChange.send()
        }
    }

    func isEnabled(_ source: UniversitySource) -> Bool {
        enabledSourceIds.contains(source.rawValue)
    }

    func setEnabled(_ source: UniversitySource, _ enabled: Bool) {
        var ids = enabledSourceIds
        if enabled {
            ids.insert(source.rawValue)
        } else if source != .mit {
            ids.remove(source.rawValue)
        }
        enabledSourceIds = ids
    }

    /// All sources except MIT (which is always on and not toggleable).
    var toggleableSources: [UniversitySource] {
        UniversitySource.allCases.filter { $0 != .mit }
    }
}
