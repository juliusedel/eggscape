@testable import Eggscape
import EggscapeCore
import Foundation
import StoreKit
import StoreKitTest
import Testing

/// Finds the test bundle, which carries a copy of `StoreKit/Eggscape.storekit`.
private final class BundleToken {}

/// The coin packs against `StoreKit/Eggscape.storekit`, the configuration the Run scheme uses, in a local StoreKit test
/// session: no App Store, no Apple account, no dialogs. Serialized, because StoreKit has one test environment.
@MainActor
@Suite(.serialized)
struct StoreServiceTests {
    private func makeSession() throws -> SKTestSession {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Eggscape", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func makeWallet() -> WalletStore {
        let suite = "eggscape.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WalletStore(defaults: defaults)
    }

    @Test func theConfigurationSellsEveryCoinPackAsAConsumable() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = StoreService(productIDs: CoinPack.productIDs) { _, _ in }

        await store.loadProducts()
        #expect(!store.loadFailed)
        // Cheapest first, which is the order of the packs.
        #expect(store.products.map(\.id) == CoinPack.productIDs)
        #expect(store.products.allSatisfy { $0.type == .consumable })
    }

    @Test func buyingAPackCreditsItsCoinsOnce() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let wallet = makeWallet()
        var credited: [UInt64] = []
        let store = StoreService(productIDs: CoinPack.productIDs) { transactionID, productID in
            credited.append(transactionID)
            wallet.creditPurchase(transactionID: transactionID, productID: productID)
        }
        await store.loadProducts()
        let small = try #require(store.products.first { $0.id == CoinPack.small.productID })

        await store.purchase(small)
        #expect(store.purchaseState == .idle)
        #expect(credited.count == 1)
        #expect(wallet.coins == CoinPack.small.coins)

        // StoreKit may hand the same transaction over again, e.g. after a crash before it was finished: no new coins.
        let transactionID = try #require(credited.first)
        wallet.creditPurchase(transactionID: transactionID, productID: small.id)
        #expect(wallet.coins == CoinPack.small.coins)
        // It was finished, so StoreKit does not deliver it again at the next launch.
        var unfinished = 0
        for await _ in Transaction.unfinished {
            unfinished += 1
        }
        #expect(unfinished == 0)
    }
}
