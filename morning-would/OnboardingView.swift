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

    @State private var selectedObjective = "run"
    @State private var fitnessLevel = ""
    @State private var obstacles: Set<String> = []
    @State private var morningStruggle = ""
    @State private var motivationDriver = ""
    @State private var hasFriends = ""
    @State private var competitiveness = ""
    @State private var runTarget = 1.0
    @State private var deadlineHour = 18

    // "yes" = save the recommended goal/deadline as their daily personal
    // objective; "nil" = user hasn't picked yet (Start/Skip stay locked).
    // "no" = blank-slate home screen (no objectives, no deadline).
    @State private var dailyGoalChoice: String? = nil

    @State private var showCreateAccountSheet = false
    @State private var showSignInSheet = false
    @State private var accountAction = ""
    @State private var showCreateCompetition = false
    @State private var isCheckingStrava = false
    @State private var stravaJustLinked = false
    @State private var stravaDelayComplete = false
    @State private var stravaDelayProgress: CGFloat = 0

    // Animation state
    @State private var screenAppeared = false
    @State private var cardStagger: [Bool] = Array(repeating: false, count: 8)
    @State private var continueScale: CGFloat = 1.0
    @State private var stravaRingScale: CGFloat = 0
    @State private var stravaRingOpacity: Double = 0.6

    private let totalPages = 15
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
    private let stravaOrange = Color(red: 0.988, green: 0.322, blue: 0.0)

    private var needsMorningHelp: Bool {
        morningStruggle == "every" || morningStruggle == "some"
    }

    private var wantsRun: Bool { true }

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
        .onChange(of: isSignedIn) { _, _ in
            // Daily-goal settings are no longer auto-written at account
            // creation. They're written once the user makes the explicit
            // Yes/No choice on the final onboarding screen — see
            // `finishOnboarding` and `handleCompetitionCTA`.
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && currentPage == 13 && !userId.isEmpty && !stravaConnected {
                checkStravaStatus()
            }
        }
        .onAppear { triggerScreenAnimations() }
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
                    .shadow(color: gold.opacity(0.5), radius: 4, y: 0)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button(action: advancePage) {
            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 14)
                    .fill(canContinue ? gold : Color.gray.opacity(0.3))

                // Gold fill animation for Strava delay
                if currentPage == 13 && !stravaConnected && !stravaDelayComplete {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(gold)
                            .frame(width: geo.size.width * stravaDelayProgress)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Text(currentPage == 0 ? "Get Started" : "Continue")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .scaleEffect(continueScale)
        .disabled(!canContinue)
        .animation(.easeInOut(duration: 0.2), value: canContinue)
        .onChange(of: canContinue) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { continueScale = 1.06 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.15)) { continueScale = 1.0 }
            }
        }
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
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(dailyGoalChoice == nil ? Color.gray.opacity(0.3) : gold)
                )
            }
            .disabled(dailyGoalChoice == nil)

            Button(action: finishOnboarding) {
                Text("Skip for now")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(dailyGoalChoice == nil ? Color.gray.opacity(0.4) : Color.gray)
            }
            .disabled(dailyGoalChoice == nil)
        }
        .animation(.easeInOut(duration: 0.2), value: dailyGoalChoice)
    }

    // MARK: - Validation

    private var canContinue: Bool {
        switch currentPage {
        case 0: return true
        case 1: return !fitnessLevel.isEmpty
        case 2: return true
        case 3: return !obstacles.isEmpty
        case 4: return !morningStruggle.isEmpty
        case 5: return !motivationDriver.isEmpty
        case 6: return true
        case 7: return !hasFriends.isEmpty
        case 8: return !competitiveness.isEmpty
        case 9: return true
        case 10, 11: return true
        case 12: return isSignedIn
        case 13: return stravaConnected || stravaDelayComplete
        default: return true
        }
    }

    // MARK: - Navigation

    private func advancePage() {
        guard canContinue, currentPage < totalPages - 1 else { return }
        navigateForward = true
        screenAppeared = false
        cardStagger = Array(repeating: false, count: 8)
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
        triggerScreenAnimations()
    }

    private func goBack() {
        guard currentPage > 0 else { return }
        navigateForward = false
        screenAppeared = false
        cardStagger = Array(repeating: false, count: 8)
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage -= 1
        }
        triggerScreenAnimations()
    }

    private func triggerScreenAnimations() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.5)) { screenAppeared = true }
            for i in 0..<8 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(i) * 0.06)) {
                    cardStagger[i] = true
                }
            }
        }
        // Start Strava delay timer when landing on that page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if self.currentPage == 13 && !self.stravaConnected {
                self.startStravaDelay()
            }
        }
    }

    private func startStravaDelay() {
        guard !stravaConnected else { return }
        stravaDelayComplete = false
        stravaDelayProgress = 0
        withAnimation(.linear(duration: 5.0)) {
            stravaDelayProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            stravaDelayComplete = true
        }
    }

    // MARK: - Completion

    private func writeObjectiveSettings() {
        let defaults = UserDefaults.standard

        if dailyGoalChoice == "no" {
            // Blank-slate path: no daily objectives, no deadline, no schedule.
            defaults.set(false, forKey: "pushupsEnabled")
            defaults.set(false, forKey: "pushupsIsSet")
            defaults.set(false, forKey: "runEnabled")
            defaults.set(false, forKey: "runIsSet")
            defaults.set(0, forKey: "pushupObjective")
            defaults.set(0.0, forKey: "runDistance")
            defaults.set(false, forKey: "scheduleIsSet")
            defaults.removeObject(forKey: "scheduleType")
            defaults.removeObject(forKey: "objectiveDeadline")
            return
        }

        // "yes" path (default behavior): personalized run goal + deadline.
        defaults.set(false, forKey: "pushupsEnabled")
        defaults.set(false, forKey: "pushupsIsSet")
        defaults.set(true, forKey: "runEnabled")
        defaults.set(true, forKey: "runIsSet")
        defaults.set(0, forKey: "pushupObjective")
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

        let choice = dailyGoalChoice
        let body: [String: Any]
        if choice == "no" {
            // Blank slate: explicitly disable everything on the server too so
            // no daily session ever gets created for this user.
            body = [
                "pushups_enabled": false,
                "pushups_count": 0,
                "run_enabled": false,
                "run_distance": 0,
                "objective_schedule": "daily",
                "objective_deadline": NSNull(),
                "timezone": TimeZone.current.identifier
            ]
        } else {
            // "yes" path: personalized run goal + deadline from onboarding.
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let deadlineDate = Calendar.current.date(from: DateComponents(hour: deadlineHour, minute: 0)) ?? Date()
            body = [
                "pushups_enabled": false,
                "pushups_count": 0,
                "run_enabled": true,
                "run_distance": runTarget,
                "objective_schedule": "daily",
                "objective_deadline": formatter.string(from: deadlineDate),
                "timezone": TimeZone.current.identifier
            ]
        }

        guard let url = URL(string: "https://api.runmatch.io/objectives/settings/\(userId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AuthToken.applyTo(&request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                print("✅ Onboarding objectives synced (\(choice ?? "default"))")
            }
        }.resume()
    }

    private func finishOnboarding() {
        // Both Skip and Start now flow through here AFTER the user has
        // explicitly picked Yes/No on the daily-goal selector, so we always
        // write+sync settings (the body of those functions branches on
        // dailyGoalChoice).
        writeObjectiveSettings()
        syncObjectivesToBackend()
        hasCompletedOnboarding = true
    }

    private func handleCompetitionCTA() {
        // Persist the daily-goal choice before opening the competition sheet.
        writeObjectiveSettings()
        syncObjectivesToBackend()
        showCreateCompetition = true
    }

    // MARK: - Strava

    private func connectStrava() {
        guard !userId.isEmpty else { return }
        if let url = URL(string: "https://api.runmatch.io/strava/connect/\(userId)") {
            UIApplication.shared.open(url)
        }
    }

    private func checkStravaStatus() {
        guard !userId.isEmpty else { return }
        guard let url = URL(string: "https://api.runmatch.io/strava/status/\(userId)") else { return }

        isCheckingStrava = true
        var _req = URLRequest(url: url)
        AuthToken.applyTo(&_req)
        URLSession.shared.dataTask(with: _req) { data, _, _ in
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
                case 2:  reaffirmation1
                case 3:  obstaclesScreen
                case 4:  morningScreen
                case 5:  motivationScreen
                case 6:  reaffirmation2
                case 7:  friendsScreen
                case 8:  competitivenessScreen
                case 9:  reaffirmation3
                case 10: targetScreen
                case 11: deadlineScreen
                case 12: accountScreen
                case 13: stravaScreen
                case 14: finalScreen
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
        ZStack {
            // Ambient gold glow behind logo
            Circle()
                .fill(gold.opacity(0.08))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .scaleEffect(screenAppeared ? 1.1 : 0.8)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: screenAppeared)
                .offset(y: -60)

            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                Image("RunMatchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .scaleEffect(screenAppeared ? 1 : 0.6)
                    .opacity(screenAppeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: screenAppeared)

                Text("Welcome to RunMatch")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.black, gold], startPoint: .leading, endPoint: .trailing)
                    )
                    .opacity(screenAppeared ? 1 : 0)
                    .offset(y: screenAppeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: screenAppeared)

                VStack(spacing: 10) {
                    welcomePoint(icon: "figure.run", text: "Set daily running goals", index: 0)
                    welcomePoint(icon: "dollarsign.circle", text: "Put real stakes on them", index: 1)
                    welcomePoint(icon: "trophy.fill", text: "Compete with friends", index: 2)
                }
                .padding(.top, 12)
            }
        }
    }

    private func welcomePoint(icon: String, text: String, index: Int) -> some View {
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
        .opacity(cardStagger[safe: index] == true ? 1 : 0)
        .offset(x: cardStagger[safe: index] == true ? 0 : 20)
    }

    // MARK: - Screen 1: Fitness Level

    private var fitnessLevelScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            ZStack(alignment: .leading) {
                // Ambient heartbeat line
                HeartbeatLine(gold: gold)
                    .opacity(screenAppeared ? 0.25 : 0)
                    .animation(.easeIn(duration: 0.8), value: screenAppeared)

                screenHeader(title: "How would you describe your fitness level?", subtitle: "This helps us set the right starting point.")
            }

            VStack(spacing: 12) {
                animatedCard(index: 0) {
                    optionCard(title: "Just getting started", icon: "leaf", isSelected: fitnessLevel == "beginner") {
                        fitnessLevel = "beginner"; runTarget = 0.5
                    }
                }
                animatedCard(index: 1) {
                    optionCard(title: "Somewhat active", icon: "figure.walk", isSelected: fitnessLevel == "somewhat") {
                        fitnessLevel = "somewhat"; runTarget = 1.0
                    }
                }
                animatedCard(index: 2) {
                    optionCard(title: "Consistently active", icon: "figure.run", isSelected: fitnessLevel == "consistent") {
                        fitnessLevel = "consistent"; runTarget = 2.0
                    }
                }
                animatedCard(index: 3) {
                    optionCard(title: "Athlete", icon: "bolt.fill", isSelected: fitnessLevel == "athlete") {
                        fitnessLevel = "athlete"; runTarget = 4.0
                    }
                }
            }
        }
    }

    // MARK: - Screen 2: Reaffirmation 1

    private var reaffirmation1: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 20)

            Text("People with specific goals are 2-3x more likely to follow through")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.5), value: screenAppeared)

            HStack(alignment: .bottom, spacing: 32) {
                VStack(spacing: 8) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 8).fill(gold)
                            .frame(width: 64, height: screenAppeared ? 160 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.3), value: screenAppeared)
                        // Floating "2-3x" label
                        Text("2-3x")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(gold)
                            .offset(y: screenAppeared ? -24 : 0)
                            .opacity(screenAppeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.0), value: screenAppeared)
                    }
                    Text("Specific\nGoal").font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.black).multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.25))
                        .frame(width: 64, height: screenAppeared ? 60 : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.5), value: screenAppeared)
                    Text("Vague\nIntention").font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.gray).multilineTextAlignment(.center)
                }
            }

            Text("You've already taken the first step.\nRunMatch will help you lock it in.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.8), value: screenAppeared)
        }
    }

    // MARK: - Screen 4: Obstacles

    private var obstaclesScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "What's kept you from being consistent?", subtitle: "Select all that apply.")

            VStack(spacing: 12) {
                animatedCard(index: 0) {
                    multiSelectCard(title: "Lack of motivation", icon: "battery.25percent",
                                    isSelected: obstacles.contains("motivation")) { toggleObstacle("motivation") }
                }
                animatedCard(index: 1) {
                    multiSelectCard(title: "No accountability", icon: "person.slash",
                                    isSelected: obstacles.contains("accountability")) { toggleObstacle("accountability") }
                }
                animatedCard(index: 2) {
                    multiSelectCard(title: "Busy schedule", icon: "clock",
                                    isSelected: obstacles.contains("schedule")) { toggleObstacle("schedule") }
                }
                animatedCard(index: 3) {
                    multiSelectCard(title: "Get bored running alone", icon: "person",
                                    isSelected: obstacles.contains("bored")) { toggleObstacle("bored") }
                }
                animatedCard(index: 4) {
                    multiSelectCard(title: "Start strong, then fall off", icon: "chart.line.downtrend.xyaxis",
                                    isSelected: obstacles.contains("falloff")) { toggleObstacle("falloff") }
                }
            }
        }
    }

    private func toggleObstacle(_ key: String) {
        if obstacles.contains(key) { obstacles.remove(key) } else { obstacles.insert(key) }
    }

    // MARK: - Screen 5: Morning

    private var morningScreen: some View {
        ZStack(alignment: .top) {
            // Sunrise gradient ambient
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.1, blue: 0.3).opacity(screenAppeared ? 0.08 : 0),
                    Color(red: 0.95, green: 0.6, blue: 0.2).opacity(screenAppeared ? 0.1 : 0),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 200)
            .blur(radius: 30)
            .animation(.easeIn(duration: 1.5), value: screenAppeared)

            VStack(alignment: .leading, spacing: 28) {
                screenHeader(title: "Do you struggle getting out of bed?", subtitle: "RunMatch was built to get runners out the door in the morning.")

                VStack(spacing: 12) {
                    animatedCard(index: 0) {
                        optionCard(title: "Every single morning", icon: "moon.zzz", isSelected: morningStruggle == "every") {
                            morningStruggle = "every"; deadlineHour = 7
                        }
                    }
                    animatedCard(index: 1) {
                        optionCard(title: "Some days are rough", icon: "cloud.sun", isSelected: morningStruggle == "some") {
                            morningStruggle = "some"; deadlineHour = 7
                        }
                    }
                    animatedCard(index: 2) {
                        optionCard(title: "Nah, I'm a morning person", icon: "sun.max.fill", isSelected: morningStruggle == "nah") {
                            morningStruggle = "nah"; deadlineHour = 18
                        }
                    }
                }
            }
        }
    }

    // MARK: - Screen 6: Motivation

    private var motivationScreen: some View {
        ZStack {
            // Floating motivational icons
            FloatingBubbles(gold: gold, appeared: screenAppeared)

            VStack(alignment: .leading, spacing: 28) {
                screenHeader(title: "What would keep you on track?", subtitle: "Pick what resonates most.")

                VStack(spacing: 12) {
                    animatedCard(index: 0) {
                        optionCard(title: "Putting money on the line", icon: "dollarsign.circle", isSelected: motivationDriver == "money") {
                            motivationDriver = "money"
                        }
                    }
                    animatedCard(index: 1) {
                        optionCard(title: "Competing with friends", icon: "trophy", isSelected: motivationDriver == "friends") {
                            motivationDriver = "friends"
                        }
                    }
                    animatedCard(index: 2) {
                        optionCard(title: "A daily routine with a deadline", icon: "alarm", isSelected: motivationDriver == "routine") {
                            motivationDriver = "routine"
                        }
                    }
                    animatedCard(index: 3) {
                        optionCard(title: "All of the above", icon: "star.fill", isSelected: motivationDriver == "all") {
                            motivationDriver = "all"
                        }
                    }
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
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: screenAppeared)

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
            .opacity(screenAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(1.2), value: screenAppeared)
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

                AnimatedTrendChart(gold: gold, appeared: screenAppeared)
                    .frame(height: 180)

                // Pulsing dot positioned at end of gold line: point (1.0, 0.10) with 16pt inset
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height, inset: CGFloat = 16
                    let dotX = inset + 1.0 * (w - 2 * inset)
                    let dotY = inset + 0.10 * (h - 2 * inset)
                    Circle()
                        .fill(gold)
                        .frame(width: 10, height: 10)
                        .shadow(color: gold.opacity(0.6), radius: 6)
                        .scaleEffect(screenAppeared ? 1.3 : 0)
                        .opacity(screenAppeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(1.3), value: screenAppeared)
                        .position(x: dotX, y: dotY)
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
        ZStack(alignment: .top) {
            RunningBuddies(gold: gold, appeared: screenAppeared)
                .frame(height: 40)
                .padding(.top, -8)

            VStack(alignment: .leading, spacing: 28) {
                screenHeader(title: "Do you have friends who run?", subtitle: nil)

                VStack(spacing: 12) {
                    animatedCard(index: 0) {
                        optionCard(title: "Yeah, a few", icon: "person.2", isSelected: hasFriends == "few") { hasFriends = "few" }
                    }
                    animatedCard(index: 1) {
                        optionCard(title: "I've got a whole crew", icon: "person.3.fill", isSelected: hasFriends == "crew") { hasFriends = "crew" }
                    }
                    animatedCard(index: 2) {
                        optionCard(title: "Not really, I go solo", icon: "person", isSelected: hasFriends == "solo") { hasFriends = "solo" }
                    }
                }
            }
        }
    }

    // MARK: - Screen 9: Competitiveness

    private var competitivenessScreen: some View {
        ZStack {
            FlameParticles(gold: gold, appeared: screenAppeared)

            VStack(alignment: .leading, spacing: 28) {
                screenHeader(title: "How competitive are you?", subtitle: "Be honest.")

                VStack(spacing: 12) {
                    animatedCard(index: 0) {
                        optionCard(title: "Very — I hate losing", icon: "flame.fill", isSelected: competitiveness == "very") { competitiveness = "very" }
                    }
                    animatedCard(index: 1) {
                        optionCard(title: "Somewhat — friendly competition is fun", icon: "hands.clap", isSelected: competitiveness == "somewhat") { competitiveness = "somewhat" }
                    }
                    animatedCard(index: 2) {
                        optionCard(title: "Not at all — I'm here for me", icon: "heart.fill", isSelected: competitiveness == "not") { competitiveness = "not" }
                    }
                }
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
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: screenAppeared)

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.08)).frame(height: 140)
                    VStack(spacing: 8) {
                        Image(systemName: "person").font(.title).foregroundStyle(Color.gray)
                        Text("Solo").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.gray)
                        Text("Week 3: gave up").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.red.opacity(0.7))
                    }
                }
                .opacity(screenAppeared ? 1 : 0)
                .offset(x: screenAppeared ? 0 : -20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: screenAppeared)

                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(gold.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(gold.opacity(0.3), lineWidth: 1))
                        .overlay(
                            ShimmerOverlay(gold: gold, appeared: screenAppeared)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        )
                        .frame(height: 140)
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.fill").font(.title).foregroundStyle(gold)
                        Text("In a Competition").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.black)
                        Text("Week 8: still going").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.green)
                    }
                }
                .opacity(screenAppeared ? 1 : 0)
                .offset(x: screenAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: screenAppeared)
            }

            Text("RunMatch competitions put real stakes on the line.\nWinner takes the pot.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.6), value: screenAppeared)
        }
    }

    // MARK: - Screen 11: Target

    private var targetScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "Set your daily run distance", subtitle: "You can adjust this anytime.")

            VStack(spacing: 20) {
                // Big distance display
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.run").font(.title3).foregroundStyle(gold)
                        Text("Run Distance").font(.system(.headline, design: .rounded)).foregroundStyle(Color.black)
                    }
                    Text(String(format: "%.1f mi", runTarget))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: runTarget)
                }

                // Draggable slider
                VStack(spacing: 8) {
                    RunDistanceSlider(value: $runTarget, range: 0.5...10.0, step: 0.5, gold: gold)
                        .frame(height: 44)

                    HStack {
                        Text("0.5 mi").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.gray)
                        Spacer()
                        Text("10.0 mi").font(.system(.caption2, design: .rounded)).foregroundStyle(Color.gray)
                    }
                }

                // Hovering runner icon
                HoveringRunner(gold: gold)
                    .frame(height: 70)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.12), lineWidth: 1))
            )
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
            HStack(spacing: 16) {
                ClockFace(hour: deadlineHour, gold: gold)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    if needsMorningHelp {
                        Text("Set an early deadline to get moving")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.black)
                        Text("The earlier the deadline, the harder it is to hit snooze.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.gray)
                    } else {
                        Text("When's your deadline each day?")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.black)
                        Text("Miss it, and your stakes are on the line.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.gray)
                    }
                }
            }

            if needsMorningHelp {
                VStack(spacing: 12) {
                    animatedCard(index: 0) { deadlineOption(label: "6:00 AM", hour: 6) }
                    animatedCard(index: 1) { deadlineOption(label: "7:00 AM", hour: 7, recommended: true) }
                    animatedCard(index: 2) { deadlineOption(label: "8:00 AM", hour: 8) }
                    animatedCard(index: 3) { deadlineOption(label: "9:00 AM", hour: 9) }
                }
            } else {
                VStack(spacing: 12) {
                    animatedCard(index: 0) { deadlineOption(label: "9:00 AM", hour: 9, subtitle: "Morning person") }
                    animatedCard(index: 1) { deadlineOption(label: "12:00 PM", hour: 12, subtitle: "Midday") }
                    animatedCard(index: 2) { deadlineOption(label: "6:00 PM", hour: 18, subtitle: "After work") }
                    animatedCard(index: 3) { deadlineOption(label: "10:00 PM", hour: 22, subtitle: "Night owl") }
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
        ZStack {
            // Ambient shield glow
            Image(systemName: "shield.fill")
                .font(.system(size: 200))
                .foregroundStyle(gold.opacity(screenAppeared ? 0.04 : 0))
                .blur(radius: 20)
                .animation(.easeIn(duration: 1.5), value: screenAppeared)
                .offset(y: -40)

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
                    Image("RunMatchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .opacity(screenAppeared ? 1 : 0)
                        .scaleEffect(screenAppeared ? 1 : 0.8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: screenAppeared)

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
                        .opacity(screenAppeared ? 1 : 0)
                        .offset(y: screenAppeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: screenAppeared)

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
                        .opacity(screenAppeared ? 1 : 0)
                        .offset(y: screenAppeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: screenAppeared)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isSignedIn)
    }

    // MARK: - Screen 14: Strava

    private var stravaScreen: some View {
        ZStack {
            // Motion lines behind runner
            if !stravaConnected && !stravaJustLinked {
                StravaMotionLines(appeared: screenAppeared)
                    .offset(y: -80)
            }

            VStack(spacing: 28) {
                Spacer().frame(height: 12)

                if stravaConnected || stravaJustLinked {
                    VStack(spacing: 16) {
                        ZStack {
                            // Expanding ring
                            Circle()
                                .stroke(Color.green.opacity(stravaRingOpacity), lineWidth: 3)
                                .frame(width: 80, height: 80)
                                .scaleEffect(stravaRingScale)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(Color.green)
                                .scaleEffect(stravaJustLinked ? 1.0 : 0.5)
                                .opacity(stravaJustLinked ? 1.0 : 0)
                        }
                        .onChange(of: stravaJustLinked) { _, linked in
                            if linked {
                                withAnimation(.easeOut(duration: 0.8)) { stravaRingScale = 2.5; stravaRingOpacity = 0 }
                            }
                        }

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
                        .foregroundStyle(stravaOrange)
                        .opacity(screenAppeared ? 1 : 0)
                        .scaleEffect(screenAppeared ? 1 : 0.7)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: screenAppeared)

                    Text("Link Strava")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.black)

                    Text("Strava tracks your runs automatically so every mile counts toward your goals and competitions. Link now or add it later in Profile.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.gray)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.black.opacity(0.4))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All runs must be started and ended on Strava. Completed runs are automatically logged toward your RunMatch goals and competitions.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.5))
                                Text("You won't be able to track runs without Strava linked.")
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.7))
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.gray.opacity(0.08))
                    )

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
                        .background(RoundedRectangle(cornerRadius: 14).fill(stravaOrange))
                    }
                    .opacity(screenAppeared ? 1 : 0)
                    .offset(y: screenAppeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: screenAppeared)
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: stravaConnected)
    }

    // MARK: - Screen 15: Final

    private var finalScreen: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 12)

            ZStack {
                // Trophy shimmer
                Image(systemName: "trophy.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(gold.opacity(0.08))
                    .blur(radius: 20)
                    .scaleEffect(screenAppeared ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: screenAppeared)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(gold)
                    .scaleEffect(screenAppeared ? 1 : 0.5)
                    .opacity(screenAppeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: screenAppeared)
            }

            Text("You're ready to compete")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: screenAppeared)

            summaryCard

            dailyGoalSelector
        }
    }

    private var dailyGoalSelector: some View {
        VStack(spacing: 14) {
            Text("Set as your daily goals?")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                choicePill(label: "Yes", isSelected: dailyGoalChoice == "yes") {
                    dailyGoalChoice = "yes"
                }
                choicePill(label: "No", isSelected: dailyGoalChoice == "no") {
                    dailyGoalChoice = "no"
                }
            }
        }
        .padding(.top, 4)
        .opacity(screenAppeared ? 1 : 0)
        .offset(y: screenAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.4).delay(0.6), value: screenAppeared)
    }

    private func choicePill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.black)
                .frame(width: 110, height: 46)
                .background(
                    Capsule().fill(isSelected ? gold : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isSelected ? gold : Color.gray.opacity(0.35), lineWidth: 1.5)
                )
        }
        .buttonStyle(BounceButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow(icon: "target", label: "Goal", value: summaryGoalText, index: 0)
            Divider()
            summaryRow(icon: "clock", label: "Deadline", value: summaryDeadlineText, index: 1)
            Divider()
            summaryRow(icon: "calendar", label: "Schedule", value: "Daily", index: 2)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.12), lineWidth: 1))
        )
        .opacity(screenAppeared ? 1 : 0)
        .offset(y: screenAppeared ? 0 : 15)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: screenAppeared)
    }

    private func summaryRow(icon: String, label: String, value: String, index: Int = 0) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(gold).frame(width: 24)
            Text(label).font(.system(.subheadline, design: .rounded)).foregroundStyle(Color.gray)
            Spacer()
            Text(value).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Color.black)
        }
        .opacity(cardStagger[safe: index] == true ? 1 : 0)
        .offset(x: cardStagger[safe: index] == true ? 0 : 15)
    }

    private var summaryGoalText: String {
        return String(format: "%.1f mile run", runTarget)
    }

    private var summaryDeadlineText: String {
        if deadlineHour < 12 { return "\(deadlineHour):00 AM" }
        if deadlineHour == 12 { return "12:00 PM" }
        return "\(deadlineHour - 12):00 PM"
    }

    // MARK: - Animated Card Wrapper

    private func animatedCard<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(cardStagger[safe: index] == true ? 1 : 0)
            .offset(y: cardStagger[safe: index] == true ? 0 : 12)
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
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
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
        .buttonStyle(BounceButtonStyle())
    }

    private func multiSelectCard(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
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
        .buttonStyle(BounceButtonStyle())
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Bounce Button Style

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Heartbeat Line (Fitness Level)

struct HeartbeatLine: View {
    let gold: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let h = size.height, w = size.width
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t.truncatingRemainder(dividingBy: 2.0) / 2.0)
                var path = Path()
                let segments: Int = 200
                for i in 0...segments {
                    let x = CGFloat(i) / CGFloat(segments) * w
                    let norm = (x / w + phase).truncatingRemainder(dividingBy: 1.0)
                    let y: CGFloat
                    if norm > 0.4 && norm < 0.45 {
                        y = h * 0.5 - h * 0.35 * sin((norm - 0.4) / 0.05 * .pi)
                    } else if norm > 0.45 && norm < 0.5 {
                        y = h * 0.5 + h * 0.2 * sin((norm - 0.45) / 0.05 * .pi)
                    } else {
                        y = h * 0.5
                    }
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(gold), lineWidth: 1.5)
            }
        }
        .frame(height: 40)
    }
}

