import SwiftUI

// MARK: - Tutorial Step

struct TutorialStep {
    let targetId: String?
    let title: String
    let message: String
    let icon: String
}

let appTutorialSteps: [TutorialStep] = [
    TutorialStep(targetId: "starter-comp",
                 title: "First one's on us.",
                 message: "Run 1 mile. Win $10. Your starter match is already live.",
                 icon: "gift.fill"),
    TutorialStep(targetId: "compete-button",
                 title: "Start a match or join one.",
                 message: "Create a match with friends, join with a code, or browse past results.",
                 icon: "trophy.fill"),
    TutorialStep(targetId: "page-dots",
                 title: "Swipe for your personal daily goals.",
                 message: "Competitions live here. Swipe right to see your daily run goal and streak.",
                 icon: "arrow.left.and.right"),
    TutorialStep(targetId: "strava-badge",
                 title: "Runs track automatically.",
                 message: "Link Strava and every GPS run counts toward your goals and matches. All runs must be started and stopped on Strava to count.",
                 icon: "figure.run"),
    TutorialStep(targetId: "profile-button",
                 title: "Wallet & profile.",
                 message: "Add funds, connect Strava, manage stakes, and withdraw winnings.",
                 icon: "person.circle"),
]

// MARK: - Preference Key for Frame Capture

struct TutorialFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tutorialTarget(_ id: String) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(key: TutorialFrameKey.self, value: [id: geo.frame(in: .global)])
            }
        )
    }
}

// MARK: - Spotlight Cutout Shape

struct SpotlightCutout: Shape {
    var targetRect: CGRect
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 8

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(targetRect.origin.x, targetRect.origin.y),
                AnimatablePair(targetRect.size.width, targetRect.size.height)
            )
        }
        set {
            targetRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let spotlight = targetRect.insetBy(dx: -padding, dy: -padding)
        path.addRoundedRect(in: spotlight, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

// MARK: - Tutorial Overlay

struct TutorialOverlay: View {
    @Binding var currentStep: Int
    @Binding var isActive: Bool
    let frames: [String: CGRect]
    let steps: [TutorialStep]
    var onComplete: () -> Void

    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    private var step: TutorialStep {
        steps[min(currentStep, steps.count - 1)]
    }

    private var effectiveTargetRect: CGRect {
        if let id = step.targetId, let frame = frames[id] {
            return frame
        }
        let cx = UIScreen.main.bounds.midX
        let cy = UIScreen.main.bounds.midY
        return CGRect(x: cx, y: cy, width: 0, height: 0)
    }

    private var showCardBelow: Bool {
        guard step.targetId != nil else { return false }
        return effectiveTargetRect.midY < UIScreen.main.bounds.height * 0.45
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            SpotlightCutout(targetRect: effectiveTargetRect)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Position the tooltip card dynamically so it doesn't overlap
            // the spotlighted element. If the target is in the top half,
            // card goes below; if bottom half, card goes above.
            VStack(spacing: 0) {
                if showCardBelow {
                    // Push card down past the spotlight
                    Spacer().frame(minHeight: max(20, effectiveTargetRect.maxY + 16))
                    tooltipCard
                    Spacer(minLength: 20)
                } else if step.targetId != nil {
                    // Push card up above the spotlight
                    Spacer(minLength: 20)
                    tooltipCard
                    Spacer().frame(minHeight: max(20, UIScreen.main.bounds.height - effectiveTargetRect.minY + 16))
                } else {
                    // No target — center
                    Spacer()
                    tooltipCard
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentStep)
    }

    private var tooltipCard: some View {
        VStack(spacing: 10) {
            // Icon + step dots
            HStack {
                Image(systemName: step.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(gold)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentStep ? gold : Color.black.opacity(0.15))
                            .frame(width: i == currentStep ? 16 : 6, height: 5)
                    }
                }
            }

            // Title
            Text(step.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Message
            Text(step.message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Buttons
            HStack(spacing: 12) {
                Button("Skip") {
                    withAnimation(.easeOut(duration: 0.25)) { isActive = false }
                    onComplete()
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.35))

                Spacer()

                Button(action: advance) {
                    HStack(spacing: 5) {
                        Text(currentStep == steps.count - 1 ? "Let's Go" : "Next")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        if currentStep < steps.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(gold))
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(gold.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: gold.opacity(0.25), radius: 20, y: 6)
        .padding(.horizontal, 32)
    }

    private func advance() {
        if currentStep >= steps.count - 1 {
            withAnimation(.easeOut(duration: 0.25)) { isActive = false }
            onComplete()
        } else {
            currentStep += 1
        }
    }
}
