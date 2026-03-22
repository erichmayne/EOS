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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
                if hasCompletedOnboarding {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .preferredColorScheme(.dark)
                } else if !isShowingSplash {
                    OnboardingView()
                        .preferredColorScheme(.light)
                        .transition(.opacity)
                }

                if isShowingSplash {
                    SplashViewWithLogo(isShowingSplash: $isShowingSplash)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isShowingSplash)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .onAppear {
                if !hasCompletedOnboarding {
                    let d = UserDefaults.standard
                    let existingUser = d.bool(forKey: "isSignedIn")
                        || d.bool(forKey: "pushupsEnabled")
                        || d.bool(forKey: "runEnabled")
                        || !(d.string(forKey: "userId") ?? "").isEmpty
                    if existingUser { hasCompletedOnboarding = true }
                }
            }
            .onOpenURL { url in
                let stripeHandled = StripeAPI.handleURLCallback(with: url)
                if stripeHandled {
                    print("✅ Stripe handled URL: \(url)")
                }
            }
        }
    }
}
