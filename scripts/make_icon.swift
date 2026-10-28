#!/usr/bin/env swift
// Draws Eggscape's 1024×1024 app icon with CoreGraphics: an egg resting in a stainless-steel spoon, seen from above,
// on a warm yolk-colored background, lit from the top right like the game.
//
// usage: swift scripts/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ]
    ) ?? CGColor(gray: 0, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))
}

/// Egg outline seen from above: an oval that is a little narrower at the top.
func eggPath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let top = CGPoint(x: center.x, y: center.y + height / 2)
    let bottom = CGPoint(x: center.x, y: center.y - height / 2)
    let halfWidth = width / 2
    path.move(to: top)
    path.addCurve(
        to: CGPoint(x: center.x + halfWidth, y: center.y - height * 0.08),
        control1: CGPoint(x: center.x + halfWidth * 0.62, y: top.y),
        control2: CGPoint(x: center.x + halfWidth, y: center.y + height * 0.24)
    )
    path.addCurve(
        to: bottom,
        control1: CGPoint(x: center.x + halfWidth, y: center.y - height * 0.36),
        control2: CGPoint(x: center.x + halfWidth * 0.58, y: bottom.y)
    )
    path.addCurve(
        to: CGPoint(x: center.x - halfWidth, y: center.y - height * 0.08),
        control1: CGPoint(x: center.x - halfWidth * 0.58, y: bottom.y),
        control2: CGPoint(x: center.x - halfWidth, y: center.y - height * 0.36)
    )
    path.addCurve(
        to: top,
        control1: CGPoint(x: center.x - halfWidth, y: center.y + height * 0.24),
        control2: CGPoint(x: center.x - halfWidth * 0.62, y: top.y)
    )
    path.closeSubpath()
    return path
}

/// Deterministic pseudo-random numbers for the speckles.
struct Random {
    var state: UInt64

    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 11) / CGFloat(1 << 53)
    }
}

