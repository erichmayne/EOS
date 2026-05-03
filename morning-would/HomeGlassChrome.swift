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

// MARK: - Social Placeholder

struct SocialView: View {
    @Environment(\.dismiss) private var dismiss
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(gold)
                Text("Social")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Friends, leaderboards, and shared wins are coming soon.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Spacer()
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
