import EggscapeCore
import StoreKit
import SwiftUI

/// The shop's coin page: the coin packs sold through the App Store.
struct CoinShopPage: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let store = services.store
        let notice = PurchaseNotice(store.purchaseState)
        let best = CoinPack.bestValue(prices: Dictionary(
            store.products.map { ($0.id, $0.price) },
            uniquingKeysWith: { first, _ in first }
        ))
        VStack(alignment: .leading, spacing: 14) {
            if store.products.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if store.loadFailed, !store.isLoading {
                        Text("Münzpakete sind gerade nicht verfügbar.")
                            .foregroundStyle(.secondary)
                        Button("Erneut versuchen") {
                            Task { await store.loadProducts() }
                        }
                        .secondaryActionStyle()
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Lade Münzpakete …")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.background, in: .rect(cornerRadius: 20))
            } else {
                ForEach(store.products, id: \.id) { product in
                    if let pack = CoinPack.pack(productID: product.id) {
                        CoinPackCard(product: product, pack: pack, isBestValue: pack == best)
                    }
                }
            }
            Label {
                Text("Münzen verdienst du bei jedem Lauf: je weiter, schneller und wetterfester, desto mehr.")
            } icon: {
                Image(systemName: "figure.run")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        // Shown once: StoreKit does not report a declined "Ask to Buy", so a lasting note would go stale.
        .alert(item: Binding(get: { notice }, set: {
            if $0 == nil {
                store.purchaseState = .idle
            }
        })) { notice in
            Alert(title: notice.title, message: notice.message)
        }
        .task {
            if store.products.isEmpty {
                await store.loadProducts()
            }
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

/// One coin pack as a big card: the coins, the App Store's name and localized price, and a badge on the best offer.
/// The whole card is the buy button.
private struct CoinPackCard: View {
    let product: Product
    let pack: CoinPack
    let isBestValue: Bool
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let store = services.store
        // One row at normal text sizes; stacked at accessibility sizes, where the row would not fit a 375 pt phone.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        Button {
            Task { await store.purchase(product) }
        } label: {
            layout {
                CoinPile(count: (CoinPack.all.firstIndex(of: pack) ?? 0) + 1, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    if isBestValue {
                        Text("Bestes Angebot")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.accentFill), in: .capsule)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(pack.coins, format: .number)
                            .font(.title.bold())
                            .monospacedDigit()
                        Text("Münzen")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text(product.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                priceTag
            }
            .padding(18)
            .background(.background, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isBestValue ? Color.accentColor : .clear, lineWidth: 2.5)
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(Text("\(product.displayName) für \(product.displayPrice) kaufen"))
        .accessibilityValue(isBestValue ? Text("\(pack.coins) Münzen, bestes Angebot") : Text("\(pack.coins) Münzen"))
        .accessibilityIdentifier("shop.pack.\(product.id)")
    }

    /// The App Store's localized price on the accent color, like the app's primary buttons.
    private var priceTag: some View {
        ZStack {
            // Keeps the tag's width while the spinner shows.
            Text(product.displayPrice)
                .monospacedDigit()
                .opacity(isPurchasing ? 0 : 1)
            if isPurchasing {
                ProgressView()
                    .tint(.white)
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.accentFill), in: .capsule)
    }

    private var isPurchasing: Bool {
        services.store.purchaseState == .purchasing(productID: product.id)
    }

    private var isBusy: Bool {
        if case .purchasing = services.store.purchaseState {
            true
        } else {
            false
        }
    }
}

/// One to three coins in a little pile, more for a bigger pack.
private struct CoinPile: View {
    let count: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(offsets.enumerated()), id: \.offset) { _, offset in
                CoinIcon(size: size)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .offset(x: offset.width * size, y: offset.height * size)
            }
        }
        .frame(width: size * 1.6, height: size * 1.4)
        .accessibilityHidden(true)
    }

    /// Coin centers in coin sizes, from the back of the pile to the front.
    private var offsets: [CGSize] {
        switch count {
        case ...1:
            [.zero]
        case 2:
            [CGSize(width: -0.2, height: 0.12), CGSize(width: 0.2, height: -0.12)]
        default:
            [CGSize(width: -0.28, height: 0.16), CGSize(width: 0.28, height: 0.16), CGSize(width: 0, height: -0.16)]
        }
    }
}