func drawIcon(in context: CGContext) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background: warm yolk gradient with a soft light from the top right.
    context.setFillColor(color(0xF6A43C))
    context.fill(full)
    if let background = gradient([(0, color(0xFFD36E)), (1, color(0xF08A24))]) {
        context.drawLinearGradient(
            background,
            start: CGPoint(x: 900, y: 1024),
            end: CGPoint(x: 80, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    if let glow = gradient([(0, color(0xFFFFFF, 0.45)), (1, color(0xFFFFFF, 0))]) {
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: 820, y: 860),
            startRadius: 0,
            endCenter: CGPoint(x: 820, y: 860),
            endRadius: 620,
            options: []
        )
    }

    // The spoon lies diagonally: bowl upper right, handle running out at the bottom left.
    context.saveGState()
    context.translateBy(x: 560, y: 560)
    context.rotate(by: -0.62)

    let bowl = CGRect(x: -235, y: -205, width: 470, height: 600)
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: -52, y: -170))
    handle.addCurve(
        to: CGPoint(x: -78, y: -900),
        control1: CGPoint(x: -40, y: -420),
        control2: CGPoint(x: -92, y: -640)
    )
    handle.addLine(to: CGPoint(x: 78, y: -900))
    handle.addCurve(to: CGPoint(x: 52, y: -170), control1: CGPoint(x: 92, y: -640), control2: CGPoint(x: 40, y: -420))
    handle.closeSubpath()

    // Soft shadow of the whole spoon towards the bottom left.
    context.saveGState()
    context.setShadow(offset: CGSize(width: -26, height: -30), blur: 46, color: color(0x6B3200, 0.45))
    context.addPath(handle)
    context.addEllipse(in: bowl)
    context.setFillColor(color(0xB9BFC6))
    context.fillPath()
    context.restoreGState()

    // Handle: convex polished steel, a bright streak along the middle and darker flanks.
    context.saveGState()
    context.addPath(handle)
    context.clip()
    if let steel = gradient([
        (0, color(0x6E767F)), (0.28, color(0xC9CFD6)), (0.46, color(0xFAFBFC)), (0.6, color(0xD5DAE0)),
        (1, color(0x5F676F)),
    ]) {
        context.drawLinearGradient(steel, start: CGPoint(x: -90, y: 0), end: CGPoint(x: 90, y: 0), options: [])
    }
    context.restoreGState()

    // Bowl: concave mirror; dark rim on the near side, bright crescent at the far rim.
    context.saveGState()
    context.addEllipse(in: bowl)
    context.clip()
    if let outer = gradient([(0, color(0x5C646D)), (0.5, color(0xAEB5BD)), (1, color(0xE9ECEF))]) {
        context.drawLinearGradient(outer, start: CGPoint(x: -200, y: -260), end: CGPoint(x: 180, y: 420), options: [])
    }
    let inner = bowl.insetBy(dx: 26, dy: 26)
    context.addEllipse(in: inner)
    context.clip()
    if let concave = gradient([
        (0, color(0xF4F6F8)),
        (0.45, color(0xA9B0B8)),
        (0.8, color(0x6A727B)),
        (1, color(0x4D545C)),
    ]) {
        context.drawRadialGradient(
            concave,
            startCenter: CGPoint(x: -40, y: -60),
            startRadius: 10,
            endCenter: CGPoint(x: 10, y: 60),
            endRadius: 340,
            options: [.drawsAfterEndLocation]
        )
    }
    if let crescent = gradient([(0, color(0xFFFFFF, 0.85)), (1, color(0xFFFFFF, 0))]) {
        context.drawRadialGradient(
            crescent,
            startCenter: CGPoint(x: 60, y: 330),
            startRadius: 0,
            endCenter: CGPoint(x: 60, y: 330),
            endRadius: 190,
            options: []
        )
    }
    context.restoreGState()
    context.addEllipse(in: bowl.insetBy(dx: 3, dy: 3))
    context.setStrokeColor(color(0xFFFFFF, 0.55))
    context.setLineWidth(5)
    context.strokePath()

    // The egg in the bowl, with a soft contact shadow on the steel.
    let eggCenter = CGPoint(x: 10, y: 95)
    let egg = eggPath(center: eggCenter, width: 300, height: 400)
    context.saveGState()
    context.setShadow(offset: CGSize(width: -22, height: -26), blur: 34, color: color(0x1E2328, 0.55))
    context.addPath(egg)
    context.setFillColor(color(0xF3E6D6))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(egg)
    context.clip()
    // Matte shell lit from the top right (in icon space; the spoon is rotated, the light is not).
    context.rotate(by: 0.62)
    if let shell = gradient([
        (0, color(0xFFFDF8)),
        (0.45, color(0xF6EADB)),
        (0.8, color(0xDCC6AE)),
        (1, color(0xB89C82)),
    ]) {
        context.drawRadialGradient(
            shell,
            startCenter: CGPoint(x: 100, y: 150),
            startRadius: 6,
            endCenter: CGPoint(x: 40, y: 70),
            endRadius: 290,
            options: [.drawsAfterEndLocation]
        )
    }
    var random = Random(state: 7)
    for _ in 0 ..< 70 {
        let x = random.next() * 320 - 120
        let y = random.next() * 420 - 120
        let radius = 1.2 + random.next() * 3.2
        context.setFillColor(color(0x9C7B5E, 0.12 + random.next() * 0.22))
        context.fillEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
    }
    context.restoreGState()

    context.restoreGState()
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make_icon.swift <AppIcon.appiconset>\n".utf8))
    exit(64)
}

let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not create a bitmap context")
}

context.interpolationQuality = .high
context.setShouldAntialias(true)
drawIcon(in: context)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          directory.appendingPathComponent("AppIcon.png") as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      )
else {
    fatalError("Could not write the icon")
}

CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)

let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(directory.appendingPathComponent("AppIcon.png").path)")
