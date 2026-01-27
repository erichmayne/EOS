import Foundation

enum StripeConfig {
    /// Stripe publishable key (LIVE mode)
    // Set locally only. Do not commit real keys.
    static let publishableKey = "YOUR_STRIPE_PUBLISHABLE_KEY"

    /// Backend base URL hosting the create-payment-intent endpoint (HTTPS via nginx/certbot)
    static let backendURL = URL(string: "https://api.live-eos.com")!
}



