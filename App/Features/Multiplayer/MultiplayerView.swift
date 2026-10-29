import SwiftUI

/// Tab "Mehrspieler": hot-seat on one phone, nearby phones, and online play.
struct MultiplayerView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HotSeatSetupView()
                    } label: {
                        ModeRow(
                            title: "Gemeinsam an einem Handy",
                            detail: "2 bis 4 Spieler laufen nacheinander dieselbe Strecke.",
                            systemImage: "iphone.and.arrow.forward"
                        )
                    }
                    .accessibilityIdentifier("multiplayer.hotSeat")
                    NavigationLink {
                        NearbyView()
                    } label: {
                        ModeRow(
                            title: "In der Nähe",
                            detail: "Bis zu 4 Handys im selben Raum, ganz ohne Internet.",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                    }
                    .accessibilityIdentifier("multiplayer.nearby")
                    NavigationLink {
                        OnlineView()
                    } label: {
                        ModeRow(
                            title: "Online",
                            detail: "2 bis 4 Spieler über Game Center, auch mit Einladungen an Freunde.",
                            systemImage: "globe.europe.africa.fill"
                        )
                    }
                    .accessibilityIdentifier("multiplayer.online")
                }
            }
            .navigationTitle("Mehrspieler")
            .toolbar { SettingsToolbarButton() }
        }
    }
}

extension View {
    /// For the nearby and online rooms of the Mehrspieler tab: an accepted invitation does not cover the room but waits
    /// (see `RootView`). While no run is on screen, the room asks whether to leave it for the invitation.
    func holdsBackInvitations(inRoom: Bool, showsRun: Bool, leaveRoom: @escaping () -> Void) -> some View {
        modifier(RoomInvitationPrompt(isInRoom: inRoom, showsRun: showsRun, leaveRoom: leaveRoom))
    }
}

private struct RoomInvitationPrompt: ViewModifier {
    let isInRoom: Bool
    let showsRun: Bool
    var leaveRoom: () -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var owner = LeaseOwner()

    func body(content: Content) -> some View {
        content
            .onAppear { services.navigation.setBusy(isInRoom, for: owner) }
            .onChange(of: isInRoom) { _, inRoom in services.navigation.setBusy(inRoom, for: owner) }
            .onDisappear { services.navigation.setBusy(false, for: owner) }
            .alert("Einladung annehmen?", isPresented: asksToLeave) {
                Button("Annehmen") {
                    // The invitation appears once the room is gone; the tab goes back to its list meanwhile.
                    leaveRoom()
                    dismiss()
                }
                Button("Ablehnen", role: .cancel) {
                    services.gameCenter.acceptedInvite = nil
                }
            } message: {
                Text("Dafür verlässt du den Raum.")
            }
    }

    /// Not over a run: the run's full-screen cover could not appear while the question is up.
    private var asksToLeave: Binding<Bool> {
        let asks = isInRoom && !showsRun && services.gameCenter.acceptedInvite != nil
        return Binding(get: { asks }, set: { _ in })
    }
}

struct ModeRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 6)
    }
}
