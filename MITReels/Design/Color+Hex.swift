import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Initialize a Color from a hex integer (e.g., `Color(hex: 0xF4F4F4)`).
    /// Uses sRGB color space for consistent rendering across displays.
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Packed sRGB hex (`0xRRGGBB`) of the resolved color. Round-trips with
    /// `Color(hex:)` for persisting a user-picked color.
    var hexValue: UInt {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> UInt { UInt(max(0, min(255, (v * 255).rounded()))) }
        return (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }

    /// Blend toward white by `amount` (0…1) in sRGB — a quick gradient-end lift
    /// for user-chosen colors that don't carry an OKLCH-derived end.
    func lightened(_ amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let t = CGFloat(min(max(amount, 0), 1))
        return Color(
            .sRGB,
            red: Double(r + (1 - r) * t),
            green: Double(g + (1 - g) * t),
            blue: Double(b + (1 - b) * t),
            opacity: Double(a)
        )
    }
}
