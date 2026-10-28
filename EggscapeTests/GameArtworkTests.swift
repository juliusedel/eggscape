@testable import Eggscape
import EggscapeCore
import Foundation
import Testing

/// A skin with a pattern that has parameters, so its JSON nests keys on several levels.
private let speckled = EggAppearance(
    base: .init(hex: 0xC67B4A),
    pattern: .speckles(color: .init(hex: 0x5A3A22), density: 0.4, size: 0.3),
    finish: .satin,
    seed: 42
)

@MainActor
struct GameArtworkTests {
    @Test func scenesOfOneScreenScaleShareTheArtwork() {
        #expect(GameArtwork.shared(screenScale: 2) === GameArtwork.shared(screenScale: 2))
    }

    @Test func eggTexturesAreKeptForTheCurrentSkinOnly() {
        let artwork = GameArtwork.shared(screenScale: 1)
        let texture = artwork.egg(speckled, widthPixels: 24)
        #expect(artwork.egg(speckled, widthPixels: 24) === texture)

        var other = speckled
        other.seed = 7
        _ = artwork.egg(other, widthPixels: 24)
        #expect(artwork.egg(speckled, widthPixels: 24) !== texture)
    }
}
