import SwiftUI

struct PauseMenu: View {
    let session: RunSession
    var onQuit: () -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
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
            Toggle(isOn: $settings.isSoundOn) {
                Label("Ton", systemImage: settings.isSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .padding(.horizontal, 6)
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
