import SwiftUI
import StripePaymentSheet

// MARK: - Onboarding Flow (v3 — Friends & Competition Focus)

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

    // Interactive state for new screens
    @State private var selectedMatchType: String = ""
    @State private var selectedBuyIn: Double = 10
    @State private var wantsDailyStakes: String? = nil
    @State private var joinCodeText: String = ""

    @State private var showCreateAccountSheet = false
    @State private var showSignInSheet = false
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
    @State private var potAnimating = false

    private let totalPages = 11
    private let gold = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
    private let stravaOrange = Color(red: 0.988, green: 0.322, blue: 0.0)

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
                    Spacer().frame(height: 20)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && currentPage == 9 && !userId.isEmpty && !stravaConnected {
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(canContinue ? gold : Color.gray.opacity(0.3))

                if currentPage == 9 && !stravaConnected && !stravaDelayComplete {
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

    // MARK: - Validation

    private var canContinue: Bool {
        switch currentPage {
        case 0: return true                                  // Welcome
        case 1: return true                                  // Friends hook
        case 2: return true                                  // How it works
        case 3: return true                                   // Pick format (browse only)
        case 4: return true                                  // Set stakes
        case 5: return true                                  // $10 on us
        case 6: return true                                  // Strava explainer
        case 7: return wantsDailyStakes != nil                // Daily stakes choice
        case 8: return isSignedIn                             // Account
        case 9: return stravaConnected || stravaDelayComplete // Strava connect
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if self.currentPage == 9 && !self.stravaConnected {
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

        if wantsDailyStakes != "yes" {
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

        defaults.set(false, forKey: "pushupsEnabled")
        defaults.set(false, forKey: "pushupsIsSet")
        defaults.set(true, forKey: "runEnabled")
        defaults.set(true, forKey: "runIsSet")
        defaults.set(0, forKey: "pushupObjective")
        defaults.set(2.0, forKey: "runDistance")
        defaults.set("Daily", forKey: "scheduleType")
        defaults.set(true, forKey: "scheduleIsSet")

        let comps = DateComponents(hour: 18, minute: 0)
        if let date = Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) {
            defaults.set(date.timeIntervalSince1970, forKey: "objectiveDeadline")
        }
    }

    private func syncObjectivesToBackend() {
        guard !userId.isEmpty else { return }

        let body: [String: Any]
        if wantsDailyStakes != "yes" {
            body = [
                "pushups_enabled": false, "pushups_count": 0,
                "run_enabled": false, "run_distance": 0,
                "objective_schedule": "daily",
                "objective_deadline": NSNull(),
                "timezone": TimeZone.current.identifier
            ]
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let deadlineDate = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
            body = [
                "pushups_enabled": false, "pushups_count": 0,
                "run_enabled": true, "run_distance": 2.0,
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
                print("✅ Onboarding objectives synced")
            }
        }.resume()
    }

    private func finishOnboarding() {
        writeObjectiveSettings()
        syncObjectivesToBackend()
        hasCompletedOnboarding = true
    }

    private func handleCreateMatch() {
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
                case 1:  friendsHookScreen
                case 2:  howItWorksScreen
                case 3:  pickFormatScreen
                case 4:  setStakesScreen
                case 5:  freeMatchScreen
                case 6:  stravaExplainerScreen
                case 7:  dailyStakesScreen
                case 8:  accountScreen
                case 9:  stravaConnectScreen
                case 10: challengeFriendsScreen
                default: EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 0: Welcome (kept from original)

    private var welcomeScreen: some View {
        ZStack {
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

    // MARK: - Screen 1: "Your friends are betting they can outrun you."

    private var friendsHookScreen: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 16)

            VStack(spacing: 6) {
                Text("Your friends are betting")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("they can outrun you.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(gold)
            }
            .multilineTextAlignment(.center)
            .opacity(screenAppeared ? 1 : 0)
            .offset(y: screenAppeared ? 0 : 10)
            .animation(.easeOut(duration: 0.5), value: screenAppeared)

            VStack(spacing: 6) {
                chatBubble(name: "Jordan", message: "You're going down this week 💪", isMe: false, index: 0)
                chatBubble(name: "Sarah", message: "I'll put $25 on it", isMe: false, index: 1)
                chatBubble(name: nil, message: "You're on 😤", isMe: true, index: 2)
                chatBubble(name: "Mike", message: "Bet. Put it on RunMatch 🏆", isMe: false, index: 3)
            }

            Text("Challenge friends to running matches.\nWinner takes the pot.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.7), value: screenAppeared)
        }
    }

    private func chatBubble(name: String?, message: String, isMe: Bool, index: Int) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMe { Spacer(minLength: 60) }
            if !isMe {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String((name ?? "?").prefix(1)))
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.gray)
                    )
            }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if let name, !isMe {
                    Text(name)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.gray)
                        .padding(.leading, 4)
                }
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(isMe ? .white : Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isMe ? gold : Color(UIColor.systemGray6))
                    )
            }
            if !isMe { Spacer(minLength: 60) }
        }
        .opacity(cardStagger[safe: index] == true ? 1 : 0)
        .offset(y: cardStagger[safe: index] == true ? 0 : 10)
    }

    // MARK: - Screen 2: "Here's how it works."

    @State private var loopRotation: Double = 0

    private var howItWorksScreen: some View {
        VStack(spacing: 28) {
            screenHeader(title: "Here's how it works.", subtitle: nil)

            Spacer().frame(height: 8)

            ZStack {
                // Connecting ring
                Circle()
                    .stroke(gold.opacity(0.15), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: 200, height: 200)
                    .opacity(screenAppeared ? 1 : 0)
                    .animation(.easeIn(duration: 0.6), value: screenAppeared)

                // Rotating arc
                Circle()
                    .trim(from: 0, to: 0.12)
                    .stroke(gold.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(loopRotation))

                // Three nodes positioned on the circle
                loopNode(icon: "trophy.fill", label: "Match", angle: -90, index: 0)
                loopNode(icon: "figure.run", label: "Run", angle: 30, index: 1)
                loopNode(icon: "dollarsign.circle.fill", label: "Win", angle: 150, index: 2)

                // Curved arrows between nodes
                ForEach([(-90.0, 30.0), (30.0, 150.0), (150.0, 270.0)], id: \.0) { from, to in
                    Circle()
                        .trim(from: CGFloat((from + 100) / 360), to: CGFloat((to - 10) / 360))
                        .stroke(gold.opacity(screenAppeared ? 0.25 : 0), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                        .frame(width: 200, height: 200)
                        .animation(.easeOut(duration: 0.8).delay(0.5), value: screenAppeared)
                }
            }
            .frame(height: 260)
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    loopRotation = 360
                }
            }

            // Labels below
            VStack(spacing: 14) {
                loopLabel(number: "1", text: "Start a match & set the stakes", index: 0)
                loopLabel(number: "2", text: "Everyone runs — tracked by Strava", index: 1)
                loopLabel(number: "3", text: "Winner takes the pot", index: 2)
            }
        }
    }

    private func loopNode(icon: String, label: String, angle: Double, index: Int) -> some View {
        let r: CGFloat = 100
        let rad = angle * .pi / 180
        let x = cos(rad) * r
        let y = sin(rad) * r
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(gold).frame(width: 52, height: 52)
                    .shadow(color: gold.opacity(0.3), radius: 8, y: 3)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
        }
        .offset(x: x, y: y)
        .scaleEffect(cardStagger[safe: index] == true ? 1 : 0.3)
        .opacity(cardStagger[safe: index] == true ? 1 : 0)
    }

    private func loopLabel(number: String, text: String, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(gold))
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.black)
            Spacer()
        }
        .opacity(cardStagger[safe: index] == true ? 1 : 0)
        .offset(x: cardStagger[safe: index] == true ? 0 : 15)
    }

    // MARK: - Screen 3: "Pick your format."

    @State private var dropIn: [Bool] = [false, false, false]

    private var pickFormatScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            screenHeader(title: "Pick your competition.", subtitle: "Three ways to compete.")

            VStack(spacing: 18) {
                matchTypeCard(type: "race", icon: "flag.checkered", title: "Race",
                              desc: "First to hit the distance wins", example: "First to 10 miles wins $100")
                    .opacity(dropIn[0] ? 1 : 0)
                    .offset(y: dropIn[0] ? 0 : -60)
                    .scaleEffect(dropIn[0] ? 1 : 0.85)

                matchTypeCard(type: "cumulative", icon: "chart.bar.fill", title: "Most Miles",
                              desc: "Highest total in the timeframe wins", example: "Most miles in 7 days takes the $75 pot")
                    .opacity(dropIn[1] ? 1 : 0)
                    .offset(y: dropIn[1] ? 0 : -60)
                    .scaleEffect(dropIn[1] ? 1 : 0.85)

                matchTypeCard(type: "consistency", icon: "flame.fill", title: "Streak",
                              desc: "Hit your daily target every single day", example: "Miss a day and you're out")
                    .opacity(dropIn[2] ? 1 : 0)
                    .offset(y: dropIn[2] ? 0 : -60)
                    .scaleEffect(dropIn[2] ? 1 : 0.85)
            }
        }
        .onAppear { triggerDropCascade() }
    }

    private func triggerDropCascade() {
        dropIn = [false, false, false]
        for i in 0..<3 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.4 + Double(i) * 0.18)) {
                dropIn[i] = true
            }
        }
    }

    private func matchTypeCard(type: String, icon: String, title: String, desc: String, example: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(gold)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.black)
                    Text(desc)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.gray)
                }
                Spacer()
            }
            Text("\"\(example)\"")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(gold.opacity(0.8))
                .italic()
                .padding(.leading, 42)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(gold.opacity(0.35), lineWidth: 1.5)
        )
    }

    // MARK: - Screen 4: "Set the stakes."

    @State private var runnerCount: Int = 0
    @State private var stakesTimer: Timer? = nil

    private var setStakesScreen: some View {
        VStack(spacing: 28) {
            screenHeader(title: "Set the stakes.", subtitle: "Everyone puts in. Winner takes all.")

            Spacer().frame(height: 8)

            // Runner cascade — figures fade in one by one
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: "figure.run")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(i < runnerCount ? gold : Color.gray.opacity(0.12))
                        .scaleEffect(i < runnerCount ? 1.0 : 0.7)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.05), value: runnerCount)
                }
            }
            .frame(height: 44)
            .onAppear { startRunnerCascade() }
            .onDisappear { stakesTimer?.invalidate(); stakesTimer = nil }

            // Live math equation
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("$50")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                    Text("×")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.gray)
                    Text("\(max(1, runnerCount))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .contentTransition(.numericText())
                    Text("=")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.gray)
                    Text("$\(max(1, runnerCount) * 50)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(gold)
                        .contentTransition(.numericText())
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: runnerCount)

                Text("pot")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.gray)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gold.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(gold.opacity(0.25), lineWidth: 1))
            )

            Text("The more friends, the bigger the prize.")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.gray)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.8), value: screenAppeared)
        }
    }

    private func startRunnerCascade() {
        runnerCount = 0
        stakesTimer?.invalidate()
        var count = 0
        stakesTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { timer in
            count += 1
            withAnimation { runnerCount = count }
            if count >= 6 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { self.runnerCount = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.startRunnerCascade()
                    }
                }
            }
        }
    }

    // MARK: - Screen 5: "Your first $10 is on us."

    private var freeMatchScreen: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 20)

            Image(systemName: "gift.fill")
                .font(.system(size: 52))
                .foregroundStyle(gold)
                .scaleEffect(screenAppeared ? 1 : 0.5)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: screenAppeared)

            VStack(spacing: 8) {
                Text("Your first $10 is on us.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("No buy-in. No catch.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.gray)
            }
            .multilineTextAlignment(.center)
            .opacity(screenAppeared ? 1 : 0)
            .offset(y: screenAppeared ? 0 : 8)
            .animation(.easeOut(duration: 0.4).delay(0.2), value: screenAppeared)

            // Starter comp card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your First Mile")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Race · 1 mile · Free entry")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Text("$10")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(gold)
                    .shadow(color: gold.opacity(0.3), radius: 12, y: 6)
            )
            .opacity(screenAppeared ? 1 : 0)
            .offset(y: screenAppeared ? 0 : 15)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: screenAppeared)

            Text("Run 1 mile. Win $10. It's that simple.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(gold)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.6), value: screenAppeared)
        }
    }

    // MARK: - Screen 6: "Every mile tracked automatically."

    @State private var stravaBubbles: [Bool] = [false, false, false]

    private var stravaExplainerScreen: some View {
        VStack(spacing: 28) {
            screenHeader(title: "Every mile tracked automatically.", subtitle: "Link Strava and your GPS runs sync to all competitions. No manual logging.")

            Spacer().frame(height: 4)

            // Gold bubble cascade left to right
            HStack(spacing: 16) {
                stravaBubbleNode(icon: "play.fill", label: "Start on\nStrava", index: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(gold.opacity(stravaBubbles[0] ? 0.5 : 0))
                    .animation(.easeOut(duration: 0.3).delay(0.5), value: stravaBubbles[0])
                stravaBubbleNode(icon: "figure.run", label: "Run your\nroute", index: 1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(gold.opacity(stravaBubbles[1] ? 0.5 : 0))
                    .animation(.easeOut(duration: 0.3).delay(0.7), value: stravaBubbles[1])
                stravaBubbleNode(icon: "checkmark", label: "Miles sync\nto matches", index: 2)
            }

            // Steps text
            VStack(spacing: 10) {
                stravaLine(number: "1", text: "Start a run on Strava", index: 0)
                stravaLine(number: "2", text: "Run your route", index: 1)
                stravaLine(number: "3", text: "Miles sync to all competitions", index: 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(gold)
                Text("All runs must be started and stopped on Strava to count")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(gold)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(gold.opacity(0.08)))
            .opacity(screenAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.8), value: screenAppeared)
        }
        .onAppear { triggerStravaCascade() }
    }

    private func triggerStravaCascade() {
        stravaBubbles = [false, false, false]
        for i in 0..<3 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3 + Double(i) * 0.25)) {
                stravaBubbles[i] = true
            }
        }
    }

    private func stravaBubbleNode(icon: String, label: String, index: Int) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(gold)
                    .frame(width: 60, height: 60)
                    .shadow(color: gold.opacity(0.3), radius: 8, y: 3)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .scaleEffect(stravaBubbles[safe: index] == true ? 1 : 0.3)
        .opacity(stravaBubbles[safe: index] == true ? 1 : 0)
    }

    private func stravaLine(number: String, text: String, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(gold))
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.black)
            Spacer()
        }
        .opacity(cardStagger[safe: index] == true ? 1 : 0)
        .offset(x: cardStagger[safe: index] == true ? 0 : 15)
    }

    // MARK: - Screen 7: "Make it personal." (Daily Stakes)

    private var dailyStakesScreen: some View {
        VStack(spacing: 24) {
            screenHeader(title: "Make accountability cost.", subtitle: "Optional — put real money behind your daily goals.")

            // Two-panel visual: HIT vs MISS
            HStack(spacing: 12) {
                // HIT panel
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    Text("Hit your goal")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.black)
                    Text("Keep your\nmoney")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.green)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.green.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.green.opacity(0.2), lineWidth: 1))
                )

                // MISS panel
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.red)
                    }
                    Text("Miss your goal")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.black)
                    Text("$5 goes to\nyour friend")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.red.opacity(0.15), lineWidth: 1))
                )
            }
            .opacity(screenAppeared ? 1 : 0)
            .offset(y: screenAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: screenAppeared)

            // Example goal line
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(gold)
                Text("Example: 2.0 miles by 7:00 AM — $5 at stake")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.gray)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.gray.opacity(0.06)))

            VStack(spacing: 12) {
                animatedCard(index: 0) {
                    optionCard(title: "I want daily accountability", icon: "flame.fill",
                               isSelected: wantsDailyStakes == "yes") { wantsDailyStakes = "yes" }
                }
                animatedCard(index: 1) {
                    optionCard(title: "Just competitions for now", icon: "trophy",
                               isSelected: wantsDailyStakes == "no") { wantsDailyStakes = "no" }
                }
            }

            Text("You can always change this later.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Screen 8: Account

    private var accountScreen: some View {
        ZStack {
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
                        Button { showCreateAccountSheet = true } label: {
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

                        Button { showSignInSheet = true } label: {
                            Text("Sign In")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1)
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

    // MARK: - Screen 9: Connect Strava

    private var stravaConnectScreen: some View {
        ZStack {
            if !stravaConnected && !stravaJustLinked {
                StravaMotionLines(appeared: screenAppeared)
                    .offset(y: -80)
            }

            VStack(spacing: 28) {
                Spacer().frame(height: 12)

                if stravaConnected || stravaJustLinked {
                    VStack(spacing: 16) {
                        ZStack {
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

                    Text("This is how your miles count toward matches and goals. Link now or add it later in Profile.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.gray)
                        .multilineTextAlignment(.center)

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

    // MARK: - Screen 10: "Challenge your friends." (Final — styled like Start Your First Competition)

    private var challengeFriendsScreen: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)

            ZStack {
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

            Text("Challenge your friends.")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: screenAppeared)

            // Action buttons
            VStack(spacing: 12) {
                Button(action: handleCreateMatch) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create a Match")
                    }
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(gold)
                            .shadow(color: gold.opacity(0.3), radius: 8, y: 4)
                    )
                }
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: screenAppeared)

                Button(action: finishOnboarding) {
                    HStack(spacing: 8) {
                        Image(systemName: "ticket.fill")
                        Text("Join with a Code")
                    }
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: screenAppeared)

                Button(action: finishOnboarding) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.run")
                        Text("Run My Free $10 Race")
                    }
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(gold.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(gold.opacity(0.3), lineWidth: 1))
                    )
                }
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.5), value: screenAppeared)
            }

            Button(action: finishOnboarding) {
                Text("Skip — I'll explore first")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.gray)
            }
            .padding(.top, 4)
            .opacity(screenAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.7), value: screenAppeared)
        }
    }

    // MARK: - Reusable Components

    private func screenHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .opacity(screenAppeared ? 1 : 0)
                .offset(y: screenAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.4), value: screenAppeared)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.gray)
                    .opacity(screenAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: screenAppeared)
            }
        }
    }

    private func animatedCard<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(cardStagger[safe: index] == true ? 1 : 0)
            .offset(y: cardStagger[safe: index] == true ? 0 : 12)
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

// MARK: - Clock Face (Deadline)

struct ClockFace: View {
    let hour: Int
    let gold: Color
    @State private var secondTick: Int = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.15), lineWidth: 2)
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1.5, height: i % 3 == 0 ? 6 : 3)
                    .offset(y: -22)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.red.opacity(0.5))
                .frame(width: 1, height: 20)
                .offset(y: -10)
                .rotationEffect(.degrees(Double(secondTick) * 6))
                .animation(.easeOut(duration: 0.15), value: secondTick)
            RoundedRectangle(cornerRadius: 1)
                .fill(gold)
                .frame(width: 2.5, height: 14)
                .offset(y: -7)
                .rotationEffect(.degrees(Double(hour % 12) * 30))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: hour)
            Circle().fill(gold).frame(width: 5, height: 5)
        }
        .onAppear { startTicking() }
    }

    private func startTicking() {
        Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { _ in
            secondTick = (secondTick + 1) % 60
        }
    }
}

// MARK: - Triangle Shape (Arrow Tip)

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