// MARK: - Floating Bubbles (Motivation)

struct FloatingBubbles: View {
    let gold: Color
    let appeared: Bool
    @State private var animate = false

    private let icons = ["dollarsign.circle", "trophy.fill", "star.fill", "alarm"]
    private let positions: [(x: CGFloat, y: CGFloat)] = [
        (0.15, 0.2), (0.8, 0.15), (0.25, 0.7), (0.85, 0.65)
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: icons[i])
                    .font(.system(size: 14))
                    .foregroundStyle(gold.opacity(0.12))
                    .position(
                        x: positions[i].x * geo.size.width,
                        y: positions[i].y * geo.size.height + (animate ? -15 : 15)
                    )
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Animated Trend Chart (Reaffirmation 2)

struct TrendLineShape: Shape {
    let points: [(CGFloat, CGFloat)]
    let inset: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        for (i, p) in points.enumerated() {
            let pt = CGPoint(x: inset + p.0 * (w - 2 * inset), y: inset + p.1 * (h - 2 * inset))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }
}

struct AnimatedTrendChart: View {
    let gold: Color
    let appeared: Bool
    @State private var goldTrim: CGFloat = 0
    @State private var grayTrim: CGFloat = 0

    private let goldPts: [(CGFloat, CGFloat)] = [(0,0.55),(0.15,0.50),(0.3,0.42),(0.5,0.32),(0.7,0.22),(0.85,0.15),(1.0,0.10)]
    private let grayPts: [(CGFloat, CGFloat)] = [(0,0.50),(0.15,0.45),(0.3,0.48),(0.5,0.58),(0.7,0.68),(0.85,0.75),(1.0,0.82)]

