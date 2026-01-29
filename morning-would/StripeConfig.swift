import Foundation

enum StripeConfig {
    // MARK: - Stripe LIVE Key
    // Get from: https://dashboard.stripe.com/apikeys
    // ⚠️ Set this locally - do not commit real key to git
    static let publishableKey = "pk_live_51SFmmBJvjEmusMrWmyxxYVbOCdbGXGPP1abyBQx6de058XiwPgiZwZ1QfsBSnxlaH2aXC1XQtr3D71F3rT09wNIp00yWIHDvsH"

    /// Backend base URL
    static let backendURL = URL(string: "https://api.live-eos.com")!
}



