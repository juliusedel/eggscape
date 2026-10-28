import SwiftUI

/// Tab "Shop": egg skins for coins and coin packs.
struct ShopView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Shop",
                systemImage: "bag.fill",
                description: Text("Hier kaufst du bald gefärbte Eier.")
            )
            .navigationTitle("Shop")
            .toolbar { SettingsToolbarButton() }
        }
    }
}
