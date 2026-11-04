#!/usr/bin/env swift
// Tells whether a simulator screenshot already shows the app or still its launch screen, and whether the Simulator
// drew the Dynamic Island into it, for scripts/capture_screenshots.sh. The launch screen is one flat color
// (UILaunchScreen in App/Info.plist), so the spread of the brightness below the status bar sets them apart: it is
// about 0 there and far higher in every staged scene.
//
// A screenshot from a real iPhone never shows the Dynamic Island, but the Simulator now and then draws it into one as
// a black pill at the top center: during the launch, and in about every fourth screenshot of a staged run while the
// run stands still (iOS 27.2 on the iPhone 18 Pro and Pro Max).
//
// usage: screen_drawn <screenshot>
// Prints the spread and exits 0 when the app has drawn its screen, 1 while the screen is still flat, 2 when the app
// has drawn its screen but the Dynamic Island shows, 64 for wrong arguments and 66 when the image cannot be read.

import CoreGraphics
import Foundation
import ImageIO

/// The standard deviation of the brightness (0 to 255) above which a screen counts as drawn. Measured on simulator
/// captures: 0 on the launch screen of the iPhone 18 Pro and Pro Max, 9 on iPhone Duo's outer display, whose status
/// bar sits at the side inside the measured area, and at least 26 in every staged scene.
let threshold = 15.0

/// The brightness (0 to 255) below which a pixel counts as the black of the Dynamic Island.
let black = 40.0

/// The screenshot drawn into memory as 8-bit RGBX, its first row being the top of the screen.
func render(_ image: CGImage) -> CGContext? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: image.width,
              height: image.height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.data == nil ? nil : context
}

/// Calls `body` with the brightness of every pixel in `rows` and `columns`, counted from the top left.
func forEachBrightness(in context: CGContext, rows: Range<Int>, columns: Range<Int>, _ body: (Double) -> Void) {
    guard let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    for row in rows {
        let line = bytes + row * context.bytesPerRow
        for column in columns {
            let pixel = line + column * 4
            // ITU-R 601 luma, the weights of a plain grayscale conversion.
            body((299 * Double(pixel[0]) + 587 * Double(pixel[1]) + 114 * Double(pixel[2])) / 1000)
        }
    }
}

/// The standard deviation of the brightness below the status bar and the Dynamic Island (the top 8 %) and above the
/// home indicator (the bottom 5 %), which the system also draws over the launch screen.
func brightnessSpread(in context: CGContext) -> Double {
    let rows = context.height * 8 / 100 ..< context.height * 95 / 100
    var sum = 0.0
    var sumOfSquares = 0.0
    var count = 0.0
    forEachBrightness(in: context, rows: rows, columns: 0 ..< context.width) { brightness in
        sum += brightness
        sumOfSquares += brightness * brightness
        count += 1
    }
    guard count > 0 else { return 0 }
    let mean = sum / count
    return max(sumOfSquares / count - mean * mean, 0).squareRoot()
}

/// The share of black pixels in the area between the fractions `x` of the width and `y` of the height.
func blackShare(in context: CGContext, x: Range<Double>, y: Range<Double>) -> Double {
    let width = Double(context.width)
    let height = Double(context.height)
    var blackPixels = 0.0
    var count = 0.0
    forEachBrightness(
        in: context,
        rows: Int(height * y.lowerBound) ..< Int(height * y.upperBound),
        columns: Int(width * x.lowerBound) ..< Int(width * x.upperBound)
    ) { brightness in
        if brightness < black {
            blackPixels += 1
        }
        count += 1
    }
    return count > 0 ? blackPixels / count : 0
}

/// Whether the Dynamic Island shows: black in the middle of where it sits and none beside it. The pill covers 38 to
/// 62 % of the width and 1.6 to 5.3 % of the height on the iPhone 18 Pro and Pro Max; the areas beside it lie between
/// the pill and the clock or the status icons. A dark screen, black beside the middle as well, does not count.
func showsIsland(in context: CGContext) -> Bool {
    let rows = 0.02 ..< 0.045
    let middle = blackShare(in: context, x: 0.42 ..< 0.58, y: rows)
    let beside = max(
        blackShare(in: context, x: 0.33 ..< 0.37, y: rows),
        blackShare(in: context, x: 0.63 ..< 0.67, y: rows)
    )
    return middle > 0.8 && beside < 0.2
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: screen_drawn <screenshot>\n".utf8))
    exit(64)
}

let url = URL(fileURLWithPath: arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = render(image)
else {
    FileHandle.standardError.write(Data("screen_drawn: cannot read \(url.path)\n".utf8))
    exit(66)
}

let spread = brightnessSpread(in: context)
let island = showsIsland(in: context)
print(String(format: "%.1f", spread) + (island ? " with the Dynamic Island" : ""))
switch (spread > threshold, island) {
case (false, _):
    exit(1)
case (true, true):
    exit(2)
case (true, false):
    exit(0)
}
