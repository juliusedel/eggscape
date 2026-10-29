import GameKit
import SwiftUI

/// "Online": race 2-4 players over Game Center, found by Apple's matchmaker or invited as friends.
struct OnlineView: View {
    /// Opened for an accepted invitation (see `RootView`) rather than in the Mehrspieler tab.
    private let isInvitation: Bool
    @Environment(AppServices.self) private var services
    /// The accepted invitation, for the first matchmaker only: GameKit takes it once, so later matchmakers start from a
    /// new match request.
    @State private var pendingInvite: GKInvite?
    @State private var session: NearbySession?
    /// A match whose players are still connecting; the race room opens once all of them are there.
    @State private var pendingMatch: GameKitTransport?
    /// Why the last match did not get going.
    @State private var failure: String?
    @State private var showsMatchmaker = false
    @State private var signInOwner = LeaseOwner()
    @State private var matchmakerOwner = LeaseOwner()

    init(invite: GKInvite? = nil) {
        isInvitation = invite != nil
        _pendingInvite = State(initialValue: invite)
    }

    var body: some View {
        Group {
            if let session {
                RaceRoomView(session: session, onLeave: leave)
            } else if pendingMatch != nil {
                waiting
            } else {
                start
            }
        }
        .navigationTitle("Online")
        .navigationBarTitleDisplayMode(.inline)
        // A tab switch would leave the match (see onDisappear), which ends it for everybody when this phone referees.
        .toolbar(session == nil && pendingMatch == nil ? .automatic : .hidden, for: .tabBar)
        // Only the rooms of the Mehrspieler tab hold invitations back, not the room of an invitation.
        .holdsBackInvitations(
            inRoom: !isInvitation && (session != nil || pendingMatch != nil),
            showsRun: session?.showsRun ?? false,
            leaveRoom: leave
        )
        .onAppear {
            services.gameCenter.signIn(for: signInOwner)
            if pendingInvite != nil {
                showsMatchmaker = true
            }
        }
        .onDisappear {
            services.gameCenter.stopWaitingForSignIn(for: signInOwner)
            leave()
        }
        // However the matchmaker closes (a match, cancelled, failed or swiped away), the invitation is used up.
        .sheet(isPresented: $showsMatchmaker, onDismiss: { pendingInvite = nil }) {
            MatchmakerView(invite: pendingInvite) { match in
                showsMatchmaker = false
                open(GameKitTransport(match: match))
            } onCancel: {
                showsMatchmaker = false
            }
            .ignoresSafeArea()
            // Apple's matchmaker cannot be covered: in the Mehrspieler tab an invitation waits until it has closed.
            .onAppear { services.navigation.setBusy(!isInvitation, for: matchmakerOwner) }
            .onDisappear { services.navigation.setBusy(false, for: matchmakerOwner) }
        }
    }

    /// Leaves the race room, or the match that is still waiting for its players.
    private func leave() {
        session?.leave()
        session = nil
        pendingMatch?.close()
        pendingMatch = nil
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
            if let failure {
                Text(failure)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
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
                Button("Erneut versuchen") { services.gameCenter.signIn(for: signInOwner) }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Warte auf Mitspieler …")
                .foregroundStyle(.secondary)
            Button("Abbrechen", role: .cancel) {
                pendingMatch?.close()
                pendingMatch = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Opens the race room once every player is connected: until then, the phones could disagree on who is in the
    /// race and who referees it.
    private func open(_ match: GameKitTransport) {
        failure = nil
        pendingMatch = match
        Task {
            let isComplete = await match.waitForAllPlayers()
            // Cancelled or left meanwhile.
            guard pendingMatch === match else { return }
            pendingMatch = nil
            if isComplete {
                session = NearbySession(match: match, services: services)
            } else {
                match.close()
                failure = String(localized: "Nicht alle Mitspieler konnten sich verbinden.")
            }
        }
    }
}
