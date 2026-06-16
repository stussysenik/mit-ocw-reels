import SwiftUI

extension Color {
    /// Initialize a Color from OKLCH — the perceptually-uniform cylindrical
    /// space (lightness, chroma, hue). Equal `l` reads as equal perceived
    /// lightness *across all hues*, so a palette built at one `l` gives uniform
    /// text legibility and balanced visual weight — unlike HSL, where same-L
    /// blue and yellow look wildly different.
    ///
    /// - Parameters:
    ///   - l: Perceptual lightness, 0 (black) … 1 (white).
    ///   - c: Chroma (colorfulness), ~0 (gray) … ~0.37 (sRGB max, hue-dependent).
    ///   - h: Hue angle in degrees, 0 … 360.
    ///
    /// Out-of-gamut results are clamped per-channel in linear sRGB (good enough
    /// for UI palettes; swap for a chroma-reducing gamut map if banding appears).
    init(oklch l: Double, _ c: Double, _ h: Double, opacity: Double = 1.0) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)

        // OKLab → LMS (cube of the nonlinear response)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let lms0 = l_ * l_ * l_
        let lms1 = m_ * m_ * m_
        let lms2 = s_ * s_ * s_

        // LMS → linear sRGB
        let rLin =  4.0767416621 * lms0 - 3.3077115913 * lms1 + 0.2309699292 * lms2
        let gLin = -1.2684380046 * lms0 + 2.6097574011 * lms1 - 0.3413193965 * lms2
        let bLin = -0.0041960863 * lms0 - 0.7034186147 * lms1 + 1.7076147010 * lms2

        // Clamp to gamut, then sRGB transfer (linear → gamma-encoded)
        func encode(_ x: Double) -> Double {
            let v = min(max(x, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }

        self.init(
            .sRGB,
            red: encode(rLin),
            green: encode(gLin),
            blue: encode(bLin),
            opacity: opacity
        )
    }
}
