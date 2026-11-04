#!/usr/bin/env swift
// Renders the images of README.md from the App Store screenshots and the app icon: the icon with the rounded corners
// iOS gives it, a banner of five phones and one phone per screenshot for the gallery. The phones are drawn around the
// screenshots: a black bezel with a metal rim and the Dynamic Island, which a screenshot never shows
// (scripts/screen_drawn.swift has a capture taken again when the Simulator drew it in).
//
// usage: readme_images [<screenshots> [<output>]]
// <screenshots> holds the English screenshots of `make screenshots-sim` (default fastlane/screenshots/en-US), of which
// the 6.3" ones are used; <output> is where the images go (default docs/images). Exits 64 for wrong arguments, 66 when
// an image cannot be read and 73 when one cannot be written.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The simulator of the 6.3" screenshots in scripts/capture_screenshots.sh: 1206 × 2622 pixels, 402 × 874 points.
let device = "iPhone 18 Pro"

/// The scenes of scripts/capture_screenshots.sh, in App Store order. The gallery shows all of them.
let scenes = ["01-start", "02-calibration", "03-sunny", "04-rain", "05-storm", "06-lobby", "07-results", "08-shop"]

/// The banner: its size in pixels (2:1, so it also fits GitHub's social preview) and its phones, back to front, by
/// the horizontal offset of their center from the banner's center and the height of their screen.
let bannerSize = CGSize(width: 2000, height: 1000)
let bannerPhones: [(scene: String, offset: CGFloat, height: CGFloat)] = [
    ("01-start", -727, 600), ("06-lobby", 727, 600),
    ("03-sunny", -390, 720), ("07-results", 390, 720),
    ("05-storm", 0, 840),
]

/// The width of a gallery phone in pixels, bezel included: twice the 180 points README.md shows it at.
let galleryWidth: CGFloat = 360

/// The width of the icon in pixels: twice the 128 points README.md shows it at.
let iconSize = 256

/// The proportions of the phone, as fractions of the screen's width: about those of a 6.3" iPhone with a Dynamic
/// Island, whose 402-point screen has corners of about 60 points and an island of 125 × 37 points, 11 points below
/// the top edge.
enum Phone {
    static let cornerRadius: CGFloat = 0.15
    static let bezel: CGFloat = 0.034
    static let rim: CGFloat = 0.0075
    static let islandWidth: CGFloat = 0.31
    static let islandHeight: CGFloat = 0.0915
    static let islandTop: CGFloat = 0.0275
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count <= 2 else {
    FileHandle.standardError.write(Data("usage: readme_images [<screenshots> [<output>]]\n".utf8))
    exit(64)
}

let screenshotDirectory = URL(fileURLWithPath: arguments.first ?? "fastlane/screenshots/en-US")
let outputDirectory = URL(fileURLWithPath: arguments.dropFirst().first ?? "docs/images")
let iconFile = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data("readme_images: \(message)\n".utf8))
    exit(code)
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail(66, "cannot read \(url.path)") }
    return image
}

/// Everything is read before anything is written, so a missing screenshot leaves the previous images alone.
let screenshots = Dictionary(uniqueKeysWithValues: scenes.map { scene in
    (scene, loadImage(screenshotDirectory.appendingPathComponent("\(device)-\(scene).jpg")))
})
let icon = loadImage(iconFile)

func screenshot(_ scene: String) -> CGImage {
    guard let image = screenshots[scene] else { fail(66, "no screenshot of the scene \(scene)") }
    return image
}

/// An sRGB canvas with its origin at the bottom left; `opaque` leaves out the alpha channel.
func makeCanvas(width: Int, height: Int, opaque: Bool) -> CGContext {
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let canvas = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: alpha.rawValue
          )
    else { fail(73, "cannot create a canvas of \(width) × \(height) pixels") }
    canvas.interpolationQuality = .high
    return canvas
}

func save(_ canvas: CGContext, as type: UTType, name: String) {
    let url = outputDirectory.appendingPathComponent(name)
    guard let image = canvas.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
    else { fail(73, "cannot write \(url.path)") }
    let options = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary : nil
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { fail(73, "cannot write \(url.path)") }
    print("wrote \(url.path)")
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], at locations: [CGFloat]) -> CGGradient {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
    else { fail(73, "cannot create a gradient") }
    return gradient
}

/// A rounded rectangle with continuous corners like iOS draws them: the curve starts 1.53 radii before the corner and
/// bends gradually instead of joining a quarter circle. The Bézier points are PaintCode's measurement of iOS 7's.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let radius = min(radius, min(rect.width, rect.height) / 2 / 1.52866471)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + 1.52866471 * radius, y: rect.maxY))
    // `back` points from the corner along the edge the path comes from, `onward` along the edge it goes on with.
    func addCorner(_ corner: CGPoint, back: CGVector, onward: CGVector) {
        func point(_ alongBack: CGFloat, _ alongOnward: CGFloat) -> CGPoint {
            CGPoint(
                x: corner.x + (alongBack * back.dx + alongOnward * onward.dx) * radius,
                y: corner.y + (alongBack * back.dy + alongOnward * onward.dy) * radius
            )
        }
        path.addLine(to: point(1.52866471, 0))
        path.addCurve(to: point(0.66993427, 0.06549600), control1: point(1.08849323, 0), control2: point(0.86840689, 0))
        path.addCurve(
            to: point(0.06549600, 0.66993427),
            control1: point(0.37282392, 0.16794942),
            control2: point(0.16794942, 0.37282392)
        )
        path.addCurve(to: point(0, 1.52866471), control1: point(0, 0.86840689), control2: point(0, 1.08849323))
    }
    addCorner(CGPoint(x: rect.maxX, y: rect.maxY), back: CGVector(dx: -1, dy: 0), onward: CGVector(dx: 0, dy: -1))
    addCorner(CGPoint(x: rect.maxX, y: rect.minY), back: CGVector(dx: 0, dy: 1), onward: CGVector(dx: -1, dy: 0))
    addCorner(CGPoint(x: rect.minX, y: rect.minY), back: CGVector(dx: 1, dy: 0), onward: CGVector(dx: 0, dy: 1))
    addCorner(CGPoint(x: rect.minX, y: rect.maxY), back: CGVector(dx: 0, dy: -1), onward: CGVector(dx: 1, dy: 0))
    path.closeSubpath()
    return path
}

