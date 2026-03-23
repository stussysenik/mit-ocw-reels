import Foundation
import Testing
@testable import MITReels

/// Verify SourcePreferences toggle persistence and MIT-always-on invariant.
struct SourcePreferencesTests {

    @Test func defaultEnabledSourcesContainsMIT() {
        let prefs = SourcePreferences()
        // Clear any persisted state
        UserDefaults.standard.removeObject(forKey: "enabledSourceIds")
        #expect(prefs.enabledSourceIds.contains("mit"))
    }

    @Test func mitCannotBeDisabled() {
        let prefs = SourcePreferences()
        prefs.setEnabled(.mit, false)
        #expect(prefs.isEnabled(.mit) == true)
    }

    @Test func toggleSourceOnAndOff() {
        let prefs = SourcePreferences()
        // Start clean
        UserDefaults.standard.removeObject(forKey: "enabledSourceIds")

        prefs.setEnabled(.stanford, true)
        #expect(prefs.isEnabled(.stanford) == true)

        prefs.setEnabled(.stanford, false)
        #expect(prefs.isEnabled(.stanford) == false)
    }

    @Test func toggleableSourcesExcludesMIT() {
        let prefs = SourcePreferences()
        #expect(!prefs.toggleableSources.contains(.mit))
        #expect(prefs.toggleableSources.count == 29) // 30 total - 1 MIT
    }

    @Test func enabledSourceIdsAlwaysContainsMIT() {
        let prefs = SourcePreferences()
        prefs.enabledSourceIds = ["stanford"]
        #expect(prefs.enabledSourceIds.contains("mit"))
        #expect(prefs.enabledSourceIds.contains("stanford"))
    }
}
