import Observation
import os
import StoreKit

/// Sells the coin packs (consumable in-app purchases) with StoreKit 2. Coins are credited through `credit`, which
/// must credit every transaction id at most once; the transaction is finished afterwards. Transactions that are not
/// verified, or are for a pack this build does not sell, stay unfinished, so StoreKit delivers them again later.
@MainActor
@Observable
final class StoreService {
    enum PurchaseState: Equatable {
        case idle
        case purchasing(productID: String)
        /// Waiting for approval, e.g. "Ask to Buy".
        case pending
        case failed(String)
    }

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    var purchaseState = PurchaseState.idle

    @ObservationIgnored private let productIDs: [String]
    @ObservationIgnored private let credit: (_ transactionID: UInt64, _ productID: String) -> Void
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "store")

    init(productIDs: [String], credit: @escaping (_ transactionID: UInt64, _ productID: String) -> Void) {
        self.productIDs = productIDs
        self.credit = credit
    }

    /// Picks up purchases that completed outside the purchase flow (Ask to Buy, interrupted purchases). Call once
    /// at launch.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.process(result)
            }
        }
        Task { [weak self] in
            for await result in Transaction.unfinished {
                await self?.process(result)
            }
        }
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: productIDs)
            products = loaded.sorted { $0.price < $1.price }
            loadFailed = products.isEmpty
        } catch {
            logger.error("Loading products failed: \(error.localizedDescription)")
            loadFailed = true
        }
    }

    /// Buys `product` with `buy` and credits it. The coin shop buys through SwiftUI's `PurchaseAction`
    /// (`CoinPackCard`), as Apple advises for SwiftUI apps: it shows the App Store's sheet over the scene of the button
    /// that was tapped, while `Product.purchase()` has no scene to go by. The unit tests buy with `Product.purchase()`
    /// in a StoreKitTest session, which needs no sheet.
    func purchase(_ product: Product, with buy: @MainActor (Product) async throws -> Product.PurchaseResult) async {
        purchaseState = .purchasing(productID: product.id)
        do {
            let result = try await buy(product)
            await handle(result)
        } catch StoreKitError.userCancelled {
            purchaseState = .idle
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription)")
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// The App Store's answer to a purchase.
    private func handle(_ result: Product.PurchaseResult) async {
        switch result {
        case let .success(.verified(transaction)):
            await deliver(transaction)
            purchaseState = .idle
        case .success(.unverified):
            // Nothing is credited and the transaction stays unfinished, but the player may have paid: say so.
            logger.error("Ignoring an unverified purchase")
            purchaseState = .failed(String(localized: "Der Kauf konnte nicht bestätigt werden."))
        case .pending:
            purchaseState = .pending
        case .userCancelled:
            purchaseState = .idle
        @unknown default:
            purchaseState = .idle
        }
    }

    private func process(_ result: VerificationResult<Transaction>) async {
        // Only content from transactions signed by the App Store is granted.
        guard case let .verified(transaction) = result else {
            logger.error("Ignoring an unverified transaction")
            return
        }
        await deliver(transaction)
    }

    private func deliver(_ transaction: Transaction) async {
        // A pack added in a later version (bought with an offer code, or approved via Ask to Buy before updating) is
        // credited by that version.
        guard productIDs.contains(transaction.productID) else {
            logger.error("Leaving the transaction for the unknown product \(transaction.productID) unfinished")
            return
        }
        if transaction.revocationDate == nil, transaction.productType == .consumable {
            credit(transaction.id, transaction.productID)
        }
        await transaction.finish()
    }
}
