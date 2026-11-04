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
            VStack(alignment: .leading, spacing: 10) {
                // Hot-seat runs earn nothing (`RunRules.hotSeat`), so the note names the modes that do.
                Label {
                    Text(
                        "Münzen verdienst du im Einzelspieler und bei Rennen in der Nähe oder online: je weiter, schneller und wetterfester, desto mehr."
                    )
                } icon: {
                    Image(systemName: "figure.run")
                }
                // The wallet has no copy in the cloud, and the App Store does not restore consumables such as the
                // coin packs, so buyers learn before they buy that deleting the app also deletes these coins.
                Label {
                    Text(
                        "Münzen werden nur auf diesem Gerät gespeichert. Löschst du die App oder setzt du die Daten zurück, sind sie weg, auch gekaufte."
                    )
                } icon: {
                    Image(systemName: "iphone")
                }
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
    /// StoreKit's buy action for this view's scene (see `StoreService.purchase(_:with:)`).
    @Environment(\.purchase) private var purchase

    var body: some View {
        let store = services.store
        let purchase = purchase
        // One row at normal text sizes; stacked at accessibility sizes, where the row would not fit a 375 pt phone.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        Button {
            Task { await store.purchase(product, with: { try await purchase($0) }) }
        } label: {
            layout {
                CoinPile(count: (CoinPack.all.firstIndex(of: pack) ?? 0) + 1, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    if isBestValue {
                        bestValueBadge
                    }
                    coinCount
                    // Wraps instead of being cut off: App Store Connect allows names of up to 30 characters.
                    Text(product.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // The coins get all the room the pile and the price leave. A spacer here added the row's spacing on
                // both of its sides, which left too little for "2.000 Münzen" on a 402 pt iPhone.
                .frame(maxWidth: .infinity, alignment: .leading)
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

    /// A capsule on one line. Where it has to wrap, as "Bestes Angebot" does at large text sizes on a small phone, the
    /// round ends of a capsule would cut into the text, so it gets rounded corners instead.
    private var bestValueBadge: some View {
        let label = Text("Bestes Angebot")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        return ViewThatFits(in: .horizontal) {
            label.background(Color(.accentFill), in: .capsule)
            label.background(Color(.accentFill), in: .rect(cornerRadius: 8))
        }
    }

    /// "2.000 Münzen" on one line where it fits, otherwise "Münzen" under the number: squeezed into one line, SwiftUI
    /// broke the number itself ("2.00" / "0"). The line counts as fitting only if the biggest pack's line would, so the
    /// three cards always look alike.
    private var coinCount: some View {
        ViewThatFits(in: .horizontal) {
            ZStack(alignment: .leading) {
                countLine(CoinPack.all.map(\.coins).max() ?? pack.coins)
                    .hidden()
                countLine(pack.coins)
            }
            VStack(alignment: .leading, spacing: 0) {
                coins(pack.coins)
                coinUnit
            }
        }
    }

    private func countLine(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            coins(count)
            coinUnit
        }
    }

    private func coins(_ count: Int) -> Text {
        Text(count, format: .number)
            .font(.title.bold())
            .monospacedDigit()
    }

    private var coinUnit: Text {
        Text("Münzen")
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    /// The App Store's localized price on the accent color, like the app's primary buttons. It keeps its one line.
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
        .fixedSize()
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