/// Draws a phone whose screen fills `screen` and shows `image`. `shadow` is the opacity of the shadow it casts.
func drawPhone(showing image: CGImage, screen: CGRect, shadow: CGFloat, in canvas: CGContext) {
    let width = screen.width
    let body = screen.insetBy(dx: -Phone.bezel * width, dy: -Phone.bezel * width)
    let bodyRadius = (Phone.cornerRadius + Phone.bezel) * width
    let bodyShape = continuousRoundedRect(body, radius: bodyRadius)

    if shadow > 0 {
        canvas.saveGState()
        canvas.setShadow(
            offset: CGSize(width: 0, height: -0.045 * width),
            blur: 0.16 * width,
            color: color(0x2A1404, alpha: shadow)
        )
        canvas.addPath(bodyShape)
        canvas.setFillColor(color(0x4A4A50))
        canvas.fillPath()
        canvas.restoreGState()
    }

    // The metal rim: a diagonal gradient over the whole body, of which the black bezel leaves a thin edge.
    canvas.saveGState()
    canvas.addPath(bodyShape)
    canvas.clip()
    canvas.drawLinearGradient(
        gradient([color(0xB8B8BE), color(0x4A4A50), color(0x8E8E95)], at: [0, 0.55, 1]),
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )
    canvas.restoreGState()
    let rim = max(1.5, Phone.rim * width)
    canvas.addPath(continuousRoundedRect(body.insetBy(dx: rim, dy: rim), radius: bodyRadius - rim))
    canvas.setFillColor(color(0x050505))
    canvas.fillPath()

    canvas.saveGState()
    canvas.addPath(continuousRoundedRect(screen, radius: Phone.cornerRadius * width))
    canvas.clip()
    canvas.draw(image, in: screen)
    canvas.restoreGState()

    let island = CGRect(
        x: screen.midX - Phone.islandWidth * width / 2,
        y: screen.maxY - (Phone.islandTop + Phone.islandHeight) * width,
        width: Phone.islandWidth * width,
        height: Phone.islandHeight * width
    )
    canvas.addPath(CGPath(
        roundedRect: island,
        cornerWidth: island.height / 2,
        cornerHeight: island.height / 2,
        transform: nil
    ))
    canvas.setFillColor(color(0x000000))
    canvas.fillPath()
}

let screenAspect: CGFloat = 2622.0 / 1206.0

do {
    try FileManager.default.createDirectory(
        at: outputDirectory.appendingPathComponent("screens"),
        withIntermediateDirectories: true
    )
} catch {
    fail(73, "cannot create \(outputDirectory.path)/screens: \(error.localizedDescription)")
}

// The icon, masked like on the home screen.
do {
    let canvas = makeCanvas(width: iconSize, height: iconSize, opaque: false)
    let square = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
    canvas.addPath(continuousRoundedRect(square, radius: 0.225 * CGFloat(iconSize)))
    canvas.clip()
    canvas.draw(icon, in: square)
    save(canvas, as: .png, name: "icon.png")
}

// The banner, on the warm gradient of the icon: light at the top right, orange at the bottom left.
do {
    let canvas = makeCanvas(width: Int(bannerSize.width), height: Int(bannerSize.height), opaque: true)
    let size = bannerSize
    canvas.drawLinearGradient(
        gradient([color(0xFFE39E), color(0xF7B256), color(0xEE8A34)], at: [0, 0.55, 1]),
        start: CGPoint(x: size.width, y: size.height),
        end: .zero,
        options: []
    )
    let glowCenter = CGPoint(x: size.width / 2, y: size.height * 0.55)
    canvas.drawRadialGradient(
        gradient([color(0xFFF4DA, alpha: 0.55), color(0xFFF4DA, alpha: 0)], at: [0, 1]),
        startCenter: glowCenter,
        startRadius: 0,
        endCenter: glowCenter,
        endRadius: size.width * 0.42,
        options: []
    )
    for phone in bannerPhones {
        let width = phone.height / screenAspect
        let screen = CGRect(
            x: size.width / 2 + phone.offset - width / 2,
            y: (size.height - phone.height) / 2 + 10,
            width: width,
            height: phone.height
        )
        drawPhone(showing: screenshot(phone.scene), screen: screen, shadow: 0.38, in: canvas)
    }
    save(canvas, as: .jpeg, name: "banner.jpg")
}

// One phone per scene, without a shadow, on a transparent background that suits GitHub's light and dark themes.
for scene in scenes {
    let screenWidth = galleryWidth / (1 + 2 * Phone.bezel)
    let bezel = Phone.bezel * screenWidth
    let screen = CGRect(x: bezel, y: bezel, width: screenWidth, height: screenWidth * screenAspect)
    let canvas = makeCanvas(
        width: Int(galleryWidth),
        height: Int((screen.height + 2 * bezel).rounded(.up)),
        opaque: false
    )
    drawPhone(showing: screenshot(scene), screen: screen, shadow: 0, in: canvas)
    save(canvas, as: .png, name: "screens/\(scene).png")
}
