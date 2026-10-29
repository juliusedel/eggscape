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

    @Test func cacheFileNameIsTheSameOnEveryCall() {
        let names = (0 ..< 50).compactMap { _ in
            GameArtwork.cacheFileName(name: "egg", appearance: speckled, width: 320)
        }
        #expect(names.count == 50)
        #expect(Set(names).count == 1)
    }

    @Test func cacheFileNameChangesWithEverythingThatChangesThePixels() {
        var reseeded = speckled
        reseeded.seed = 43
        let name = GameArtwork.cacheFileName(name: "egg", appearance: speckled, width: 320)
        #expect(name != nil)
        #expect(GameArtwork.cacheFileName(name: "broken", appearance: speckled, width: 320) != name)
        #expect(GameArtwork.cacheFileName(name: "egg", appearance: speckled, width: 321) != name)
        #expect(GameArtwork.cacheFileName(name: "egg", appearance: reseeded, width: 320) != name)
    }

    @Test func removesOnlyTheCachesOfOtherRendererVersions() throws {
        let fileManager = FileManager.default
        let caches = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: caches) }
        for name in ["EggArt-v1", "EggArt-v2", GameArtwork.cacheDirectoryName, "Other"] {
            try fileManager.createDirectory(at: caches.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        GameArtwork.removeStaleCaches(in: caches)

        let left = try fileManager.contentsOfDirectory(atPath: caches.path)
        #expect(Set(left) == [GameArtwork.cacheDirectoryName, "Other"])
    }

    @Test func preparedBrokenEggIsTheOneThatDrops() async {
        let artwork = GameArtwork.shared(screenScale: 1)
        let prepared = await artwork.brokenEgg(speckled, widthPixels: 48)
        #expect(await artwork.brokenEgg(speckled, widthPixels: 48) === prepared)
    }
}
