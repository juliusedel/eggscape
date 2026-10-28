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
                }
            }
            .navigationTitle("Mehrspieler")
            .toolbar { SettingsToolbarButton() }
        }
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
