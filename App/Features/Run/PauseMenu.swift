import SwiftUI

struct PauseMenu: View {
    let session: RunSession
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Pause")
                .font(.title.bold())
            Button {
                session.resume()
            } label: {
                Label("Weiter", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .primaryActionStyle()
            .accessibilityIdentifier("pause.resume")
            Button {
                session.recalibrate()
            } label: {
                Label("Neu kalibrieren", systemImage: "scope")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .secondaryActionStyle()
            Button(role: .destructive, action: onQuit) {
                Label("Beenden", systemImage: "xmark")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .secondaryActionStyle()
            .accessibilityIdentifier("pause.quit")
        }
        .font(.headline)
        .controlSize(.large)
        .padding(24)
        .frame(maxWidth: 360)
        .floatingPanel()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25))
    }
}