    var body: some View {
        ZStack {
            TrendLineShape(points: grayPts)
                .trim(from: 0, to: grayTrim)
                .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

            TrendLineShape(points: goldPts)
                .trim(from: 0, to: goldTrim)
                .stroke(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)), lineWidth: 3)
        }
        .onAppear { startDrawing() }
        .onChange(of: appeared) { _, val in
            if val { startDrawing() } else { goldTrim = 0; grayTrim = 0 }
        }
    }

    private func startDrawing() {
        goldTrim = 0
        grayTrim = 0
        withAnimation(.easeOut(duration: 1.2).delay(0.3)) { goldTrim = 1.0 }
        withAnimation(.easeOut(duration: 1.2).delay(0.5)) { grayTrim = 1.0 }
    }
}

// MARK: - Running Buddies (Friends)

struct RunningBuddies: View {
    let gold: Color
    let appeared: Bool
    @State private var offset: CGFloat = -60

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 16))
                    .foregroundStyle(gold.opacity(0.2))
                Image(systemName: "figure.run")
                    .font(.system(size: 14))
                    .foregroundStyle(gold.opacity(0.12))
            }
            .offset(x: offset)
            .onAppear {
                guard appeared else { return }
                startLoop(width: geo.size.width)
            }
            .onChange(of: appeared) { _, val in
                if val { startLoop(width: geo.size.width) }
            }
        }
    }

    private func startLoop(width: CGFloat) {
        offset = -60
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            offset = width + 60
        }
    }
}

