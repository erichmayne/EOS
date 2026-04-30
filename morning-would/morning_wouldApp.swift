//
//  morning_wouldApp.swift
//  morning-would
//
//  Created by Erich Mayne on 1/4/26.
//

import SwiftUI
import Combine
import CoreData
import StripePaymentSheet

// MARK: - Version comparison helper
private func isVersion(_ current: String, olderThan required: String) -> Bool {
    let c = current.split(separator: ".").compactMap { Int($0) }
    let r = required.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(c.count, r.count) {
        let cv = i < c.count ? c[i] : 0
        let rv = i < r.count ? r[i] : 0
        if cv < rv { return true }
        if cv > rv { return false }
    }
    return false
}

// MARK: - Force Update View
struct ForceUpdateView: View {
    let storeUrl: String
    private let goldColor = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image("RunMatchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)

            VStack(spacing: 12) {
                Text("Update Required")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)

                Text("A new version of RunMatch is available with important updates. Please update to continue.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                if let url = URL(string: storeUrl) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Update Now")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(goldColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") installed")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.gray.opacity(0.6))

            Spacer()
        }
        .background(Color.white)
        .ignoresSafeArea()
    }
}

// MARK: - Version Check Manager
final class VersionChecker: ObservableObject {
    @Published var requiresUpdate = false
    @Published var storeUrl = "https://apps.apple.com/us/app/runmatch/id6758569221"
    @Published var hasChecked = false

    func check() {
        guard let url = URL(string: "/app/config", relativeTo: StripeConfig.backendURL) else {
            hasChecked = true
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                defer { self.hasChecked = true }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let minVersion = json["minVersion"] as? String else {
                    return
                }

                if let url = json["storeUrl"] as? String, !url.isEmpty {
                    self.storeUrl = url
                }

                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
                self.requiresUpdate = isVersion(currentVersion, olderThan: minVersion)

                if self.requiresUpdate {
                    print("⚠️ Force update required: current \(currentVersion) < minimum \(minVersion)")
                }
            }
        }.resume()
    }
}

@main
struct EOSApp: App {
    let persistenceController = PersistenceController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isShowingSplash = true
    @StateObject private var versionChecker = VersionChecker()

    init() {
        STPAPIClient.shared.publishableKey = StripeConfig.publishableKey
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black], for: .normal)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if versionChecker.requiresUpdate {
                    ForceUpdateView(storeUrl: versionChecker.storeUrl)
                        .transition(.opacity)
                } else if hasCompletedOnboarding {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .preferredColorScheme(.dark)
                } else if !isShowingSplash {
                    OnboardingView()
                        .preferredColorScheme(.light)
                        .transition(.opacity)
                }

                if isShowingSplash && !versionChecker.requiresUpdate {
                    SplashViewWithLogo(isShowingSplash: $isShowingSplash)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isShowingSplash)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .animation(.easeInOut(duration: 0.3), value: versionChecker.requiresUpdate)
            .onAppear {
                versionChecker.check()

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
