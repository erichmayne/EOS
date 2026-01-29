import Foundation

enum StripeConfig {
    // MARK: - Stripe LIVE Key
    // Get from: https://dashboard.stripe.com/apikeys
    // ⚠️ Set this locally - do not commit real key to git
    static let publishableKey = "pk_live_YOUR_KEY_HERE"

    /// Backend base URL
    static let backendURL = URL(string: "https://api.live-eos.com")!
}



