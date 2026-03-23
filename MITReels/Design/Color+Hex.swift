import SwiftUI

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
}
