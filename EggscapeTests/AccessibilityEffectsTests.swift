@testable import Eggscape
import SwiftUI
import Testing

/// Effects that follow the iOS accessibility settings: Dim Flashing Lights tones the lightning down, and Reduce Motion
/// lets the countdown fade instead of zoom. Without the settings everything stays as it was.
struct AccessibilityEffectsTests {
    @Test func dimFlashingLightsTonesTheLightningDown() {
        let standard = LightningFlash.forSetting(dimsFlashingLights: false)
        let dimmed = LightningFlash.forSetting(dimsFlashingLights: true)

        #expect(!dimmed.flickers)
        #expect(dimmed.strikeOpacity <= 0.3)
        #expect(dimmed.strikeRise > 0, "no jump to the brightest white")
        #expect(dimmed.strikeFade > standard.strikeFade)
        // The warning stays, as a slow glow below the strike.
        #expect(dimmed.warningGlow > 0)
        #expect(dimmed.warningGlow < dimmed.strikeOpacity)
    }

    @Test func withoutDimFlashingLightsTheLightningFlashesAsBefore() {
        let standard = LightningFlash.forSetting(dimsFlashingLights: false)

        #expect(standard.flickers)
        #expect(standard.strikeOpacity == 0.9)
        #expect(standard.strikeRise == 0)
        #expect(standard.strikeFade == 0.35)
    }

    @Test func reduceMotionFadesTheCountdownInsteadOfZooming() {
        let reduced = CountdownMotion.forSetting(reduceMotion: true)

        #expect(reduced.numberEntryScale == 1)
        #expect(reduced.numberExitScale == 1)
        #expect(reduced.bannerEntryScale == 1)
        #expect(reduced.numberAnimation != CountdownMotion.standard.numberAnimation, "no spring")
        #expect(reduced.bannerAnimation != CountdownMotion.standard.bannerAnimation, "no spring")
    }

    @Test func withoutReduceMotionTheCountdownZoomsAsBefore() {
        let standard = CountdownMotion.forSetting(reduceMotion: false)

        #expect(standard.numberEntryScale == 1.8)
        #expect(standard.numberExitScale == 0.6)
        #expect(standard.bannerEntryScale == 0.4)
        #expect(standard.numberAnimation == .spring(duration: 0.35, bounce: 0.45))
        #expect(standard.bannerAnimation == .spring(duration: 0.3, bounce: 0.5))
    }
}
