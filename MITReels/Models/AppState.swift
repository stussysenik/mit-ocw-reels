import SwiftUI

/// Central, observable source of truth for cross-cutting UI state.
///
/// Injected once at the app root via `.environment`; views read from it and are
/// pure projections of it. A single mutation here — e.g. recoloring a school —
/// reflects everywhere that resolves through `AppState` instantly, which is how
/// the UI stays high-fidelity and snappy instead of relying on scattered
/// singletons each notifying their own observers.
@Observable
final class AppState {
    /// Per-school accent overrides (`school.rawValue` → packed sRGB hex
    /// `0xRRGGBB`). Absent → use the OKLCH default from `SchoolPalette`.
    private(set) var schoolColorOverrides: [String: UInt]

    private let overridesKey = "schoolColorOverrides_v1"

    init() {
        let raw = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Int] ?? [:]
        schoolColorOverrides = raw.compactMapValues { $0 >= 0 ? UInt($0) : nil }
    }

    // MARK: - Resolved colors (semantic layer)

    /// The accent for a school: the user's override if set, else the OKLCH default.
    func accent(for school: MITSchool) -> Color {
        if let hex = schoolColorOverrides[school.rawValue] { return Color(hex: hex) }
        return SchoolPalette.accent(for: school)
    }

    /// The gradient end for a school. Overrides keep a smooth feel by lifting the
    /// chosen color toward white; defaults use the OKLCH same-hue brightening.
    func gradientEnd(for school: MITSchool) -> Color {
        if let hex = schoolColorOverrides[school.rawValue] {
            return Color(hex: hex).lightened(0.28)
        }
        return SchoolPalette.gradientEnd(for: school)
    }

    /// Two-way binding for a school's accent, for use with `ColorPicker`.
    func accentBinding(for school: MITSchool) -> Binding<Color> {
        Binding(
            get: { self.accent(for: school) },
            set: { self.setAccent($0, for: school) }
        )
    }

    // MARK: - Mutations

    func setAccent(_ color: Color, for school: MITSchool) {
        schoolColorOverrides[school.rawValue] = color.hexValue
        persist()
    }

    func resetColor(for school: MITSchool) {
        schoolColorOverrides.removeValue(forKey: school.rawValue)
        persist()
    }

    func resetAllColors() {
        schoolColorOverrides = [:]
        persist()
    }

    var hasColorOverrides: Bool { !schoolColorOverrides.isEmpty }

    private func persist() {
        let dict = schoolColorOverrides.mapValues { Int($0) }
        UserDefaults.standard.set(dict, forKey: overridesKey)
    }
}
