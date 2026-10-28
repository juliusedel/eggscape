import EggscapeArt
import EggscapeCore
import Foundation

// `eggscape-art`: renders the procedural artwork to PNG.
//
//     eggscape-art preview <dir> [sheet ...]   preview sheets (frame-white, egg-studio, skins, broken, effects)
//     eggscape-art assets <Assets.xcassets>    Spoon, SpoonShadow and SpoonHighlight image sets (@3x)
//     eggscape-art timings                     render times of the expensive textures

let usage = """
usage: eggscape-art preview <dir> [sheet ...]
       eggscape-art assets <Assets.xcassets>
       eggscape-art timings
sheets: \(Previews.sheets.joined(separator: ", "))
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func seconds(_ work: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    work()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
}

/// Median of `runs` timings, after one warm-up run.
func median(runs: Int, _ work: () -> Void) -> Double {
    work()
    let times = (0 ..< runs).map { _ in seconds(work) }.sorted()
    return times[times.count / 2]
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }

do {
    switch command {
    case "preview":
        guard arguments.count >= 2 else { fail(usage) }
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = arguments.count > 2 ? Array(arguments.dropFirst(2)) : Previews.sheets
        for name in names {
            var image: PixelImage?
            let time = seconds { image = Previews.render(name) }
            guard let image else { fail("unknown sheet \(name)\n\(usage)") }
            let url = directory.appendingPathComponent("\(name).png")
            try PNGFile.write(image, to: url)
            print(String(format: "%@  %dx%d  %.2f s", url.path, image.width, image.height, time))
        }
    case "assets":
        guard arguments.count == 2 else { fail(usage) }
        let catalog = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try AssetCatalog.write(to: catalog)
        print("wrote Spoon, SpoonShadow and SpoonHighlight to \(catalog.path)")
    case "timings":
        let egg = median(runs: 9) { _ = EggArt.egg(Samples.farmBrown, width: 320) }
        let broken = median(runs: 5) { _ = EggArt.broken(Samples.farmBrown, width: 400) }
        let spoon = median(runs: 3) { _ = SpoonArt.spoon(unit: 498) }
        let shadow = median(runs: 3) { _ = SpoonArt.shadow(unit: 498) }
        let highlight = median(runs: 3) { _ = SpoonArt.highlight(unit: 498) }
        print(String(format: "EggArt.egg(width: 320)       %7.1f ms", egg * 1000))
        print(String(format: "EggArt.broken(width: 400)    %7.1f ms", broken * 1000))
        print(String(format: "SpoonArt.spoon(unit: 498)    %7.1f ms", spoon * 1000))
        print(String(format: "SpoonArt.shadow(unit: 498)   %7.1f ms", shadow * 1000))
        print(String(format: "SpoonArt.highlight(unit: 498)%7.1f ms", highlight * 1000))
    default:
        fail(usage)
    }
} catch {
    fail("eggscape-art: \(error)")
}
