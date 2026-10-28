import EggscapeCore
import SwiftUI

struct StartView: View {
    @Environment(AppServices.self) private var services
    @State private var session: RunSession?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(verbatim: "Eggscape")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("start.title")
            Text("Eierlauf für die Hosentasche")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                startRun()
            } label: {
                Text("Spielen")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .accessibilityIdentifier("start.play")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground").ignoresSafeArea())
        .fullScreenCover(item: $session) { session in
            RunView(session: session, onRestart: startRun, onExit: { self.session = nil })
        }
    }

    private func startRun() {
        let setup = RunSetup(course: .timeTrial(.short), weather: .clear, seed: UInt64.random(in: .min ... .max))
        session = RunSession(setup: setup, motion: services.motion)
    }
}

#Preview {
    StartView()
        .environment(AppServices())
}
