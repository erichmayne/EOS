import SwiftUI

// MARK: - Tutorial Step

struct TutorialStep {
    let targetId: String?
    let title: String
    let message: String
    let icon: String
}

let appTutorialSteps: [TutorialStep] = [
    TutorialStep(targetId: nil,
                 title: "Welcome to RunMatch!",
                 message: "Let us show you around. This quick tour walks you through everything you need.",
                 icon: "hand.wave.fill"),
    TutorialStep(targetId: "goals-card",
                 title: "Your Daily Progress",
                 message: "This card tracks your daily run. Green means you've hit your distance target for the day.",
                 icon: "target"),
    TutorialStep(targetId: "timer",
                 title: "Beat the Clock",
                 message: "Complete your run before the deadline. Miss it, and your stakes are on the line.",
                 icon: "clock"),
    TutorialStep(targetId: "objective-button",
                 title: "Configure Your Goals",
                 message: "Set your daily run distance, pick your schedule, and choose your deadline.",
                 icon: "gearshape"),
    TutorialStep(targetId: "profile-button",
                 title: "Your Profile",
                 message: "Add balance, connect Strava for run tracking, and set your payout stakes.",
                 icon: "person.circle"),
    TutorialStep(targetId: "compete-button",
                 title: "Challenge Friends",
                 message: "Create or join competitions with real money on the line. Winner takes the pot.",
                 icon: "trophy.fill"),
    TutorialStep(targetId: "strava-badge",
                 title: "Runs Track Automatically",
                 message: "Once Strava is linked, every GPS-tracked run on Strava you complete automatically counts toward your goals and competitions in RunMatch. No manual logging needed.",
                 icon: "figure.run"),
    TutorialStep(targetId: nil,
                 title: "You're All Set!",
                 message: "Time to crush your first goal. Good luck!",
                 icon: "star.fill"),
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
                .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if step.targetId != nil {
                VStack {
                    if showCardBelow {
                        Spacer()
                    }
                    tooltipCard
                    if !showCardBelow {
                        Spacer()
                    }
                }
                .padding(.vertical, 60)
            } else {
                tooltipCard
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentStep)
    }

    private var tooltipCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentStep ? gold : Color.white.opacity(0.25))
                        .frame(width: i == currentStep ? 16 : 6, height: 6)
                }
            }

            Image(systemName: step.icon)
                .font(.system(size: 32))
                .foregroundStyle(gold)
                .padding(.top, 4)

            Text(step.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(step.message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 24) {
                Button("Skip tour") {
                    withAnimation(.easeOut(duration: 0.25)) { isActive = false }
                    onComplete()
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))

                Button(action: advance) {
                    Text(currentStep == steps.count - 1 ? "Let's Go!" : "Next")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(gold))
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(gold.opacity(0.2), lineWidth: 1)
                )
        )
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