// MARK: - Flame Particles (Competitiveness)

struct FlameParticles: View {
    let gold: Color
    let appeared: Bool
    @State private var animate = false

    private let particles: [(x: CGFloat, delay: Double, size: CGFloat)] = [
        (0.2, 0, 6), (0.35, 0.4, 4), (0.5, 0.1, 5),
        (0.65, 0.6, 4), (0.8, 0.3, 6), (0.45, 0.8, 3)
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<particles.count, id: \.self) { i in
                let p = particles[i]
                Circle()
                    .fill(
                        i % 2 == 0
                            ? gold.opacity(0.15)
                            : Color.orange.opacity(0.12)
                    )
                    .frame(width: p.size, height: p.size)
                    .position(
                        x: p.x * geo.size.width,
                        y: animate ? -10 : geo.size.height * 0.3
                    )
                    .opacity(animate ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 2.5)
                        .repeatForever(autoreverses: false)
                        .delay(p.delay),
                        value: animate
                    )
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if appeared { animate = true }
        }
        .onChange(of: appeared) { _, val in
            if val { animate = true }
        }
    }
}

// MARK: - Shimmer Overlay (Reaffirmation 3)

struct ShimmerOverlay: View {
    let gold: Color
    let appeared: Bool
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, gold.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 80)
            .offset(x: shimmerOffset)
            .onAppear {
                guard appeared else { return }
                startShimmer()
            }
            .onChange(of: appeared) { _, val in
                if val { startShimmer() }
            }
    }

    private func startShimmer() {
        shimmerOffset = -200
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false).delay(1)) {
            shimmerOffset = 300
        }
    }
}

