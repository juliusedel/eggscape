import SwiftUI

/// A small golden coin.
struct CoinIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 1, green: 0.86, blue: 0.4), Color(red: 0.86, green: 0.6, blue: 0.12)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                ))
            Circle()
                .strokeBorder(Color(red: 0.72, green: 0.48, blue: 0.08).opacity(0.7), lineWidth: max(size * 0.07, 1))
                .padding(size * 0.1)
            EggShape()
                .fill(Color(red: 0.98, green: 0.92, blue: 0.7).opacity(0.9))
                .frame(width: size * 0.32, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
