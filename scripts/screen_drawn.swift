#!/usr/bin/env swift
// Tells whether a simulator screenshot already shows the app or still its launch screen, for
// scripts/capture_screenshots.sh. The launch screen is one flat color (UILaunchScreen in App/Info.plist), so the spread
// of the brightness below the status bar sets them apart: it is about 0 there and far higher in every staged scene.
//
// usage: screen_drawn <screenshot>
// Prints the spread and exits 0 when the app has drawn its screen, 1 while the screen is still flat, 64 for wrong
// arguments and 66 when the image cannot be read. capture_screenshots.sh compiles it once with swiftc into .build/.

import CoreGraphics
import Foundation
import ImageIO

/// The standard deviation of the brightness (0 to 255) above which a screen counts as drawn. Measured on simulator
/// captures: 0 on the launch screen of the iPhone 18 Pro and Pro Max, 9 on iPhone Duo's outer display, whose status
/// bar sits at the side inside the measured area, and at least 26 in every staged scene.
let threshold = 15.0

/// The standard deviation of the brightness below the status bar and the Dynamic Island (the top 8 %) and above the
/// home indicator (the bottom 5 %), which the system also draws over the launch screen.
func brightnessSpread(of image: CGImage) -> Double? {
    let top = image.height * 8 / 100
    let bottom = image.height * 95 / 100
    guard bottom > top,
          // Cropping counts rows from the top of the image.
          let body = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top)),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: body.width,
              height: body.height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { return nil }
    context.draw(body, in: CGRect(x: 0, y: 0, width: body.width, height: body.height))
    guard let data = context.data else { return nil }

    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var sum = 0.0
    var sumOfSquares = 0.0
    for row in 0 ..< body.height {
        let line = bytes + row * context.bytesPerRow
        for column in 0 ..< body.width {
            let pixel = line + column * 4
            // ITU-R 601 luma, the weights of a plain grayscale conversion.
            let luma = (299 * Double(pixel[0]) + 587 * Double(pixel[1]) + 114 * Double(pixel[2])) / 1000
            sum += luma
            sumOfSquares += luma * luma
        }
    }
    let count = Double(body.width * body.height)
    let mean = sum / count
    return max(sumOfSquares / count - mean * mean, 0).squareRoot()
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: screen_drawn <screenshot>\n".utf8))
    exit(64)
}

let url = URL(fileURLWithPath: arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let spread = brightnessSpread(of: image)
else {
    FileHandle.standardError.write(Data("screen_drawn: cannot read \(url.path)\n".utf8))
    exit(66)
}

print(String(format: "%.1f", spread))
exit(spread > threshold ? 0 : 1)
