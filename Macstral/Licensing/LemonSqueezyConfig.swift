import Foundation

// MARK: - LemonSqueezyConfig

/// Non-secret Lemon Squeezy identifiers and endpoints used by the licensing layer.
///
/// These values are safe to ship in the binary: the license activate/validate/deactivate
/// endpoints authenticate with the user's own license key, not with the store's secret API
/// key (which is never embedded). Fill the placeholders after creating the product in the
/// Lemon Squeezy dashboard (PLAN.md §3).
enum LemonSqueezyConfig {

    // MARK: Store / product identifiers (non-secret)

    /// Numeric store ID from Lemon Squeezy → Settings → Stores.
    static let storeID = "REPLACE_STORE_ID"
    /// Numeric product ID for "Macstral Pro".
    static let productID = "REPLACE_PRODUCT_ID"
    /// Numeric variant ID for the $30 single-payment variant with license keys enabled.
    static let variantID = "REPLACE_VARIANT_ID"

    // MARK: Pricing display

    /// Human-readable Pro price, shown in upsell copy.
    static let proPriceDisplay = "$30"

    /// How many Macs a single license may activate (Lemon Squeezy activation limit).
    static let activationInstanceLimit = 3

    // MARK: Endpoints

    /// Hosted checkout URL opened in the browser for the "Upgrade" button.
    /// Replace with the real Lemon Squeezy buy link once the product exists.
    static let checkoutURL = URL(string: "https://macstral.lemonsqueezy.com/buy/REPLACE_VARIANT_SLUG")!

    /// Base URL for the Lemon Squeezy license API.
    static let apiBaseURL = URL(string: "https://api.lemonsqueezy.com/v1")!

    static var activateURL: URL { apiBaseURL.appendingPathComponent("licenses/activate") }
    static var validateURL: URL { apiBaseURL.appendingPathComponent("licenses/validate") }
    static var deactivateURL: URL { apiBaseURL.appendingPathComponent("licenses/deactivate") }
}
