import SwiftUI

struct StartView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: "Eggscape")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("start.title")
            Text("Eierlauf für die Hosentasche")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

#Preview {
    StartView()
}
