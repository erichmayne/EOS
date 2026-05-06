// HomeGlassChrome.swift
// Shared visual helpers for the redesigned home screen.

import SwiftUI

// MARK: - Glass Background

/// Subtle warm-tinted backdrop with two faint blurred orbs (gold + warm cream).
/// Pure colors + blur — no Material APIs, so no iOS version concerns.
struct HomeGlassBackground: View {
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    var body: some View {
        ZStack {
            Color(white: 0.965)

            Circle()
                .fill(gold.opacity(0.12))
                .frame(width: 500, height: 500)
                .blur(radius: 120)
                .offset(x: 160, y: -280)

            Circle()
                .fill(Color(red: 1.0, green: 0.88, blue: 0.7).opacity(0.12))
                .frame(width: 600, height: 600)
                .blur(radius: 130)
                .offset(x: -200, y: 340)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Starter Bonus Celebration Sheet

/// Mid-size centered sheet that fires (a) when the user wins their seeded
/// starter comp, and (b) when their locked $10 unlocks because they crossed
/// $50 in lifetime comp earnings. Uses the win-card aesthetic — dark
/// gradient + white facet polygons + vertical gold accent on the left edge.
struct StarterBonusCelebrationSheet: View {
    enum Mode { case starterWin, unlock }

    let mode: Mode
    @Binding var isPresented: Bool
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    private var eyebrow: String {
        switch mode {
        case .starterWin: return "FIRST WIN"
        case .unlock:     return "BONUS UNLOCKED"
        }
    }
    private var headline: String {
        switch mode {
        case .starterWin: return "You won."
        case .unlock:     return "It's yours."
        }
    }
    private var amount: String {
        switch mode {
        case .starterWin: return "$10"
        case .unlock:     return "+$10"
        }
    }
    private var bodyLine1: String {
        switch mode {
        case .starterWin: return "Win $50 in matches and we'll"
        case .unlock:     return "You hit $50 in winnings. Your starter $10"
        }
    }
    private var bodyLine2: String {
        switch mode {
        case .starterWin: return "automatically add your $10 to your balance."
        case .unlock:     return "just landed in your wallet — withdraw any time."
        }
    }
    private var primaryLabel: String {
        switch mode {
        case .starterWin: return "Start a Match"
        case .unlock:     return "View Wallet"
        }
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // Mid-size card — fixed height, centered
            sheet
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
        }
    }

    private var sheet: some View {
        ZStack {
            // Dark gradient base — same as win-card export
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.09),
                    Color(red: 0.02, green: 0.02, blue: 0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // White facet polygons (very low opacity)
            GeometryReader { geo in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height * 0.55))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.55, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.05))

                Path { p in
                    p.move(to: CGPoint(x: geo.size.width, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.45))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.45, y: 0))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.05))

                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height * 0.75))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.30, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.03))
            }

            // Vertical gold accent strip on the left
            HStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0.3), gold.opacity(0.8), gold.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                Spacer()
            }

            // Content stack — centered
            VStack(spacing: 14) {
                // Top: close X, top-right
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }

                // Run/Match wordmark
                HStack(spacing: 6) {
                    Image("RunMatchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    HStack(spacing: 0) {
                        Text("RUN").foregroundStyle(gold)
                        Text("MATCH").foregroundStyle(Color.white)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(3)
                }

                // Eyebrow
                Text(eyebrow)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(gold)
                    .padding(.top, 4)

                // Headline (italic gold serif)
                Text(headline)
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(gold)

                // Amount
                Text(amount)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                // Body — two centered lines
                VStack(spacing: 4) {
                    Text(bodyLine1)
                    Text(bodyLine2)
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.top, 4)

                // CTA — single gold button, white text
                Button(action: {
                    onPrimary()
                    isPresented = false
                }) {
                    Text(primaryLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(gold))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Pending Comps List

/// Sheet that shows only the user's pending (not-yet-started) competitions.
/// Each row is tappable and takes the user straight to that comp's lobby.
struct PendingCompsListView: View {
    let comps: [[String: Any]]
    let onSelectComp: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(comps.enumerated()), id: \.offset) { _, comp in
                        pendingCompCard(comp)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Waiting to Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(gold)
                }
            }
        }
    }

    private func pendingCompCard(_ comp: [String: Any]) -> some View {
        let name = comp["name"] as? String ?? "Competition"
        let scoring = comp["scoringType"] as? String ?? ""
        let objType = comp["objectiveType"] as? String ?? "run"
        let count = comp["participantCount"] as? Int ?? 0
        let buyIn = comp["buyInAmount"] as? Double ?? 0
        let seeded = comp["seededAmount"] as? Double ?? 0
        let pool = buyIn * Double(count) + seeded
        let isStarter = comp["isStarter"] as? Bool ?? false
        let compId = comp["id"] as? String ?? ""
        let target = comp["targetValue"] as? Double ?? 0
        let runTarget = comp["runTarget"] as? Double ?? 0
        let duration = comp["durationDays"] as? Int ?? 0
        let isRace = comp["isRace"] as? Bool ?? (scoring == "race")
        let code = comp["inviteCode"] as? String ?? ""

        let goalText: String = {
            if isRace && runTarget > 0 { return "Race to \(String(format: "%.1f", runTarget)) mi" }
            if objType == "run" && target > 0 { return "\(String(format: "%.1f", target)) mi/day" }
            if target > 0 { return "\(Int(target)) reps/day" }
            return scoring.capitalized
        }()

        return Button(action: { onSelectComp(compId) }) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    // Top: name + pills
                    HStack(spacing: 6) {
                        Image(systemName: objType == "run" ? "figure.run" : "flame.fill")
                            .font(.title3)
                            .foregroundStyle(gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.black)
                                .lineLimit(1)
                            Text(goalText)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.5))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if isStarter {
                                Text("STARTER")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(gold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(gold.opacity(0.12)))
                            }
                            Text(scoring.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(gold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(gold.opacity(0.12)))
                        }
                    }

                    // Stats row
                    HStack(spacing: 14) {
                        Label("\(count) joined", systemImage: "person.2.fill")
                        if duration > 0 {
                            Label("\(duration) days", systemImage: "calendar")
                        } else if isRace {
                            Label("Race", systemImage: "flag.fill")
                        }
                    }
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.45))

                    // Prize / buy-in row
                    HStack(spacing: 8) {
                        if seeded > 0 && buyIn == 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "gift.fill").font(.caption2)
                                Text("Free Entry · $\(Int(seeded)) prize")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                            }
                            .foregroundStyle(Color.green)
                        } else if buyIn > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.circle.fill").font(.caption2)
                                Text("$\(Int(buyIn)) buy-in")
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                            }
                            .foregroundStyle(Color.black.opacity(0.6))
                            if pool > 0 {
                                Text("· $\(Int(pool)) pot")
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(gold)
                            }
                        }
                        Spacer()
                        // Invite code
                        Text(code)
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }
                }
                .padding(16)

                // Bottom: "Tap to open lobby" + chevron
                Divider()
                HStack {
                    Text("Open Lobby")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(gold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(gold.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Social Placeholder

struct SocialView: View {
    @Environment(\.dismiss) private var dismiss
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(gold)
                    Text("Social")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Friends, leaderboards, public matches, personal challenges, and shared wins are coming soon.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                    Text("Coming Soon")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(gold)
                        .padding(.top, 8)
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(gold)
                }
            }
        }
    }
}
