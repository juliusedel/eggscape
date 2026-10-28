import EggscapeArt
import EggscapeCore
import SwiftUI

/// A photo-realistic egg for menus and the shop, rendered off the main thread and cached.
struct EggThumbnail: View {
    let appearance: EggAppearance
    /// Width of the egg in points.
    let width: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // Soft contact shadow, as if the egg lay on a white table lit from the top right.
            Ellipse()
                .fill(.black.opacity(0.16))
                .frame(width: width * 0.85, height: width * 0.28)
                .blur(radius: width * 0.07)
                .offset(x: -width * 0.08, y: width * EggArt.aspect * 0.44)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: width * EggArt.aspect)
                    .transition(.opacity)
            } else {
                EggShape()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: width, height: width * EggArt.aspect)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: appearance) {
            image = await EggImageCache.shared.image(for: appearance, pixelWidth: Int(width * displayScale))
        }
        .accessibilityHidden(true)
    }
}

/// Renders eggs for the UI on background tasks and keeps them in memory.
@MainActor
final class EggImageCache {
    static let shared = EggImageCache()
    private var images: [Key: UIImage] = [:]
    private var inFlight: [Key: Task<UIImage?, Never>] = [:]

    private struct Key: Hashable {
        let appearance: EggAppearance
        let width: Int
    }

    func image(for appearance: EggAppearance, pixelWidth: Int) async -> UIImage? {
        let key = Key(appearance: appearance, width: pixelWidth)
        if let image = images[key] {
            return image
        }
        let task = inFlight[key] ?? Task.detached(priority: .userInitiated) {
            GameArtwork.cgImage(EggArt.egg(appearance, width: pixelWidth)).map { UIImage(cgImage: $0) }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        images[key] = image
        return image
    }
}
