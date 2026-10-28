import Foundation

enum SpoonGeometry {
    static func layout(unit: Double) -> SpoonArt.Layout {
        let width = Int((2 * (0.805 + 0.44) * unit).rounded())
        let height = Int(((1.055 + 0.2 + 4.6) * unit).rounded())
        return SpoonArt.Layout(
            width: width,
            height: height,
            bowlCenterX: Double(width) / 2,
            bowlCenterY: (1.055 + 0.2) * unit,
            unit: unit
        )
    }
}

enum SpoonRenderer {
    enum Layer {
        case spoon, shadow, highlight
    }

    static func render(_: Layer, unit: Double) -> PixelImage {
        let layout = SpoonGeometry.layout(unit: unit)
        return PixelImage(width: layout.width, height: layout.height)
    }
}
