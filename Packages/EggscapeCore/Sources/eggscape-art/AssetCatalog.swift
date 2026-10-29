import EggscapeArt
import Foundation

/// Writes the static spoon layers into an asset catalog as @3x image sets.
enum AssetCatalog {
    /// Pixels per bowl unit at @3x. Chosen for the game's original, larger spoon (`u = 0.4133 · 402 pt` on a
    /// 402-point-wide iPhone, times 3); the current layout, `min(0.3 · width, 0.145 · height)` points per unit, needs
    /// less and shrinks the images on screen (`GameArtwork.spoonAssetUnit`).
    static let unit = 498.0

    static func write(to catalog: URL) throws {
        let layers: [(name: String, image: () -> PixelImage)] = [
            ("Spoon", { SpoonArt.spoon(unit: unit) }),
            ("SpoonShadow", { SpoonArt.shadow(unit: unit) }),
            ("SpoonHighlight", { SpoonArt.highlight(unit: unit) }),
        ]
        let manager = FileManager.default
        try manager.createDirectory(at: catalog, withIntermediateDirectories: true)
        let catalogContents = catalog.appendingPathComponent("Contents.json")
        if !manager.fileExists(atPath: catalogContents.path) {
            try Data(contentsJSON(images: nil).utf8).write(to: catalogContents)
        }
        for layer in layers {
            let set = catalog.appendingPathComponent("\(layer.name).imageset")
            try manager.createDirectory(at: set, withIntermediateDirectories: true)
            let fileName = "\(layer.name)@3x.png"
            try PNGFile.write(layer.image(), to: set.appendingPathComponent(fileName))
            try Data(contentsJSON(images: fileName).utf8).write(to: set.appendingPathComponent("Contents.json"))
        }
    }

    /// Xcode's `Contents.json`: a catalog folder when `images` is `nil`, otherwise a universal image set with only a
    /// 3x file (2x devices scale it down at load time).
    static func contentsJSON(images fileName: String?) -> String {
        guard let fileName else {
            return """
            {
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }

            """
        }
        return """
        {
          "images" : [
            {
              "idiom" : "universal",
              "scale" : "1x"
            },
            {
              "idiom" : "universal",
              "scale" : "2x"
            },
            {
              "filename" : "\(fileName)",
              "idiom" : "universal",
              "scale" : "3x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
    }
}
