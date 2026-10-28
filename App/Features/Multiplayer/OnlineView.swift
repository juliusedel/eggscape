import GameKit
import SwiftUI

/// "Online": race 2-4 players over Game Center, found by Apple's matchmaker or invited as friends.
struct OnlineView: View {
    var invite: GKInvite?
    @Environment(AppServices.self) private var services
    @State private var session: NearbySession?
    @State private var showsMatchmaker = false

    var body: some View {
        Group {
            if let session {
                RaceRoomView(session: session) {
                    session.leave()
                    self.session = nil
                }
            } else {
                start
            }
        }
        .navigationTitle("Online")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            services.gameCenter.signIn()
            if invite != nil {
                showsMatchmaker = true
            }
        }
        .onDisappear {
            session?.leave()
            session = nil
        }
        .sheet(isPresented: $showsMatchmaker) {
            MatchmakerView(invite: invite) { match in
                showsMatchmaker = false
                session = NearbySession(match: GameKitTransport(match: match), services: services)
            } onCancel: {
                showsMatchmaker = false
            }
            .ignoresSafeArea()
        }
    }

    private var start: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Lauf über das Internet gegen Freunde oder andere Spieler. Dafür meldest du dich bei Game Center an.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            switch services.gameCenter.status {
            case .signedIn:
                Button {
                    showsMatchmaker = true
                } label: {
                    Label("Mitspieler finden", systemImage: "person.2.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .primaryActionStyle()
                .controlSize(.large)
                .accessibilityIdentifier("online.find")
            case .signedOut, .signingIn:
                ProgressView()
            case let .unavailable(message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Erneut versuchen") { services.gameCenter.signIn() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
