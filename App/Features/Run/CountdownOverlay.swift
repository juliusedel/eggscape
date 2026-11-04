import SwiftUI

/// How the countdown's numbers and "Los!" come and go: they zoom in and out with a spring, or with Reduce Motion
/// (iOS Settings → Accessibility → Motion) they only fade.
struct CountdownMotion: Equatable {
    /// Scale a number starts from as it appears, settling at 1; 1 itself makes a plain fade.
    var numberEntryScale: CGFloat
    /// Scale a number shrinks to as it goes.
    var numberExitScale: CGFloat
    var numberAnimation: Animation
    /// Scale "Los!" starts from.
    var bannerEntryScale: CGFloat
    var bannerAnimation: Animation

    static let standard = CountdownMotion(
        numberEntryScale: 1.8,
        numberExitScale: 0.6,
        numberAnimation: .spring(duration: 0.35, bounce: 0.45),
        bannerEntryScale: 0.4,
        bannerAnimation: .spring(duration: 0.3, bounce: 0.5)
    )
    static let reduced = CountdownMotion(
        numberEntryScale: 1,
        numberExitScale: 1,
        numberAnimation: .easeInOut(duration: 0.25),
        bannerEntryScale: 1,
        bannerAnimation: .easeOut(duration: 0.25)
    )

    static func forSetting(reduceMotion: Bool) -> CountdownMotion {
        reduceMotion ? .reduced : .standard
    }
}

/// The big "3 – 2 – 1" before the start.
struct CountdownOverlay: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = CountdownMotion.forSetting(reduceMotion: reduceMotion)
        Text(verbatim: "\(count)")
            .font(.system(size: 120, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .id(count)
            .transition(.asymmetric(
                insertion: .scale(scale: motion.numberEntryScale).combined(with: .opacity),
                removal: .scale(scale: motion.numberExitScale).combined(with: .opacity)
            ))
            .animation(motion.numberAnimation, value: count)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -120)
            .accessibilityLabel(Text("Noch \(count)"))
            .accessibilityIdentifier("countdown")
    }
}

/// "Los!" right after the countdown.
struct GoBanner: View {
    var onDone: () -> Void
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = CountdownMotion.forSetting(reduceMotion: reduceMotion)
        Text("Los!")
            .font(.system(size: 88, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(visible ? 1 : motion.bannerEntryScale)
            .opacity(visible ? 1 : 0)
            .offset(y: -120)
            .allowsHitTesting(false)
            .task {
                withAnimation(motion.bannerAnimation) { visible = true }
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeIn(duration: 0.25)) { visible = false }
                try? await Task.sleep(for: .seconds(0.25))
                onDone()
            }
    }
}
