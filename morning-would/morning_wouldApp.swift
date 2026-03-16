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
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black], for: .normal)
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
