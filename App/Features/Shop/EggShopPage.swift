import EggscapeCore
import SwiftUI

/// The shop's egg page: every egg but the classic one is locked until the player unlocks it with coins.
struct EggShopPage: View {
    @Environment(AppServices.self) private var services
    /// A locked egg the player can afford, waiting for the confirmation.
    @State private var pendingSkin: EggSkin?
    /// The coins missing for a locked egg that costs more than the balance.
    @State private var coinsShort: Int?
    @State private var unlockFailed = false
    /// Counts unlocks, to trigger the success haptic.
    @State private var unlocks = 0

    var body: some View {
        let unlocked = SkinCatalog.all.filter { services.wallet.owns($0) }.count
        let haptics = services.settings.isHapticsOn
        VStack(alignment: .leading, spacing: 14) {
            Text("\(unlocked) von \(SkinCatalog.all.count) Eiern freigeschaltet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(SkinCatalog.all) { skin in
                    Button {
                        select(skin)
                    } label: {
                        SkinCard(skin: skin, status: status(of: skin))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shop.skin.\(skin.id)")
                    // On the card, not the 2,000 pt grid: iOS 26 opens the dialog from the view it is attached to.
                    .confirmationDialog(
                        Text("Ei freischalten?"),
                        isPresented: Binding(get: { pendingSkin?.id == skin.id }, set: {
                            if !$0 {
                                pendingSkin = nil
                            }
                        }),
                        titleVisibility: .visible
                    ) {
                        Button {
                            unlock(skin)
                        } label: {
                            Text("\(Text(SkinNames.name(for: skin))) für \(skin.price) Münzen freischalten")
                        }
                        .accessibilityIdentifier("shop.confirmUnlock")
                        Button("Abbrechen", role: .cancel) {}
                    }
                }
            }
        }
        .sensoryFeedback(trigger: unlocks) { _, _ in
            haptics ? .success : nil
        }
        .alert(
            Text("Nicht genug Münzen"),
            isPresented: Binding(get: { coinsShort != nil }, set: {
                if !$0 {
                    coinsShort = nil
                }
            }),
            presenting: coinsShort
        ) { _ in
            Button("Münzen kaufen", action: services.navigation.showCoinShop)
                .accessibilityIdentifier("shop.buyCoins")
            Button("Abbrechen", role: .cancel) {}
        } message: { missing in
            Text("Dir fehlen noch \(missing) Münzen. Lauf ein paar Runden oder hol dir ein Münzpaket.")
        }
        .alert(Text("Kauf nicht möglich"), isPresented: $unlockFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte versuche es noch einmal.")
        }
    }

    private func status(of skin: EggSkin) -> SkinCard.Status {
        let wallet = services.wallet
        if wallet.equippedSkin.id == skin.id {
            return .equipped
        }
        if wallet.owns(skin) {
            return .owned
        }
        return .locked(missing: wallet.coinsMissing(for: skin))
    }

    /// Owned eggs are put on right away; a locked one asks first, or offers coins if the balance is too low.
    private func select(_ skin: EggSkin) {
        let wallet = services.wallet
        let missing = wallet.coinsMissing(for: skin)
        if wallet.owns(skin) {
            try? wallet.equip(skin)
            services.sounds.play(.plop)
        } else if missing > 0 {
            coinsShort = missing
        } else {
            pendingSkin = skin
        }
    }

    private func unlock(_ skin: EggSkin) {
        do throws(WalletError) {
            try services.wallet.purchase(skin)
            try services.wallet.equip(skin)
            services.sounds.play(.coin)
            unlocks += 1
        } catch let .insufficientCoins(missing) {
            coinsShort = missing
        } catch {
            unlockFailed = true
        }
    }
}

/// One egg in the grid: a padlock in front of it until it is unlocked, and its price in coins.
private struct SkinCard: View {
    let skin: EggSkin
    let status: Status

    enum Status: Equatable {
        case equipped
        case owned
        /// Not unlocked yet and `missing` coins short of the price, 0 if the balance covers it.
        case locked(missing: Int)
    }

    var body: some View {
        VStack(spacing: 10) {
            // A locked egg is faded behind its padlock, a little less once the balance covers its price.
            EggThumbnail(appearance: skin.appearance, width: 84)
                .saturation(lockedEggSaturation)
                .opacity(lockedEggOpacity)
                .frame(height: 124)
                .overlay {
                    if case let .locked(missing) = status {
                        LockBadge(canUnlock: missing == 0)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
            Text(SkinNames.name(for: skin))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            statusLine
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(status == .equipped ? Color.accentColor : .clear, lineWidth: 3)
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
        .animation(.snappy, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SkinNames.name(for: skin)))
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint(accessibilityAction)
        .accessibilityAddTraits(status == .equipped ? [.isButton, .isSelected] : .isButton)
    }

    private var lockedEggSaturation: Double {
        switch status {
        case .equipped, .owned: 1
        case .locked(missing: 0): 0.6
        case .locked: 0.2
        }
    }

    private var lockedEggOpacity: Double {
        switch status {
        case .equipped, .owned: 1
        case .locked(missing: 0): 0.85
        case .locked: 0.6
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .equipped:
            Label("Ausgewählt", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        case .owned:
            Text("Auswählen")
                .foregroundStyle(.secondary)
        case let .locked(missing):
            // The price stands out in the accent color once the balance covers it.
            HStack(spacing: 4) {
                CoinIcon(size: 16)
                    .opacity(missing == 0 ? 1 : 0.5)
                Text(skin.price, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(missing == 0 ? Color.accentColor : Color.secondary)
            }
        }
    }

    private var accessibilityStatus: Text {
        switch status {
        case .equipped, .owned:
            Text("Freigeschaltet")
        case .locked:
            Text("Gesperrt, \(skin.price) Münzen")
        }
    }

    /// What a double tap does, or why it cannot unlock the egg yet.
    private var accessibilityAction: Text {
        switch status {
        case .equipped:
            Text(verbatim: "")
        case .owned:
            Text("Wählt dieses Ei aus.")
        case .locked(missing: 0):
            Text("Schaltet das Ei frei.")
        case let .locked(missing):
            Text("Dir fehlen noch \(missing) Münzen. Lauf ein paar Runden oder hol dir ein Münzpaket.")
        }
    }
}

/// The padlock in front of a locked egg: white on the accent color once the balance covers the price, white on a dark
/// disc while the egg is still out of reach.
private struct LockBadge: View {
    let canUnlock: Bool

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(canUnlock ? Color(.accentFill) : Color.black.opacity(0.55), in: .circle)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}
