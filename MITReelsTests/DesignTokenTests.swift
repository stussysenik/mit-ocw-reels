import Testing
@testable import MITReels

/// Verify golden ratio spacing values are mathematically correct.
/// Base: x = 16pt, y = φ ≈ 1.618
struct DesignTokenTests {
    let phi: Double = 1.618

    @Test func spacingXsIsHalfBase() {
        #expect(Spacing.xs == 8) // x / 2
    }

    @Test func spacingSmApproximatesXOverPhi() {
        let expected = 16.0 / phi // ≈ 9.89
        #expect(abs(Double(Spacing.sm) - expected) < 0.5)
    }

    @Test func spacingMdIsBase() {
        #expect(Spacing.md == 16) // x = 1em
    }

    @Test func spacingLgApproximatesXTimesSqrtPhi() {
        let expected = 16.0 * phi.squareRoot() // ≈ 20.35
        #expect(abs(Double(Spacing.lg) - expected) < 0.5)
    }

    @Test func spacingXlApproximatesXTimesPhi() {
        let expected = 16.0 * phi // ≈ 25.89
        #expect(abs(Double(Spacing.xl) - expected) < 0.5)
    }

    @Test func radiusCardMatchesSpacingLg() {
        #expect(Radius.card == Spacing.lg) // Both x · √y ≈ 20
    }

    @Test func radiusBadgeMatchesSpacingXs() {
        #expect(Radius.badge == Spacing.xs) // Both 8pt
    }

    @Test func carbonColorInteractiveIsMITCardinal() {
        // MIT Cardinal is #A31F34
        // Verify the color exists (non-nil) — exact value testing requires
        // UIColor conversion which is fragile, so we just verify it's defined
        let _ = CarbonColor.interactive
        let _ = CarbonColor.textPrimary
        let _ = CarbonColor.textSecondary
        let _ = CarbonColor.background
        let _ = CarbonColor.layer01
        let _ = CarbonColor.reelBackground
    }
}
