import SwiftUI

// MARK: - Golden Ratio Spacing
// Base: x = 16pt (1em), y = φ (1.618)
// Every spacing value derives from these two constants.

enum Spacing {
    /// x / 2 = 8pt — tight inner gaps (text-to-text within a group)
    static let xs: CGFloat = 8
    /// x / y ≈ 10pt — icon-to-text gaps, small gutters
    static let sm: CGFloat = 10
    /// x = 16pt — horizontal padding, standard margins
    static let md: CGFloat = 16
    /// x · √y ≈ 20pt — section gaps, card-to-content spacing
    static let lg: CGFloat = 20
    /// x · y ≈ 26pt — major section separators, safe area margins
    static let xl: CGFloat = 26
}

// MARK: - Corner Radii (derived from spacing scale)

enum Radius {
    /// x · √y = 20pt — cards, video player
    static let card: CGFloat = 20
    /// xs = 8pt — small badges, pills
    static let badge: CGFloat = 8
    /// sm = 10pt — search bar, input fields
    static let search: CGFloat = 10
}

// MARK: - IBM Carbon Design Palette (White Theme)
// 60/30/10 distribution: surfaces / text / accent
// All contrast ratios verified against WCAG 2.1 on white (#FFFFFF).

enum CarbonColor {
    // --- Surfaces (60%) ---

    /// Gray 10 — app background, grouped areas
    static let background = Color(hex: 0xF4F4F4)
    /// White — card surfaces, content areas
    static let layer01 = Color.white
    /// Gray 20 — hover states, search bar fill
    static let layerHover = Color(hex: 0xE0E0E0)

    // --- Text (30%) ---

    /// Gray 100 — titles, course numbers (18.1:1 on white, AAA)
    static let textPrimary = Color(hex: 0x161616)
    /// Gray 70 — subtitles, course names (7.8:1 on white, AAA)
    static let textSecondary = Color(hex: 0x525252)
    /// Gray 40 — lecture counts, hints (2.4:1, decorative only)
    static let textPlaceholder = Color(hex: 0xA8A8A8)
    /// Gray 60 — uppercase labels, topic names (5.0:1 on white, AA)
    static let textLabel = Color(hex: 0x6F6F6F)
    /// Gray 30 — chevrons, decorative separators
    static let textTertiary = Color(hex: 0xC6C6C6)

    // --- Interactive (10%) ---

    /// MIT Cardinal — active tabs, lecture labels (7.5:1 on white, AAA)
    static let interactive = Color(hex: 0xA31F34)

    // --- Light Reel Surfaces ---

    /// White — reel card background in light mode (alias for layer01)
    static let reelBackground = layer01

    // --- School Gradient Endpoints ---

    static let engineeringGradientEnd = Color(hex: 0x5BA3CC)
    static let scienceGradientEnd = Color(hex: 0x8FC455)
    static let archPlanningGradientEnd = Color(hex: 0xE8C96A)
    static let humanitiesGradientEnd = Color(hex: 0xD07BA8)
    static let crossDiscGradientEnd = Color(hex: 0xA0A0A0)
}

// MARK: - Typography Scale (NASA-inspired)

enum Typography {
    /// Hero course number on reel cards
    static let heroNumber: Font = .system(.largeTitle, design: .default).bold()
    /// Course title on reel
    static let reelTitle: Font = .headline
    /// Metadata line
    static let reelMeta: Font = .caption
}

// MARK: - MITSchool Gradient Extension

extension MITSchool {
    var gradientEndColor: Color {
        switch self {
        case .engineering: return CarbonColor.engineeringGradientEnd
        case .science: return CarbonColor.scienceGradientEnd
        case .architecturePlanning: return CarbonColor.archPlanningGradientEnd
        case .humanitiesArts: return CarbonColor.humanitiesGradientEnd
        case .crossDisciplinary: return CarbonColor.crossDiscGradientEnd
        }
    }
}

// MARK: - Section Header Style

extension Text {
    func sectionHeader() -> some View {
        self.font(.caption2)
            .foregroundStyle(CarbonColor.textLabel)
            .textCase(.uppercase)
            .tracking(1)
    }
}
