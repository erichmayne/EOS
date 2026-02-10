//
//  morning_wouldApp.swift
//  morning-would
//
//  Created by Erich Mayne on 1/4/26.
//

import SwiftUI
import CoreData
import StripePaymentSheet

@main
struct EOSApp: App {
    let persistenceController = PersistenceController.shared
    @State private var isShowingSplash = true

    init() {
        STPAPIClient.shared.publishableKey = StripeConfig.publishableKey
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                
                // Splash screen overlay
                if isShowingSplash {
                    SplashViewWithLogo(isShowingSplash: $isShowingSplash)
                        .transition(.opacity)
                }
            }
            .onOpenURL { url in
                // Handle Stripe payment redirects
                let stripeHandled = StripeAPI.handleURLCallback(with: url)
                if stripeHandled {
                    print("✅ Stripe handled URL: \(url)")
                }
            }
        }
    }
}
