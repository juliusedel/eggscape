import EggscapeCore
import SwiftUI

/// Tab "Shop": egg skins unlocked with coins on one page, coin packs for real money on the other.
struct ShopView: View {
    @Environment(AppServices.self) private var services
    private let top = "shop.top"

    var body: some View {
        @Bindable var navigation = services.navigation
        let showCoins: (() -> Void)? = navigation.shopPage == .coins ? nil : { navigation.showCoinShop() }
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("Shop", selection: $navigation.shopPage) {
                            Text("Eier").tag(AppNavigation.ShopPage.eggs)
                            Text("Münzen").tag(AppNavigation.ShopPage.coins)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("shop.page")

                        BalanceHeader(
                            coins: services.wallet.coins,
                            equipped: services.wallet.equippedSkin,
                            showCoins: showCoins
                        )

                        switch navigation.shopPage {
                        case .eggs:
                            EggShopPage()
                        case .coins:
                            CoinShopPage()
                        }
                    }
                    .padding()
                    .id(top)
                }
                // A page opened from far down the egg grid starts at its top.
                .onChange(of: navigation.shopPage) {
                    scroller.scrollTo(top, anchor: .top)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shop")
            .toolbar { SettingsToolbarButton() }
            .task {
                await services.store.loadProducts()
            }
        }
    }
}

/// Coin balance and the egg currently in use. On the egg page the balance opens the coin shop.
private struct BalanceHeader: View {
    let coins: Int
    let equipped: EggSkin
    var showCoins: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            EggThumbnail(appearance: equipped.appearance, width: 64)
                .frame(width: 76, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                Text("Dein Ei")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(SkinNames.name(for: equipped))
                    .font(.title3.bold())
                if let showCoins {
                    Button(action: showCoins) {
                        HStack(spacing: 6) {
                            balance
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(coins) Münzen"))
                    .accessibilityHint(Text("Zeigt die Münzpakete."))
                    .accessibilityIdentifier("shop.balance")
                } else {
                    balance
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(coins) Münzen"))
                        .accessibilityIdentifier("shop.balance")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
        .animation(.snappy, value: coins)
    }

    private var balance: some View {
        HStack(spacing: 6) {
            CoinIcon(size: 22)
            Text(coins, format: .number)
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}