// MARK: - Run Distance Slider (Target)

struct RunDistanceSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gold: Color

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let thumbSize: CGFloat = 28
            let trackPadding: CGFloat = thumbSize / 2
            let trackWidth = w - thumbSize
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbX = trackPadding + fraction * trackWidth

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 6)
                    .padding(.horizontal, trackPadding)

                // Filled track
                RoundedRectangle(cornerRadius: 4)
                    .fill(gold)
                    .frame(width: thumbX, height: 6)
                    .padding(.leading, 0)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: gold.opacity(0.3), radius: isDragging ? 8 : 4)
                    .overlay(Circle().stroke(gold, lineWidth: 2.5))
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .position(x: thumbX, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                isDragging = true
                                let x = drag.location.x
                                let clamped = max(trackPadding, min(x, trackPadding + trackWidth))
                                let frac = Double((clamped - trackPadding) / trackWidth)
                                let raw = range.lowerBound + frac * (range.upperBound - range.lowerBound)
                                let snapped = (raw / step).rounded() * step
                                let newVal = max(range.lowerBound, min(snapped, range.upperBound))
                                if newVal != value {
                                    value = newVal
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
        }
    }
}

// MARK: - Animated Runner (Target)

struct HoveringRunner: View {
    let gold: Color
    @State private var hovering = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.05))
                .frame(width: 36, height: 6)
                .offset(y: 26)
                .blur(radius: 2)

            Image(systemName: "figure.run")
                .font(.system(size: 44))
                .foregroundStyle(gold)
                .offset(y: hovering ? -4 : 4)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: hovering)
        }
        .onAppear { hovering = true }
    }
}

