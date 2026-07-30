import Foundation
import StoreKit

/// The four tip tiers, in ascending price order.
///
/// These are **non-consumable** products rather than consumables. Apple's
/// guideline 3.1.1 requires a restore mechanism for anything restorable, and a
/// consumable tip could never be restored onto a second device — so a user who
/// tipped on their phone would lose the cosmetics on their Mac. Non-consumables
/// give us `Transaction.currentEntitlements` for free across the whole account.
///
/// Every tier unlocks exactly the same thing. The higher tiers exist only so
/// someone who wants to give more can, not to sell a bigger feature set.
enum TipTier: String, CaseIterable, Identifiable, Sendable {
    case coffee = "com.msdrigg.roam.tip.coffee"
    case latte = "com.msdrigg.roam.tip.latte"
    case lunch = "com.msdrigg.roam.tip.lunch"
    case dinner = "com.msdrigg.roam.tip.dinner"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .coffee: "☕️"
        case .latte: "🥛"
        case .lunch: "🥪"
        case .dinner: "🍝"
        }
    }

    var displayName: String {
        switch self {
        case .coffee: String(localized: "Black Coffee", comment: "Name of the smallest tip tier")
        case .latte: String(localized: "Latte", comment: "Name of the second tip tier")
        case .lunch: String(localized: "Lunch", comment: "Name of the third tip tier")
        case .dinner: String(localized: "Dinner", comment: "Name of the largest tip tier")
        }
    }

    /// Shown while StoreKit is still resolving real localized prices, so the
    /// tier list doesn't flash empty. Never used to complete a purchase — the
    /// amount charged always comes from the `Product` StoreKit returns.
    ///
    /// Formatted to match `Product.displayPrice` ("$3.00", not "$3") so the
    /// fallback is visually identical to the resolved state, and kept in sync
    /// with the App Store Connect prices by hand.
    var placeholderPrice: String {
        switch self {
        case .coffee: "$3.00"
        case .latte: "$5.00"
        case .lunch: "$10.00"
        case .dinner: "$20.00"
        }
    }
}

@Observable @MainActor
final class TipStore {
    static let shared = TipStore()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts: Bool = false
    private(set) var isRestoring: Bool = false

    /// Surfaced to the UI via `.alertingError`. Cleared when the user dismisses.
    var purchaseError: Error?

    /// True once the developer unlock code has been redeemed on this device.
    ///
    /// Stored rather than read from `UserDefaults` on demand (the way
    /// `isGrandfathered` is) so `@Observable` sees the change and every locked
    /// row flips the instant the code lands, without a view reload.
    private(set) var isDeveloperUnlocked: Bool

    private var updateListener: Task<Void, Never>?

    private init() {
        isDeveloperUnlocked = UserDefaults.standard.bool(forKey: UserDefaultKeys.developerCosmeticsUnlock)

        // Grandfathering has to run before the first `hasTipped` read, otherwise
        // an existing user could see the paywall for a single frame on launch.
        Self.grandfatherExistingUsersIfNeeded()

        updateListener = Task { [weak self] in
            // `Transaction.updates` carries purchases made outside this process:
            // Ask to Buy approvals, purchases on another device, and App Store
            // refunds/revocations. Without it a family-approved tip would never
            // unlock until the next cold launch.
            for await update in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    // No `deinit` cancelling `updateListener`: this is a lifetime-of-app
    // singleton, and touching a `@MainActor` stored property from the
    // nonisolated `deinit` is rejected under strict concurrency anyway.

    // MARK: - Entitlement

    /// True when the cosmetic extras (accent color, alternate icons) are unlocked.
    var hasTipped: Bool {
        !purchasedProductIDs.isEmpty || isGrandfathered || isDeveloperUnlocked
    }

    /// Users who already had a custom accent color before it became a paid
    /// feature keep it forever. Reading the flag directly (rather than caching
    /// it) keeps this correct if the defaults are restored from a backup.
    var isGrandfathered: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultKeys.cosmeticsGrandfathered)
    }

    /// Runs once per install. If the user had already set a custom accent color
    /// back when it was free, grant the unlock permanently — taking away
    /// something someone was actively using is not a trade worth making.
    private static func grandfatherExistingUsersIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: UserDefaultKeys.didEvaluateCosmeticsGrandfathering) else {
            return
        }
        defaults.set(true, forKey: UserDefaultKeys.didEvaluateCosmeticsGrandfathering)

        if defaults.object(forKey: UserDefaultKeys.customAccentColor) != nil {
            Log.data.notice("Grandfathering cosmetics for pre-existing custom accent color")
            defaults.set(true, forKey: UserDefaultKeys.cosmeticsGrandfathered)
        }
    }

    // MARK: - Developer unlock

    /// Sent *from* support into a user's chat to grant the tip extras without a
    /// purchase — a thank-you the developer can hand out directly. Versioned:
    /// minting `_v2` later retires this one instead of having to honour every
    /// code ever shipped.
    static let developerUnlockCode = ":auto_unlock_iap_v1:"

    /// Trimmed and case-folded, so the code still lands when it picks up a
    /// stray newline or capitalization on its way through the support tooling.
    static func isDeveloperUnlockCode(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == developerUnlockCode
    }

    /// Grants the extras permanently on this device. Deliberately local: this
    /// is not an entitlement, so it never touches StoreKit and is never synced.
    ///
    /// Returns true only on the call that actually flips the unlock, so callers
    /// can celebrate once instead of every time the chat is reopened.
    @discardableResult
    func redeemDeveloperUnlock() -> Bool {
        guard !isDeveloperUnlocked else { return false }

        isDeveloperUnlocked = true
        UserDefaults.standard.set(true, forKey: UserDefaultKeys.developerCosmeticsUnlock)
        Log.userInteraction.notice("Developer unlock code redeemed")
        return true
    }

    // MARK: - Loading

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: TipTier.allCases.map(\.rawValue))
            // StoreKit returns products in an unspecified order; sort by price so
            // the tier list always reads cheapest-first.
            products = loaded.sorted { $0.price < $1.price }
            Log.backend.notice("Loaded \(self.products.count, privacy: .public) tip products")
        } catch {
            Log.backend.error("Failed loading tip products \(error, privacy: .public)")
        }

        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement else { continue }
            // `revocationDate` is set when Apple refunds a purchase; treat a
            // refunded tip as no longer entitling the cosmetics.
            guard transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
        Log.backend.notice("Tip entitlements refreshed count=\(owned.count, privacy: .public)")
    }

    func product(for tier: TipTier) -> Product? {
        products.first { $0.id == tier.rawValue }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    Log.backend.error("Tip purchase failed StoreKit verification")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                Log.userInteraction.notice("Tip purchased \(product.id, privacy: .public)")

            case .userCancelled:
                Log.userInteraction.notice("Tip purchase cancelled by user")

            case .pending:
                // Ask to Buy / SCA. The unlock arrives later via
                // `Transaction.updates`, so there is nothing to do here.
                Log.userInteraction.notice("Tip purchase pending approval")

            @unknown default:
                break
            }
        } catch {
            Log.backend.error("Tip purchase failed \(error, privacy: .public)")
            purchaseError = error
        }
    }

    /// Required by guideline 3.1.1 — a missing restore path is one of the more
    /// common causes of rejection for apps selling non-consumables.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            Log.userInteraction.notice("Restored purchases")
        } catch {
            Log.backend.error("Restoring purchases failed \(error, privacy: .public)")
            purchaseError = error
        }
    }
}
