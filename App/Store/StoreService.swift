import Observation
import os
import StoreKit

/// Sells the coin packs (consumable in-app purchases) with StoreKit 2. Coins are credited through `credit`, which
/// must credit every transaction id at most once; the transaction is finished afterwards either way.
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

    func purchase(_ product: Product) async {
        purchaseState = .purchasing(productID: product.id)
        do {
            switch try await product.purchase() {
            case let .success(verification):
                await process(verification)
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription)")
            purchaseState = .failed(error.localizedDescription)
        }
    }

    private func process(_ result: VerificationResult<Transaction>) async {
        // Only content from transactions signed by the App Store is granted.
        guard case let .verified(transaction) = result else {
            logger.error("Ignoring an unverified transaction")
            return
        }
        if transaction.revocationDate == nil, transaction.productType == .consumable {
            credit(transaction.id, transaction.productID)
        }
        await transaction.finish()
    }
}
