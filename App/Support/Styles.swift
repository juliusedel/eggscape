import SwiftUI

extension View {
    /// The prominent action of a screen; Liquid Glass on iOS 26 and later. It is filled with `AccentFill`, a deeper
    /// orange than the dark-mode accent, so the white label stays readable (4.7:1) in both appearances.
    @ViewBuilder
    func primaryActionStyle() -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26, *) {
                buttonStyle(.glassProminent).tint(Color(.accentFill))
            } else {
                buttonStyle(.borderedProminent).tint(Color(.accentFill))
            }
        #else
            buttonStyle(.borderedProminent).tint(Color(.accentFill))
        #endif
    }

    /// Secondary actions next to a primary one.
    @ViewBuilder
    func secondaryActionStyle() -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26, *) {
                buttonStyle(.glass)
            } else {
                buttonStyle(.bordered)
            }
        #else
            buttonStyle(.bordered)
        #endif
    }

    /// A floating panel over the game scene.
    @ViewBuilder
    func floatingPanel(cornerRadius: CGFloat = 28) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26, *) {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
            }
        #else
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        #endif
    }
}

/// Outline of an egg seen from the side, pointy end up.
struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.62),
            control1: CGPoint(x: rect.minX + width * 0.82, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + height * 0.86),
            control2: CGPoint(x: rect.minX + width * 0.78, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + height * 0.62),
            control1: CGPoint(x: rect.minX + width * 0.22, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.minY + height * 0.86)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.34),
            control2: CGPoint(x: rect.minX + width * 0.18, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
