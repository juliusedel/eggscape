import SwiftUI

/// The big "3 – 2 – 1" before the start.
struct CountdownOverlay: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 120, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .id(count)
            .transition(.asymmetric(
                insertion: .scale(scale: 1.8).combined(with: .opacity),
                removal: .scale(scale: 0.6).combined(with: .opacity)
            ))
            .animation(.spring(duration: 0.35, bounce: 0.45), value: count)
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

    var body: some View {
        Text("Los!")
            .font(.system(size: 88, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(visible ? 1 : 0.4)
            .opacity(visible ? 1 : 0)
            .offset(y: -120)
            .allowsHitTesting(false)
            .task {
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) { visible = true }
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeIn(duration: 0.25)) { visible = false }
                try? await Task.sleep(for: .seconds(0.25))
                onDone()
            }
    }
}
