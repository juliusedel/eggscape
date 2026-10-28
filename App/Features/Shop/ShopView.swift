import EggscapeCore
import StoreKit
import SwiftUI

/// Tab "Shop": egg skins for coins, and coin packs as in-app purchases.
struct ShopView: View {
    @Environment(AppServices.self) private var services
    @State private var pendingSkin: EggSkin?
    @State private var notice: Notice?

    private struct Notice: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let message: LocalizedStringResource
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BalanceHeader(coins: services.wallet.coins, equipped: services.wallet.equippedSkin)

                    Text("Eier")
                        .font(.title2.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(SkinCatalog.all) { skin in
                            Button {
                                select(skin)
                            } label: {
                                SkinCard(
                                    skin: skin,
                                    isOwned: services.wallet.owns(skin),
                                    isEquipped: services.wallet.equippedSkin.id == skin.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("shop.skin.\(skin.id)")
                        }
                    }

                    CoinPacksSection()

                    Text("Münzen verdienst du bei jedem Lauf: je weiter, schneller und wetterfester, desto mehr.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shop")
            .toolbar { SettingsToolbarButton() }
            .confirmationDialog(
                Text("Ei kaufen?"),
                isPresented: Binding(get: { pendingSkin != nil }, set: {
                    if !$0 {
                        pendingSkin = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: pendingSkin
            ) { skin in
                Button {
                    buy(skin)
                } label: {
                    Text("\(Text(SkinNames.name(for: skin))) für \(skin.price) Münzen kaufen")
                }
                .accessibilityIdentifier("shop.confirmPurchase")
                Button("Abbrechen", role: .cancel) {}
            }
            .alert(item: $notice) { notice in
                Alert(title: Text(notice.title), message: Text(notice.message))
            }
            .task {
                await services.store.loadProducts()
            }
        }
    }

    private func select(_ skin: EggSkin) {
        if services.wallet.owns(skin) {
            try? services.wallet.equip(skin)
            services.sounds.play(.plop)
        } else {
            pendingSkin = skin
        }
    }

    private func buy(_ skin: EggSkin) {
        do throws(WalletError) {
            try services.wallet.purchase(skin)
            try services.wallet.equip(skin)
            services.sounds.play(.coin)
        } catch let .insufficientCoins(missing) {
            notice = Notice(
                title: "Nicht genug Münzen",
                message: "Dir fehlen noch \(missing) Münzen. Lauf ein paar Runden oder hol dir ein Münzpaket."
            )
        } catch {
            notice = Notice(title: "Kauf nicht möglich", message: "Bitte versuche es noch einmal.")
        }
    }
}

/// Coin balance and the egg currently in use.
private struct BalanceHeader: View {
    let coins: Int
    let equipped: EggSkin

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
                HStack(spacing: 6) {
                    CoinIcon(size: 22)
                    Text(coins, format: .number)
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(coins) Münzen"))
                .accessibilityIdentifier("shop.balance")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
        .animation(.snappy, value: coins)
    }
}

/// One skin in the grid.
private struct SkinCard: View {
    let skin: EggSkin
    let isOwned: Bool
    let isEquipped: Bool

    var body: some View {
        VStack(spacing: 10) {
            EggThumbnail(appearance: skin.appearance, width: 84)
                .frame(height: 124)
            Text(SkinNames.name(for: skin))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            status
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isEquipped ? Color.accentColor : .clear, lineWidth: 3)
        }
        .overlay(alignment: .topTrailing) {
            if skin.tier >= .epic {
                Text(SkinNames.tier(skin.tier))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        skin.tier == .legendary ? Color.orange.opacity(0.2) : Color.purple.opacity(0.15),
                        in: .capsule
                    )
                    .padding(8)
            }
        }
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SkinNames.name(for: skin)))
        .accessibilityValue(accessibilityStatus)
        .accessibilityAddTraits(isEquipped ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var status: some View {
        if isEquipped {
            Label("Ausgewählt", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } else if isOwned {
            Text("Auswählen")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                CoinIcon(size: 16)
                Text(skin.price, format: .number).monospacedDigit()
            }
        }
    }

    private var accessibilityStatus: Text {
        if isEquipped {
            Text("Ausgewählt")
        } else if isOwned {
            Text("Gekauft")
        } else {
            Text("\(skin.price) Münzen")
        }
    }
}

/// The three coin packs sold through the App Store.
private struct CoinPacksSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let store = services.store
        let notice = PurchaseNotice(store.purchaseState)
        VStack(alignment: .leading, spacing: 12) {
            Text("Münzen")
                .font(.title2.bold())
            if store.products.isEmpty {
                HStack(spacing: 10) {
                    if store.isLoading {
                        ProgressView()
                        Text("Lade Münzpakete …")
                    } else {
                        Text("Münzpakete sind gerade nicht verfügbar.")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.background, in: .rect(cornerRadius: 20))
            } else {
                ForEach(store.products, id: \.id) { product in
                    CoinPackRow(product: product, coins: CoinPack.pack(productID: product.id)?.coins ?? 0)
                }
            }
        }
        // Shown once: StoreKit does not report a declined "Ask to Buy", so a lasting note would go stale.
        .alert(item: Binding(get: { notice }, set: {
            if $0 == nil {
                store.purchaseState = .idle
            }
        })) { notice in
            Alert(title: notice.title, message: notice.message)
        }
    }
}

/// A purchase waiting for approval (e.g. "Ask to Buy") or a failed one, as an alert.
private struct PurchaseNotice: Identifiable {
    let id: String
    let title: Text
    let message: Text

    init?(_ state: StoreService.PurchaseState) {
        switch state {
        case .idle, .purchasing:
            return nil
        case .pending:
            id = "pending"
            title = Text("Kauf ausstehend")
            message = Text("Dein Kauf wartet auf Bestätigung. Die Münzen kommen, sobald er bestätigt ist.")
        case let .failed(reason):
            id = "failed"
            title = Text("Kauf nicht möglich")
            message = Text(reason)
        }
    }
}

private struct CoinPackRow: View {
    let product: Product
    let coins: Int
    @Environment(AppServices.self) private var services

    var body: some View {
        HStack(spacing: 14) {
            CoinIcon(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.headline)
                Text("\(coins) Münzen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await services.store.purchase(product) }
            } label: {
                if services.store.purchaseState == .purchasing(productID: product.id) {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .monospacedDigit()
                }
            }
            .primaryActionStyle()
            .disabled(isBusy)
            .accessibilityLabel(Text("\(product.displayName) für \(product.displayPrice) kaufen"))
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var isBusy: Bool {
        if case .purchasing = services.store.purchaseState {
            true
        } else {
            false
        }
    }
}

/// A small golden coin.
struct CoinIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 1, green: 0.86, blue: 0.4), Color(red: 0.86, green: 0.6, blue: 0.12)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                ))
            Circle()
                .strokeBorder(Color(red: 0.72, green: 0.48, blue: 0.08).opacity(0.7), lineWidth: max(size * 0.07, 1))
                .padding(size * 0.1)
            EggShape()
                .fill(Color(red: 0.98, green: 0.92, blue: 0.7).opacity(0.9))
                .frame(width: size * 0.32, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
