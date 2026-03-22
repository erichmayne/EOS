import SwiftUI
import StripePaymentSheet

// MARK: - Onboarding Flow (v2)

struct OnboardingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isSignedIn") private var isSignedIn = false
    @AppStorage("profileUsername") private var profileUsername = ""
    @AppStorage("profileEmail") private var profileEmail = ""
    @AppStorage("profilePhone") private var profilePhone = ""
    @AppStorage("profileCompleted") private var profileCompleted = false
    @AppStorage("userId") private var userId = ""
    @AppStorage("stravaConnected") private var stravaConnected = false
    @AppStorage("stravaAthleteName") private var stravaAthleteName = ""
    @AppStorage("profileCashHoldings") private var profileCashHoldings: Double = 0

    @State private var currentPage = 0
    @State private var navigateForward = true

    @State private var selectedObjective = ""
    @State private var fitnessLevel = ""
    @State private var obstacles: Set<String> = []
    @State private var morningStruggle = ""
    @State private var motivationDriver = ""
    @State private var hasFriends = ""
    @State private var competitiveness = ""
    @State private var pushupTarget = 25
    @State private var runTarget = 1.0
    @State private var deadlineHour = 18

    @State private var showCreateAccountSheet = false
    @State private var showSignInSheet = false
    @State private var accountAction = ""
    @State private var showCreateCompetition = false
    @State private var isCheckingStrava = false
    @State private var stravaJustLinked = false

    private let totalPages = 16
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))

    private var needsMorningHelp: Bool {
        morningStruggle == "every" || morningStruggle == "some"
    }

    private var wantsRun: Bool {
        selectedObjective == "run" || selectedObjective == "both"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 8)
                    .padding(.horizontal, 24)

                HStack {
                    if currentPage > 0 {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.black.opacity(0.6))
                                .frame(width: 44, height: 44)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 44)

                ZStack {
                    screenForPage(currentPage)
                        .id(currentPage)
                        .transition(.asymmetric(
                            insertion: .move(edge: navigateForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: navigateForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .clipped()

                if currentPage < totalPages - 1 {
                    continueButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                } else {
                    finalButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showCreateAccountSheet) {
            CreateAccountView(
                isSignedIn: $isSignedIn,
                profileUsername: $profileUsername,
                profileEmail: $profileEmail,
                profilePhone: $profilePhone,
                profileCompleted: $profileCompleted
            )
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(
                isSignedIn: $isSignedIn,
                profileUsername: $profileUsername,
                profileEmail: $profileEmail,
                profilePhone: $profilePhone,
                profileCompleted: $profileCompleted
            )
        }
        .sheet(isPresented: $showCreateCompetition, onDismiss: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasCompletedOnboarding = true
            }
        }) {
            CreateCompetitionView(onCreated: { })
        }
        .onChange(of: isSignedIn) { _, signedIn in
            guard signedIn else { return }
            if accountAction == "create" {
                writeObjectiveSettings()
                syncObjectivesToBackend()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && currentPage == 14 && !userId.isEmpty && !stravaConnected {
                checkStravaStatus()
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(gold)
                    .frame(width: geo.size.width * CGFloat(currentPage + 1) / CGFloat(totalPages), height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button(action: advancePage) {
            Text(currentPage == 0 ? "Get Started" : "Continue")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canContinue ? gold : Color.gray.opacity(0.3))
                )
        }
        .disabled(!canContinue)
        .animation(.easeInOut(duration: 0.2), value: canContinue)
    }

    private var finalButtons: some View {
        VStack(spacing: 14) {
            Button(action: handleCompetitionCTA) {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                    Text("Start Your First Competition")
                }
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(gold))
            }

            Button(action: finishOnboarding) {
                Text("Skip for now")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.gray)
            }
        }
    }

    // MARK: - Validation

    private var canContinue: Bool {
        switch currentPage {
        case 0: return true
        case 1: return !fitnessLevel.isEmpty
        case 2: return !selectedObjective.isEmpty
        case 3: return true
        case 4: return !obstacles.isEmpty
        case 5: return !morningStruggle.isEmpty
        case 6: return !motivationDriver.isEmpty
        case 7: return true
        case 8: return !hasFriends.isEmpty
        case 9: return !competitiveness.isEmpty
        case 10: return true
        case 11, 12: return true
        case 13: return isSignedIn
        case 14: return true
        default: return true
        }
    }

    // MARK: - Navigation

    private func advancePage() {
        guard canContinue, currentPage < totalPages - 1 else { return }
        navigateForward = true
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
    }

    private func goBack() {
        guard currentPage > 0 else { return }
        navigateForward = false
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage -= 1
        }
    }

    // MARK: - Completion

    private func writeObjectiveSettings() {
        let defaults = UserDefaults.standard
        let enablePushups = selectedObjective == "pushups" || selectedObjective == "both"
        let enableRun = selectedObjective == "run" || selectedObjective == "both"

        defaults.set(enablePushups, forKey: "pushupsEnabled")
        defaults.set(enablePushups, forKey: "pushupsIsSet")
        defaults.set(enableRun, forKey: "runEnabled")
        defaults.set(enableRun, forKey: "runIsSet")
        defaults.set(pushupTarget, forKey: "pushupObjective")
        defaults.set(runTarget, forKey: "runDistance")
        defaults.set("Daily", forKey: "scheduleType")
        defaults.set(true, forKey: "scheduleIsSet")

        let comps = DateComponents(hour: deadlineHour, minute: 0)
        if let date = Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) {
            defaults.set(date, forKey: "objectiveDeadline")
        }
    }

    private func syncObjectivesToBackend() {
        guard !userId.isEmpty else { return }

        let enablePushups = selectedObjective == "pushups" || selectedObjective == "both"
        let enableRun = selectedObjective == "run" || selectedObjective == "both"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let deadlineDate = Calendar.current.date(from: DateComponents(hour: deadlineHour, minute: 0)) ?? Date()

        let body: [String: Any] = [
            "pushups_enabled": enablePushups,
            "pushups_count": pushupTarget,
            "run_enabled": enableRun,
            "run_distance": runTarget,
            "objective_schedule": "daily",
            "objective_deadline": formatter.string(from: deadlineDate),
            "timezone": TimeZone.current.identifier
        ]

        guard let url = URL(string: "https://api.live-eos.com/objectives/settings/\(userId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                print("✅ Onboarding objectives synced to backend")
            }
        }.resume()
    }

    private func finishOnboarding() {
        if accountAction == "create" || !isSignedIn {
            writeObjectiveSettings()
        }
        hasCompletedOnboarding = true
    }

    private func handleCompetitionCTA() {
        showCreateCompetition = true
    }

    // MARK: - Strava

    private func connectStrava() {
        guard !userId.isEmpty else { return }
        if let url = URL(string: "https://api.live-eos.com/strava/connect/\(userId)") {
            UIApplication.shared.open(url)
        }
    }

    private func checkStravaStatus() {
        guard !userId.isEmpty else { return }
        guard let url = URL(string: "https://api.live-eos.com/strava/status/\(userId)") else { return }

        isCheckingStrava = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isCheckingStrava = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                let connected = json["connected"] as? Bool ?? false
                if connected && !stravaConnected {
                    stravaConnected = true
                    stravaAthleteName = json["athleteName"] as? String ?? ""
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        stravaJustLinked = true
                    }
                }
            }
        }.resume()
    }

    // MARK: - Page Router

    @ViewBuilder
    private func screenForPage(_ page: Int) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                switch page {
                case 0:  welcomeScreen
                case 1:  fitnessLevelScreen
                case 2:  objectiveTypeScreen
                case 3:  reaffirmation1
                case 4:  obstaclesScreen
                case 5:  morningScreen
                case 6:  motivationScreen
                case 7:  reaffirmation2
                case 8:  friendsScreen
                case 9:  competitivenessScreen
                case 10: reaffirmation3
                case 11: targetScreen
                case 12: deadlineScreen
                case 13: accountScreen
                case 14: stravaScreen
                case 15: finalScreen
                default: EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 0: Welcome

    private var welcomeScreen: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image("EOSLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text("Welcome to EOS")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [Color.black, gold], startPoint: .leading, endPoint: .trailing)
                )

            Text("Dawn of Better Habits")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(gold)

            VStack(spacing: 10) {
                welcomePoint(icon: "target", text: "Set daily fitness goals")
                welcomePoint(icon: "dollarsign.circle", text: "Put real stakes on them")
                welcomePoint(icon: "trophy.fill", text: "Compete with friends")
            }
            .padding(.top, 12)
        }
    }

    private func welcomePoint(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(gold)
                .frame(width: 28)
            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.black)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Screen 1: Fitness Level

    private var fitnessLevelScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "How would you describe your fitness level?", subtitle: "This helps us set the right starting point.")

            VStack(spacing: 12) {
                optionCard(title: "Just getting started", icon: "leaf", isSelected: fitnessLevel == "beginner") {
                    fitnessLevel = "beginner"; pushupTarget = 10; runTarget = 0.5
                }
                optionCard(title: "Somewhat active", icon: "figure.walk", isSelected: fitnessLevel == "somewhat") {
                    fitnessLevel = "somewhat"; pushupTarget = 25; runTarget = 1.0
                }
                optionCard(title: "Consistently active", icon: "figure.run", isSelected: fitnessLevel == "consistent") {
                    fitnessLevel = "consistent"; pushupTarget = 50; runTarget = 2.0
                }
                optionCard(title: "Athlete", icon: "bolt.fill", isSelected: fitnessLevel == "athlete") {
                    fitnessLevel = "athlete"; pushupTarget = 100; runTarget = 4.0
                }
            }
        }
    }

    // MARK: - Screen 2: Objective Type

    private var objectiveTypeScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "What do you want to work on?", subtitle: "You can always change this later.")

            VStack(spacing: 12) {
                optionCard(title: "Pushups", icon: "figure.strengthtraining.traditional", isSelected: selectedObjective == "pushups") {
                    selectedObjective = "pushups"
                }
                optionCard(title: "Running", icon: "figure.run", isSelected: selectedObjective == "run") {
                    selectedObjective = "run"
                }
                optionCard(title: "Both", icon: "flame.fill", isSelected: selectedObjective == "both") {
                    selectedObjective = "both"
                }
            }
        }
    }

    // MARK: - Screen 3: Reaffirmation 1

    private var reaffirmation1: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 20)

            Text("People with specific goals are 2-3x more likely to follow through")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)

            HStack(alignment: .bottom, spacing: 32) {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8).fill(gold).frame(width: 64, height: 160)
                    Text("Specific\nGoal").font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.black).multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.25)).frame(width: 64, height: 60)
                    Text("Vague\nIntention").font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.gray).multilineTextAlignment(.center)
                }
            }

            Text("You've already taken the first step.\nEOS will help you lock it in.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Screen 4: Obstacles

    private var obstaclesScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "What's kept you from being consistent?", subtitle: "Select all that apply.")

            VStack(spacing: 12) {
                multiSelectCard(title: "Lack of motivation", icon: "battery.25percent",
                                isSelected: obstacles.contains("motivation")) { toggleObstacle("motivation") }
                multiSelectCard(title: "No accountability", icon: "person.slash",
                                isSelected: obstacles.contains("accountability")) { toggleObstacle("accountability") }
                multiSelectCard(title: "Busy schedule", icon: "clock",
                                isSelected: obstacles.contains("schedule")) { toggleObstacle("schedule") }
                multiSelectCard(title: "Get bored working out alone", icon: "person",
                                isSelected: obstacles.contains("bored")) { toggleObstacle("bored") }
                multiSelectCard(title: "Start strong, then fall off", icon: "chart.line.downtrend.xyaxis",
                                isSelected: obstacles.contains("falloff")) { toggleObstacle("falloff") }
            }
        }
    }

    private func toggleObstacle(_ key: String) {
        if obstacles.contains(key) { obstacles.remove(key) } else { obstacles.insert(key) }
    }

    // MARK: - Screen 5: Morning

    private var morningScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "Do you struggle getting out of bed?", subtitle: "EOS started as a tool to get people moving in the morning.")

            VStack(spacing: 12) {
                optionCard(title: "Every single morning", icon: "moon.zzz", isSelected: morningStruggle == "every") {
                    morningStruggle = "every"; deadlineHour = 7
                }
                optionCard(title: "Some days are rough", icon: "cloud.sun", isSelected: morningStruggle == "some") {
                    morningStruggle = "some"; deadlineHour = 7
                }
                optionCard(title: "Nah, I'm a morning person", icon: "sun.max.fill", isSelected: morningStruggle == "nah") {
                    morningStruggle = "nah"; deadlineHour = 18
                }
            }
        }
    }

    // MARK: - Screen 6: Motivation

    private var motivationScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "What would keep you on track?", subtitle: "Pick what resonates most.")

            VStack(spacing: 12) {
                optionCard(title: "Putting money on the line", icon: "dollarsign.circle", isSelected: motivationDriver == "money") {
                    motivationDriver = "money"
                }
                optionCard(title: "Competing with friends", icon: "trophy", isSelected: motivationDriver == "friends") {
                    motivationDriver = "friends"
                }
                optionCard(title: "A daily routine with a deadline", icon: "alarm", isSelected: motivationDriver == "routine") {
                    motivationDriver = "routine"
                }
                optionCard(title: "All of the above", icon: "star.fill", isSelected: motivationDriver == "all") {
                    motivationDriver = "all"
                }
            }
        }
    }

    // MARK: - Screen 7: Reaffirmation 2

    private var reaffirmation2: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 20)

            Text("Putting stakes on your goals works")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)

            trendChartVisual

            VStack(spacing: 6) {
                Text("Up to 3x higher completion rate")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(gold)
                Text("when financial accountability is involved.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.gray)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var trendChartVisual: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(gold).frame(width: 8, height: 8)
                    Text("With stakes").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.black)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.gray.opacity(0.4)).frame(width: 8, height: 8)
                    Text("Willpower alone").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.gray)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.06)).frame(height: 180)

                Canvas { context, size in
                    let w = size.width, h = size.height, inset: CGFloat = 16
                    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: inset + x * (w - 2 * inset), y: inset + y * (h - 2 * inset))
                    }

                    var gp = Path()
                    let goldPts: [(CGFloat, CGFloat)] = [(0,0.55),(0.15,0.50),(0.3,0.42),(0.5,0.32),(0.7,0.22),(0.85,0.15),(1.0,0.10)]
                    for (i, p) in goldPts.enumerated() { if i==0 { gp.move(to: pt(p.0,p.1)) } else { gp.addLine(to: pt(p.0,p.1)) } }
                    context.stroke(gp, with: .color(Color(UIColor(red:0.85,green:0.65,blue:0,alpha:1))), lineWidth: 3)

                    var gray = Path()
                    let grayPts: [(CGFloat, CGFloat)] = [(0,0.50),(0.15,0.45),(0.3,0.48),(0.5,0.58),(0.7,0.68),(0.85,0.75),(1.0,0.82)]
                    for (i, p) in grayPts.enumerated() { if i==0 { gray.move(to: pt(p.0,p.1)) } else { gray.addLine(to: pt(p.0,p.1)) } }
                    context.stroke(gray, with: .color(.gray.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [6,4]))
                }
                .frame(height: 180)
            }

            HStack {
                Text("Week 1").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.gray)
                Spacer()
                Text("Week 8").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.gray)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Screen 8: Friends

    private var friendsScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "Do you have friends who work out?", subtitle: nil)

            VStack(spacing: 12) {
                optionCard(title: "Yeah, a few", icon: "person.2", isSelected: hasFriends == "few") { hasFriends = "few" }
                optionCard(title: "I've got a whole crew", icon: "person.3.fill", isSelected: hasFriends == "crew") { hasFriends = "crew" }
                optionCard(title: "Not really, I go solo", icon: "person", isSelected: hasFriends == "solo") { hasFriends = "solo" }
            }
        }
    }

    // MARK: - Screen 9: Competitiveness

    private var competitivenessScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "How competitive are you?", subtitle: "Be honest.")

            VStack(spacing: 12) {
                optionCard(title: "Very — I hate losing", icon: "flame.fill", isSelected: competitiveness == "very") { competitiveness = "very" }
                optionCard(title: "Somewhat — friendly competition is fun", icon: "hands.clap", isSelected: competitiveness == "somewhat") { competitiveness = "somewhat" }
                optionCard(title: "Not at all — I'm here for me", icon: "heart.fill", isSelected: competitiveness == "not") { competitiveness = "not" }
            }
        }
    }

    // MARK: - Screen 10: Reaffirmation 3

    private var reaffirmation3: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 20)

            Text("Friends who compete together stay consistent 4x longer")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.08)).frame(height: 140)
                    VStack(spacing: 8) {
                        Image(systemName: "person").font(.title).foregroundStyle(Color.gray)
                        Text("Solo").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.gray)
                        Text("Week 3: gave up").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.red.opacity(0.7))
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(gold.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(gold.opacity(0.3), lineWidth: 1))
                        .frame(height: 140)
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.fill").font(.title).foregroundStyle(gold)
                        Text("In a Competition").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.black)
                        Text("Week 8: still going").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.green)
                    }
                }
            }

            Text("EOS competitions put real stakes on the line.\nWinner takes the pot.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Screen 11: Target

    private var targetScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "Set your daily target", subtitle: "You can adjust this anytime.")

            VStack(spacing: 24) {
                if selectedObjective == "pushups" || selectedObjective == "both" {
                    stepperCard(label: "Pushups", icon: "figure.strengthtraining.traditional", display: "\(pushupTarget)") {
                        HStack(spacing: 0) {
                            stepButton(systemName: "minus") { if pushupTarget > 5 { pushupTarget -= 5 } }
                            stepButton(systemName: "plus") { if pushupTarget < 200 { pushupTarget += 5 } }
                        }
                    }
                }

                if wantsRun {
                    stepperCard(label: "Run Distance", icon: "figure.run", display: String(format: "%.1f mi", runTarget)) {
                        HStack(spacing: 0) {
                            stepButton(systemName: "minus") { if runTarget > 0.5 { runTarget -= 0.5 } }
                            stepButton(systemName: "plus") { if runTarget < 10.0 { runTarget += 0.5 } }
                        }
                    }
                }
            }
        }
    }

    private func stepperCard<Controls: View>(label: String, icon: String, display: String, @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(gold)
                Text(label).font(.system(.headline, design: .rounded)).foregroundStyle(Color.black)
            }
            HStack {
                Text(display)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                Spacer()
                controls()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.12), lineWidth: 1))
            )
        }
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.black)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.gray.opacity(0.12)))
        }
    }

    // MARK: - Screen 12: Deadline

    private var deadlineScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            if needsMorningHelp {
                screenHeader(title: "Set an early deadline to get moving", subtitle: "The earlier the deadline, the harder it is to hit snooze.")
                VStack(spacing: 12) {
                    deadlineOption(label: "6:00 AM", hour: 6)
                    deadlineOption(label: "7:00 AM", hour: 7, recommended: true)
                    deadlineOption(label: "8:00 AM", hour: 8)
                    deadlineOption(label: "9:00 AM", hour: 9)
                }
            } else {
                screenHeader(title: "When's your deadline each day?", subtitle: "Miss it, and your stakes are on the line.")
                VStack(spacing: 12) {
                    deadlineOption(label: "9:00 AM", hour: 9, subtitle: "Morning person")
                    deadlineOption(label: "12:00 PM", hour: 12, subtitle: "Midday")
                    deadlineOption(label: "6:00 PM", hour: 18, subtitle: "After work")
                    deadlineOption(label: "10:00 PM", hour: 22, subtitle: "Night owl")
                }
            }
        }
    }

    private func deadlineOption(label: String, hour: Int, subtitle: String? = nil, recommended: Bool = false) -> some View {
        Button { deadlineHour = hour } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(label).font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(deadlineHour == hour ? .white : Color.black)
                        if recommended {
                            Text("Recommended")
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(deadlineHour == hour ? .white : gold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(deadlineHour == hour ? Color.white.opacity(0.25) : gold.opacity(0.15)))
                        }
                    }
                    if let subtitle { Text(subtitle).font(.system(.caption, design: .rounded)).foregroundStyle(deadlineHour == hour ? .white.opacity(0.8) : Color.gray) }
                }
                Spacer()
                if deadlineHour == hour { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(deadlineHour == hour ? gold : Color.gray.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(deadlineHour == hour ? gold : Color.gray.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen 13: Account

    private var accountScreen: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 12)

            if isSignedIn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.green)
                    .transition(.scale.combined(with: .opacity))

                Text("Welcome, \(profileUsername.components(separatedBy: " ").first ?? profileUsername)!")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.black)
            } else {
                Image("EOSLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)

                screenHeader(title: "Create your account", subtitle: "Compete with friends, track progress, and put real stakes on your goals.")

                VStack(spacing: 12) {
                    Button {
                        accountAction = "create"
                        showCreateAccountSheet = true
                    } label: {
                        Text("Create Account")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(gold))
                    }

                    Button {
                        accountAction = "signin"
                        showSignInSheet = true
                    } label: {
                        Text("Sign In")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isSignedIn)
    }

    // MARK: - Screen 14: Strava

    private var stravaScreen: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 12)

            if stravaConnected || stravaJustLinked {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.green)
                        .scaleEffect(stravaJustLinked ? 1.0 : 0.5)
                        .opacity(stravaJustLinked ? 1.0 : 0)

                    Text("Strava Connected!")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.black)

                    if !stravaAthleteName.isEmpty {
                        Text(stravaAthleteName)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.gray)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.988, green: 0.322, blue: 0.0))

                Text("Link Strava")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.black)

                if wantsRun {
                    Text("Running objectives require Strava to track your distance automatically. Link now or add it later in Profile.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.gray)
                        .multilineTextAlignment(.center)
                } else {
                    Text("If you ever want to add running goals, you'll need Strava linked. You can always do this later in Profile.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.gray)
                        .multilineTextAlignment(.center)
                }

                Button(action: connectStrava) {
                    HStack(spacing: 8) {
                        if isCheckingStrava {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "link")
                        }
                        Text("Connect with Strava")
                    }
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.988, green: 0.322, blue: 0.0)))
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: stravaConnected)
    }

    // MARK: - Screen 15: Final

    private var finalScreen: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 12)

            Image(systemName: "trophy.fill")
                .font(.system(size: 52))
                .foregroundStyle(gold)

            Text("You're ready to compete")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)

            summaryCard

            Text("The best way to start? Challenge a friend.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow(icon: "target", label: "Goal", value: summaryGoalText)
            Divider()
            summaryRow(icon: "clock", label: "Deadline", value: summaryDeadlineText)
            Divider()
            summaryRow(icon: "calendar", label: "Schedule", value: "Daily")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.12), lineWidth: 1))
        )
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(gold).frame(width: 24)
            Text(label).font(.system(.subheadline, design: .rounded)).foregroundStyle(Color.gray)
            Spacer()
            Text(value).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.black)
        }
    }

    private var summaryGoalText: String {
        switch selectedObjective {
        case "pushups": return "\(pushupTarget) pushups"
        case "run": return String(format: "%.1f mile run", runTarget)
        case "both": return "\(pushupTarget) pushups + \(String(format: "%.1f", runTarget)) mi"
        default: return "—"
        }
    }

    private var summaryDeadlineText: String {
        if deadlineHour < 12 { return "\(deadlineHour):00 AM" }
        if deadlineHour == 12 { return "12:00 PM" }
        return "\(deadlineHour - 12):00 PM"
    }

    // MARK: - Reusable Components

    private func screenHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.gray)
            }
        }
    }

    private func optionCard(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(isSelected ? .white : gold).frame(width: 28)
                Text(title).font(.system(.body, design: .rounded, weight: .medium)).foregroundStyle(isSelected ? .white : Color.black)
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? gold : Color.gray.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? gold : Color.gray.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func multiSelectCard(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(isSelected ? gold : Color.gray).frame(width: 28)
                Text(title).font(.system(.body, design: .rounded, weight: .medium)).foregroundStyle(Color.black)
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square").font(.title3).foregroundStyle(isSelected ? gold : Color.gray.opacity(0.3))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? gold.opacity(0.08) : Color.gray.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? gold : Color.gray.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