// MARK: - Clock Face (Deadline)

struct ClockFace: View {
    let hour: Int
    let gold: Color
    @State private var secondTick: Int = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 2)

            // Hour markers
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1.5, height: i % 3 == 0 ? 6 : 3)
                    .offset(y: -22)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // Second hand
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.red.opacity(0.5))
                .frame(width: 1, height: 20)
                .offset(y: -10)
                .rotationEffect(.degrees(Double(secondTick) * 6))
                .animation(.easeOut(duration: 0.15), value: secondTick)

            // Hour hand
            RoundedRectangle(cornerRadius: 1)
                .fill(gold)
                .frame(width: 2.5, height: 14)
                .offset(y: -7)
                .rotationEffect(.degrees(Double(hour % 12) * 30))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: hour)

            // Center dot
            Circle()
                .fill(gold)
                .frame(width: 5, height: 5)
        }
        .onAppear { startTicking() }
    }

    private func startTicking() {
        Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { _ in
            secondTick = (secondTick + 1) % 60
        }
    }
}

// MARK: - Strava Motion Lines

struct StravaMotionLines: View {
    let appeared: Bool
    @State private var animate = false
    private let stravaOrange = Color(red: 0.988, green: 0.322, blue: 0.0)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(stravaOrange.opacity(animate ? 0.06 : 0.15))
                    .frame(width: CGFloat(40 - i * 10), height: 2)
                    .offset(x: animate ? -20 : 0)
                    .animation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if appeared { animate = true }
        }
        .onChange(of: appeared) { _, val in
            if val { animate = true }
        }
    }
}
