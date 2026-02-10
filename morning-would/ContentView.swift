import SwiftUI
import AVFoundation
import Vision
import StripePaymentSheet
import ContactsUI
import Combine

// MARK: - Shared Objective Settings (Observable)

/// Shared state for objective settings that syncs with UserDefaults
/// Used by ContentView and ObjectiveSettingsView to ensure immediate UI updates
class ObjectiveSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    
    @Published var pushupsEnabled: Bool {
        didSet { defaults.set(pushupsEnabled, forKey: "pushupsEnabled") }
    }
    @Published var pushupsIsSet: Bool {
        didSet { defaults.set(pushupsIsSet, forKey: "pushupsIsSet") }
    }
    @Published var runEnabled: Bool {
        didSet { defaults.set(runEnabled, forKey: "runEnabled") }
    }
    @Published var runIsSet: Bool {
        didSet { defaults.set(runIsSet, forKey: "runIsSet") }
    }
    @Published var runDistance: Double {
        didSet { defaults.set(runDistance, forKey: "runDistance") }
    }
    @Published var scheduleIsSet: Bool {
        didSet { defaults.set(scheduleIsSet, forKey: "scheduleIsSet") }
    }
    
    init() {
        // Load from UserDefaults with sensible defaults
        // Note: bool(forKey:) returns false if key doesn't exist, so we check object(forKey:) first
        self.pushupsEnabled = defaults.object(forKey: "pushupsEnabled") != nil 
            ? defaults.bool(forKey: "pushupsEnabled") : true
        self.pushupsIsSet = defaults.bool(forKey: "pushupsIsSet")
        self.runEnabled = defaults.bool(forKey: "runEnabled")
        self.runIsSet = defaults.bool(forKey: "runIsSet")
        self.runDistance = defaults.object(forKey: "runDistance") != nil 
            ? defaults.double(forKey: "runDistance") : 2.0
        self.scheduleIsSet = defaults.bool(forKey: "scheduleIsSet")
    }
    
    /// Refresh all values from UserDefaults (call after external updates like sign-in)
    func refreshFromDefaults() {
        pushupsEnabled = defaults.object(forKey: "pushupsEnabled") != nil 
            ? defaults.bool(forKey: "pushupsEnabled") : true
        pushupsIsSet = defaults.bool(forKey: "pushupsIsSet")
        runEnabled = defaults.bool(forKey: "runEnabled")
        runIsSet = defaults.bool(forKey: "runIsSet")
        runDistance = defaults.object(forKey: "runDistance") != nil 
            ? defaults.double(forKey: "runDistance") : 2.0
        scheduleIsSet = defaults.bool(forKey: "scheduleIsSet")
    }
}

// MARK: - Main content view

struct ContentView: View {
    // Shared objective settings (observable for immediate UI updates)
    @StateObject private var objectiveSettings = ObjectiveSettings()
    
    @AppStorage("hasCompletedTodayPushUps") private var hasCompletedTodayPushUps: Bool = false
    @AppStorage("todayPushUpCount") private var todayPushUpCount: Int = 0
    @AppStorage("pushupObjective") private var pushupObjective: Int = 10
    @AppStorage("objectiveDeadline") private var objectiveDeadline: Date = {
        let components = DateComponents(hour: 22, minute: 0)
        return Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? Date()
    }()
    @AppStorage("scheduleType") private var scheduleType: String = "Daily"
    @AppStorage("settingsLockedUntil") private var settingsLockedUntil: Date = Date.distantPast
    @AppStorage("profileUsername") private var profileUsername: String = ""
    @AppStorage("profileEmail") private var profileEmail: String = ""
    @AppStorage("profileCompleted") private var profileCompleted: Bool = false
    @AppStorage("userId") private var userId: String = ""
    
    // Today's progress tracking
    @AppStorage("todayRunDistance") private var todayRunDistance: Double = 0.0
    @AppStorage("hasCompletedTodayRun") private var hasCompletedTodayRun: Bool = false

    @State private var showObjectiveSettings = false
    @State private var showProfileView = false
    @State private var showPushUpSession = false
    @State private var currentTime = Date() // For live countdown
    
    // Timer for live countdown updates
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let notificationManager = NotificationManager()
    
    // Computed: Check if any objective is enabled
    private var hasAnyObjective: Bool {
        objectiveSettings.pushupsEnabled || objectiveSettings.runEnabled
    }
    
    // Computed: Check if pushup objective met
    private var pushupObjectiveMet: Bool {
        todayPushUpCount >= pushupObjective
    }
    
    // Computed: Check if run objective met
    private var runObjectiveMet: Bool {
        todayRunDistance >= objectiveSettings.runDistance
    }
    
    // Computed: Are ALL enabled objectives met?
    private var allObjectivesMet: Bool {
        let pushupsMet = !objectiveSettings.pushupsEnabled || pushupObjectiveMet
        let runMet = !objectiveSettings.runEnabled || runObjectiveMet
        return pushupsMet && runMet
    }

    var isWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    var shouldShowObjective: Bool {
        if scheduleType == "Weekdays" && isWeekend {
            return false
        }
        return true
    }

    var objectiveMet: Bool {
        allObjectivesMet
    }
    
    // Header text based on what's enabled
    private var goalsHeaderText: String {
        if objectiveSettings.pushupsEnabled && objectiveSettings.runEnabled {
            return "Today's Goals"
        } else if objectiveSettings.pushupsEnabled {
            return "Today's Goal: \(pushupObjective) Pushups"
        } else if objectiveSettings.runEnabled {
            return "Today's Goal: \(String(format: "%.1f", objectiveSettings.runDistance)) Mile Run"
        } else {
            return "Today's Goals"
        }
    }

    var timeUntilDeadline: String {
        if !shouldShowObjective {
            return "No objective today"
        }

        // Check if objective is already met
        if objectiveMet {
            return "✓ Completed"
        }

        let todayDeadline = combineDateWithTodayTime(objectiveDeadline)
        let timeInterval = todayDeadline.timeIntervalSince(currentTime)

        if timeInterval <= 0 {
            return "⚠️ Deadline passed"
        }

        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        let seconds = Int(timeInterval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s remaining"
        } else {
            return "\(seconds)s remaining"
        }
    }

    private func combineDateWithTodayTime(_ time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())

        var combined = DateComponents()
        combined.year = todayComponents.year
        combined.month = todayComponents.month
        combined.day = todayComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute

        return calendar.date(from: combined) ?? Date()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("EOS")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.black, Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.top, 30)

                    VStack(spacing: 20) {
                        // Goals Header
                        Text(goalsHeaderText)
                                .font(.system(.title3, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.black)
                            .padding(.horizontal)

                        // Objectives Card(s)
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                            VStack(spacing: 16) {
                                // Show both objectives or single based on what's enabled
                                if objectiveSettings.pushupsEnabled && objectiveSettings.runEnabled {
                                    // BOTH objectives enabled - split view
                                    HStack(spacing: 20) {
                                        // Pushups column
                                        VStack(spacing: 8) {
                                            Image(systemName: "figure.strengthtraining.traditional")
                                                .font(.title2)
                                                .foregroundStyle(pushupObjectiveMet ? Color.green : Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                                Text("\(todayPushUpCount)")
                                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                                    .foregroundStyle(Color.black)
                                                Text("/\(pushupObjective)")
                                                    .font(.system(size: 18, weight: .light, design: .rounded))
                                                    .foregroundStyle(Color.black.opacity(0.4))
                                            }
                                            Text("pushups")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.black.opacity(0.5))
                                            Circle()
                                                .fill(pushupObjectiveMet ? Color.green : Color.red.opacity(0.6))
                                                .frame(width: 8, height: 8)
                                        }
                                        .frame(maxWidth: .infinity)
                                        
                                        // Divider
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 1, height: 80)
                                        
                                        // Run column
                                        VStack(spacing: 8) {
                                            Image(systemName: "figure.run")
                                                .font(.title2)
                                                .foregroundStyle(runObjectiveMet ? Color.green : Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                                Text(String(format: "%.1f", todayRunDistance))
                                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                                    .foregroundStyle(Color.black)
                                                Text(String(format: "/%.1f", objectiveSettings.runDistance))
                                                    .font(.system(size: 18, weight: .light, design: .rounded))
                                                    .foregroundStyle(Color.black.opacity(0.4))
                                            }
                                            Text("miles")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.black.opacity(0.5))
                                            Circle()
                                                .fill(runObjectiveMet ? Color.green : Color.red.opacity(0.6))
                                                .frame(width: 8, height: 8)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .padding(.top, 8)
                                } else if objectiveSettings.pushupsEnabled {
                                    // Only pushups
                                    HStack {
                                        Text("\(todayPushUpCount)")
                                            .font(.system(size: 72, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.black)
                                        Text("/ \(pushupObjective)")
                                            .font(.system(size: 36, weight: .light, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.4))
                                    }
                                } else if objectiveSettings.runEnabled {
                                    // Only run
                                    HStack {
                                        Text(String(format: "%.1f", todayRunDistance))
                                            .font(.system(size: 72, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.black)
                                        Text(String(format: "/ %.1f mi", objectiveSettings.runDistance))
                                            .font(.system(size: 36, weight: .light, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.4))
                                    }
                                } else {
                                    // No objectives set
                                    VStack(spacing: 8) {
                                        Image(systemName: "target")
                                            .font(.largeTitle)
                                            .foregroundStyle(Color.gray)
                                        Text("No objectives set")
                                            .font(.system(.headline, design: .rounded))
                                            .foregroundStyle(Color.gray)
                                        Text("Tap 'My Objective' to get started")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.gray.opacity(0.7))
                                    }
                                    .padding(.vertical, 20)
                                }

                                // Status indicator (when objectives exist)
                                if shouldShowObjective && hasAnyObjective {
                                        HStack {
                                            Circle()
                                            .fill(allObjectivesMet ? Color.green : Color.red.opacity(0.8))
                                                .frame(width: 10, height: 10)
                                        Text(allObjectivesMet ? "All objectives met" : "Objectives not met")
                                                .font(.system(.subheadline, design: .rounded))
                                            .foregroundStyle(allObjectivesMet ? Color.green : Color.red.opacity(0.8))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                            .fill((allObjectivesMet ? Color.green : Color.red).opacity(0.1))
                                    )
                                }

                                // Timer section
                                VStack(spacing: 4) {
                                    Text(timeUntilDeadline)
                                        .font(.system(.title3, design: .rounded, weight: .semibold))
                                        .foregroundStyle(
                                            !shouldShowObjective ? Color.gray :
                                            (allObjectivesMet ? Color.green :
                                            (combineDateWithTodayTime(objectiveDeadline).timeIntervalSince(currentTime) <= 0 ? Color.red :
                                            Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))))
                                        )
                                    if shouldShowObjective && hasAnyObjective {
                                        let deadline = combineDateWithTodayTime(objectiveDeadline)
                                        Text("Deadline: \(deadline, style: .time)")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.5))
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: 350)
                        .padding(.horizontal)

                        // Action button - show pushup session if pushups enabled
                        if objectiveSettings.pushupsEnabled {
                        Button(action: {
                            showPushUpSession = true
                        }) {
                            HStack {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.title2)
                                Text("Start Pushup Session")
                                    .font(.system(.headline, design: .rounded))
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: 300)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)),
                                                Color(UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1))
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .shadow(color: Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 0.3)), radius: 10, x: 0, y: 5)
                            }
                        }

                        HStack(spacing: 15) {
                            Button(action: {
                                showObjectiveSettings = true
                            }) {
                                HStack {
                                    Image(systemName: "target")
                                    Text("My Objective")
                                }
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.white)
                                        )
                                )
                            }

                            Button(action: {
                                showProfileView = true
                            }) {
                                HStack {
                                    Image(systemName: "person.circle")
                                    Text("Profile")
                                    if !profileCompleted {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.white)
                                        )
                                )
                            }
                        }
                    }

                    Spacer()
                }
            }
            .sheet(isPresented: $showPushUpSession) {
                PushUpSessionView(todayPushUpCount: $todayPushUpCount, objective: pushupObjective)
            }
            .sheet(isPresented: $showObjectiveSettings) {
                ObjectiveSettingsView(
                    settings: objectiveSettings,
                    objective: $pushupObjective,
                    deadline: $objectiveDeadline,
                    scheduleType: $scheduleType,
                    settingsLockedUntil: $settingsLockedUntil,
                    onSave: {
                        syncObjectivesToBackend()
                    }
                )
            }
            .sheet(isPresented: $showProfileView) {
                ProfileView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkAndResetDaily()
        }
        .onAppear {
            checkAndResetDaily()
            notificationManager.requestPermissions()
            if shouldShowObjective && !objectiveMet {
                notificationManager.scheduleObjectiveReminder(
                    deadline: objectiveDeadline,
                    objective: pushupObjective,
                    scheduleType: scheduleType
                )
            }
        }
        .onReceive(countdownTimer) { time in
            currentTime = time
        }
    }

    private func checkAndResetDaily() {
        let lastResetKey = "lastDailyReset"
        let lastReset = UserDefaults.standard.object(forKey: lastResetKey) as? Date ?? Date.distantPast
        let calendar = Calendar.current

        if !calendar.isDateInToday(lastReset) {
            hasCompletedTodayPushUps = false
            todayPushUpCount = 0
            UserDefaults.standard.set(Date(), forKey: lastResetKey)
        }
        
        // Also sync lock state from server (in case it was reset after missed objective)
        syncLockStateFromServer()
    }
    
    private func syncLockStateFromServer() {
        guard !userId.isEmpty else { 
            print("⚠️ syncLockState: No userId, skipping")
            return 
        }
        
        guard let url = URL(string: "https://api.live-eos.com/users/\(userId)/settings-lock") else { 
            print("❌ syncLockState: Invalid URL")
            return 
        }
        
        print("🔄 Syncing lock state from server for user: \(userId)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ syncLockState error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ syncLockState: No HTTP response")
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ syncLockState: HTTP \(httpResponse.statusCode)")
                return
            }
            
            guard let data = data else {
                print("❌ syncLockState: No data")
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ syncLockState: JSON parse failed")
                return
            }
            
            DispatchQueue.main.async {
                if let lockDateStr = json["settings_locked_until"] as? String, !lockDateStr.isEmpty {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    
                    if let lockDate = isoFormatter.date(from: lockDateStr) {
                        print("🔒 Lock synced: \(lockDate)")
                        self.settingsLockedUntil = lockDate
                    } else {
                        // Try without fractional seconds
                        isoFormatter.formatOptions = [.withInternetDateTime]
                        if let lockDate = isoFormatter.date(from: lockDateStr) {
                            print("🔒 Lock synced: \(lockDate)")
                            self.settingsLockedUntil = lockDate
                        } else {
                            print("⚠️ Could not parse lock date: \(lockDateStr)")
                        }
                    }
                } else {
                    // No lock date or null means unlocked
                    print("🔓 Lock cleared (server returned null)")
                    self.settingsLockedUntil = Date.distantPast
                }
            }
        }.resume()
    }
    
    private func syncObjectivesToBackend() {
        guard !userId.isEmpty else {
            print("⚠️ No userId, skipping objective sync")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let deadlineString = formatter.string(from: objectiveDeadline)
        
        // ISO8601 formatter for lock date
        let isoFormatter = ISO8601DateFormatter()
        let lockDateString = settingsLockedUntil > Date.distantPast ? isoFormatter.string(from: settingsLockedUntil) : nil
        
        // Get objective type from storage
        let objType = UserDefaults.standard.string(forKey: "objectiveType") ?? "pushups"
        
        var body: [String: Any] = [
            "objective_type": objType,
            "objective_count": pushupObjective,
            "objective_schedule": scheduleType.lowercased(),
            "objective_deadline": deadlineString
        ]
        
        if let lockDate = lockDateString {
            body["settings_locked_until"] = lockDate
        }
        
        guard let url = URL(string: "/objectives/settings/\(userId)", relativeTo: URL(string: "https://api.live-eos.com")!) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Objective sync error: \(error)")
                return
            }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                print("✅ Objectives synced to backend (type: \(objType))")
            }
        }.resume()
    }
}

// MARK: - Push-up session view

struct PushUpSessionView: View {
    @Binding var todayPushUpCount: Int
    let objective: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraViewModel = CameraViewModel()
    @State private var sessionCount = 0
    @State private var isStaging = true
    @State private var showCompletionBanner = false
    @AppStorage("userId") private var userId: String = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = cameraViewModel.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                        .scaleEffect(x: -1, y: 1)
                }

                VStack {
                    Spacer()

                    if isStaging {
                        VStack(spacing: 20) {
                            Text("Position yourself in frame")
                                .font(.system(.title2, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.white)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(Color.black.opacity(0.7))
                                )

                            Button(action: {
                                isStaging = false
                                cameraViewModel.startTracking()
                            }) {
                                Text("Press to begin count")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 25)
                                            .fill(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    )
                            }
                        }
                        .padding(.bottom, 100)
                    } else {
                        VStack(spacing: 10) {
                            Text("Pushups")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.white)

                            Text("\(cameraViewModel.pushupCount)")
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)

                            if cameraViewModel.pushupCount >= objective {
                                Text("Pushups complete!")
                                    .font(.system(.title3, design: .rounded, weight: .medium))
                                    .foregroundStyle(Color.green)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(Color.black.opacity(0.7))
                                    )
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.7))
                        )
                        .padding(.bottom, 100)
                    }
                }

                if showCompletionBanner {
                    VStack {
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.green)

                            Text("Great job!")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.white)

                            Text("You completed \(cameraViewModel.pushupCount) pushups")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.9))

                            Button(action: {
                                let newCount = todayPushUpCount + cameraViewModel.pushupCount
                                todayPushUpCount = newCount
                                syncPushupProgress(count: newCount)
                                dismiss()
                            }) {
                                Text("Done")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 50)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 25)
                                            .fill(Color.white)
                                    )
                            }
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.black.opacity(0.95))
                        )
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .topTrailing) {
                Button(action: {
                    if cameraViewModel.pushupCount > 0 {
                        showCompletionBanner = true
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(Color.white)
                        .padding()
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.5))
                        )
                }
                .padding()
            }
        }
        .onAppear {
            cameraViewModel.startSession()
        }
        .onDisappear {
            cameraViewModel.stopSession()
        }
    }
    
    private func syncPushupProgress(count: Int) {
        guard !userId.isEmpty else {
            print("⚠️ No userId, skipping pushup sync")
            return
        }
        
        let body: [String: Any] = [
            "completedCount": count,
            "objectiveType": "pushups"  // Multi-objective support
        ]
        
        guard let url = URL(string: "https://api.live-eos.com/objectives/complete/\(userId)") else {
            print("⚠️ Invalid URL for pushup sync")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Pushup sync error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✅ Pushup progress synced: \(count)")
                } else {
                    print("⚠️ Pushup sync status: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}

// MARK: - Objective settings view

struct ObjectiveSettingsView: View {
    // Shared settings (observable - changes here immediately update ContentView)
    @ObservedObject var settings: ObjectiveSettings
    
    @Binding var objective: Int
    @Binding var deadline: Date
    @Binding var scheduleType: String
    @Binding var settingsLockedUntil: Date
    var onSave: (() -> Void)? = nil  // Callback to sync to backend
    @Environment(\.dismiss) private var dismiss
    
    // Temp editing states - use @AppStorage to persist between view opens
    @AppStorage("tempPushupCount") private var tempPushupCount: Int = 50
    @AppStorage("tempRunDistance") private var tempRunDistance: Double = 2.0
    @AppStorage("tempScheduleType") private var tempScheduleType: String = "Daily"
    @State private var tempDeadline: Date = Date()
    @State private var lockDays: Double = 7
    
    // Track if we've initialized from bindings
    @State private var hasInitializedFromBindings: Bool = false
    
    // Dropdown expansion states
    @State private var isObjectiveExpanded: Bool = true
    @State private var isScheduleExpanded: Bool = true
    @State private var isLockExpanded: Bool = false
    
    // Saving states
    @State private var isSavingPushups: Bool = false
    @State private var isSavingRun: Bool = false
    @State private var isSavingSchedule: Bool = false
    
    // Alerts
    @State private var showLockConfirmation: Bool = false
    @State private var showStravaRequiredAlert: Bool = false
    
    // Success feedback
    @State private var showSuccessBanner: Bool = false
    @State private var successMessage: String = "Saved!"
    
    // Strava connection check
    @AppStorage("stravaConnected") private var stravaConnected: Bool = false
    @AppStorage("userId") private var userId: String = ""

    private let notificationManager = NotificationManager()
    private let goldColor = Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
    
    var isLocked: Bool {
        settingsLockedUntil > Date()
    }
    
    var daysUntilUnlock: Int {
        let interval = settingsLockedUntil.timeIntervalSince(Date())
        return max(0, Int(ceil(interval / 86400)))
    }
    
    var lockTimeRemaining: String {
        let interval = settingsLockedUntil.timeIntervalSince(Date())
        if interval <= 0 { return "Unlocked" }
        
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours >= 24 {
            let days = Int(ceil(interval / 86400))
            return "\(days) day\(days == 1 ? "" : "s") left"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else {
            return "\(minutes)m left"
        }
    }
    
    var formattedDeadlineTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: tempDeadline)
    }
    
    var objectiveSummary: String {
        var parts: [String] = []
        if settings.pushupsIsSet {
            parts.append("\(tempPushupCount) pushups")
        }
        if settings.runIsSet {
            parts.append(String(format: "%.1f mi", tempRunDistance))
        }
        if parts.isEmpty {
            return "Not Set"
        }
        return parts.joined(separator: " + ")
    }
    
    var hasAnyObjectiveSet: Bool {
        settings.pushupsIsSet || settings.runIsSet
    }
    
    var scheduleSummary: String {
        let scheduleText = tempScheduleType == "Daily" ? "Daily" : "Weekdays"
        return "\(scheduleText) @ \(formattedDeadlineTime)"
    }
    
    // MARK: - Extracted Subviews (fixes compiler type-check timeout)
    
    @ViewBuilder
    private var pushupsRowView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18))
                    .foregroundStyle(goldColor)
                Text("Pushups")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.black)
                Spacer()
                if settings.pushupsIsSet {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Target")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                    
                    Menu {
                        ForEach([10, 15, 20, 25, 30, 40, 50, 60, 75, 100], id: \.self) { count in
                            Button("\(count) pushups") { tempPushupCount = count }
                        }
                    } label: {
                        HStack {
                            Text("\(tempPushupCount)")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    if settings.pushupsIsSet { unsetPushups() } else { setPushups() }
                }) {
                    HStack(spacing: 4) {
                        if isSavingPushups {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(settings.pushupsIsSet ? "Unset" : "Set")
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(settings.pushupsIsSet ? Color.red : Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(settings.pushupsIsSet ? Color.red.opacity(0.1) : goldColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.pushupsIsSet ? Color.red : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSavingPushups)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(settings.pushupsIsSet ? Color.green.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var runRowView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.system(size: 18))
                    .foregroundStyle(stravaConnected ? goldColor : Color.gray)
                Text("Run")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                if settings.runIsSet {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Distance")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                    
                    Menu {
                        ForEach([0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0], id: \.self) { miles in
                            Button(String(format: "%.1f miles", miles)) { tempRunDistance = miles }
                        }
                    } label: {
                        HStack {
                            Text(String(format: "%.1f mi", tempRunDistance))
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(stravaConnected ? Color.black : Color.gray)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(!stravaConnected)
                }
                
                Spacer()
                
                Button(action: {
                    if !stravaConnected {
                        showStravaRequiredAlert = true
                        return
                    }
                    if settings.runIsSet { unsetRun() } else { setRun() }
                }) {
                    HStack(spacing: 4) {
                        if isSavingRun {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(settings.runIsSet ? "Unset" : "Set")
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(settings.runIsSet ? Color.red : (stravaConnected ? Color.white : Color.gray))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(settings.runIsSet ? Color.red.opacity(0.1) : (stravaConnected ? goldColor : Color.gray.opacity(0.3))))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.runIsSet ? Color.red : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSavingRun)
            }
            
            if !stravaConnected {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Connect Strava in Profile → Account to track runs")
                        .font(.system(.caption2, design: .rounded))
                }
                .foregroundStyle(Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(settings.runIsSet ? Color.green.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .opacity(stravaConnected ? 1 : 0.7)
    }
    
    // Check if schedule has been changed from saved values
    private var scheduleHasChanges: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let currentTime = formatter.string(from: tempDeadline)
        let savedTime = formatter.string(from: deadline)
        return currentTime != savedTime || tempScheduleType.lowercased() != scheduleType.lowercased()
    }
    
    private var scheduleButtonText: String {
        if isSavingSchedule { return "" }
        if !settings.scheduleIsSet { return "Set" }
        if scheduleHasChanges { return "Update" }
        return "Unset"
    }
    
    private var scheduleButtonColor: Color {
        if !settings.scheduleIsSet { return goldColor }
        if scheduleHasChanges { return goldColor }
        return Color.red.opacity(0.1)
    }
    
    private var scheduleButtonTextColor: Color {
        if !settings.scheduleIsSet { return Color.white }
        if scheduleHasChanges { return Color.white }
        return Color.red
    }
    
    @ViewBuilder
    private var scheduleContentView: some View {
                        VStack(spacing: 16) {
                            Picker("", selection: $tempScheduleType) {
                                Text("Daily").tag("Daily")
                Text("Weekdays").tag("Weekdays")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deadline Time")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                    
                    DatePicker("", selection: $tempDeadline, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(goldColor)
                }
                
                Spacer()
                
                Button(action: {
                    if !settings.scheduleIsSet || scheduleHasChanges {
                        // Set or Update
                        setSchedule()
                    } else {
                        // Unset
                        unsetSchedule()
                    }
                }) {
                    HStack(spacing: 4) {
                        if isSavingSchedule {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(scheduleButtonText)
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(scheduleButtonTextColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(scheduleButtonColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(scheduleButtonTextColor == Color.red ? Color.red : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSavingSchedule)
                            }
                            
                            Text(tempScheduleType == "Daily" ? "Complete every day" : "Complete Monday through Friday")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var lockSectionHeader: some View {
        Button(action: { 
            if !isLocked {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLockExpanded.toggle()
                }
            }
        }) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isLocked ? Color.orange : goldColor)
                
                Text("Commitment Lock")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.black)
                
                Spacer()
                
                if isLocked {
                    Text(lockTimeRemaining)
                                .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.orange)
                } else {
                    Text("Unlocked")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.gray)
                }
                
                Image(systemName: isLockExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.5))
            }
                                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked ? 0.6 : 1)
    }
    
    @ViewBuilder
    private var lockContentView: some View {
        VStack(spacing: 16) {
            // Quick Lock - until next deadline
            Button(action: { lockUntilNextDeadline() }) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(goldColor)
                    Text("Lock until next deadline")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    Spacer()
                    Text(nextDeadlineDescription)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.black.opacity(0.3))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(!hasAnyObjectiveSet || !settings.scheduleIsSet)
            .opacity((!hasAnyObjectiveSet || !settings.scheduleIsSet) ? 0.5 : 1)
            
            // Divider
            HStack {
                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                Text("or")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.gray)
                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
            }
            
            // Extended Lock
            Text("\(Int(lockDays)) day\(Int(lockDays) == 1 ? "" : "s")")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(goldColor)
            
            Slider(value: $lockDays, in: 1...30, step: 1)
                .tint(goldColor)
            
            Button(action: { showLockConfirmation = true }) {
                HStack {
                    Image(systemName: "lock.fill")
                    Text("Lock for \(Int(lockDays)) day\(Int(lockDays) == 1 ? "" : "s")")
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(goldColor))
            }
            .buttonStyle(.plain)
            .disabled(!hasAnyObjectiveSet || !settings.scheduleIsSet)
            .opacity((!hasAnyObjectiveSet || !settings.scheduleIsSet) ? 0.5 : 1)
            
            if !hasAnyObjectiveSet || !settings.scheduleIsSet {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("Set at least one objective and schedule first")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.top, 8)
    }
    
    // Helper: Description of next deadline for Quick Lock button
    private var nextDeadlineDescription: String {
        let now = Date()
        let calendar = Calendar.current
        
        // Combine today's date with the deadline time
        let deadlineComponents = calendar.dateComponents([.hour, .minute], from: tempDeadline)
        var nextDeadline = calendar.date(bySettingHour: deadlineComponents.hour ?? 9,
                                          minute: deadlineComponents.minute ?? 0,
                                          second: 0, of: now) ?? now
        
        // If deadline already passed today, use tomorrow's
        if nextDeadline <= now {
            nextDeadline = calendar.date(byAdding: .day, value: 1, to: nextDeadline) ?? nextDeadline
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeStr = formatter.string(from: nextDeadline)
        
        if calendar.isDateInToday(nextDeadline) {
            return "Today \(timeStr)"
        } else if calendar.isDateInTomorrow(nextDeadline) {
            return "Tomorrow \(timeStr)"
        } else {
            formatter.dateFormat = "EEE h:mm a"
            return formatter.string(from: nextDeadline)
        }
    }
    
    // Manual sync lock state from server
    private func syncLockFromServer() {
        guard !userId.isEmpty else { return }
        
        guard let url = URL(string: "https://api.live-eos.com/users/\(userId)/settings-lock") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            DispatchQueue.main.async {
                if let lockDateStr = json["settings_locked_until"] as? String, !lockDateStr.isEmpty {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let lockDate = isoFormatter.date(from: lockDateStr) {
                        self.settingsLockedUntil = lockDate
                    } else {
                        isoFormatter.formatOptions = [.withInternetDateTime]
                        if let lockDate = isoFormatter.date(from: lockDateStr) {
                            self.settingsLockedUntil = lockDate
                        }
                    }
                } else {
                    // Server says unlocked
                    self.settingsLockedUntil = Date.distantPast
                }
            }
        }.resume()
    }
    
    // Quick lock until next deadline
    private func lockUntilNextDeadline() {
        let now = Date()
        let calendar = Calendar.current
        
        // Combine today's date with the deadline time
        let deadlineComponents = calendar.dateComponents([.hour, .minute], from: tempDeadline)
        var nextDeadline = calendar.date(bySettingHour: deadlineComponents.hour ?? 9,
                                          minute: deadlineComponents.minute ?? 0,
                                          second: 0, of: now) ?? now
        
        // If deadline already passed today, use tomorrow's
        if nextDeadline <= now {
            nextDeadline = calendar.date(byAdding: .day, value: 1, to: nextDeadline) ?? nextDeadline
        }
        
        // Set lock to next deadline
        settingsLockedUntil = nextDeadline
        syncLockToBackend()
        dismiss()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                Form {
                    // Lock Status Banner (when locked)
                    if isLocked {
                        Section {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(Color.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Settings Locked")
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                        .foregroundStyle(Color.black)
                                    Text(lockTimeRemaining)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.7))
                                }
                                Spacer()
                        }
                        .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.orange.opacity(0.15))
                    }
                    
                    // MARK: - Objectives Section (Both Types)
                    Section {
                        // Header row (always visible) - uses onTapGesture to avoid Form button tap bleed
                        HStack {
                            Image(systemName: "target")
                                .font(.system(size: 16))
                                .foregroundStyle(goldColor)
                            
                            Text("Objectives")
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.black)
                            
                            Spacer()
                            
                            if !isObjectiveExpanded {
                                Text(objectiveSummary)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(hasAnyObjectiveSet ? Color.green : Color.orange)
                            }
                            
                            Image(systemName: isObjectiveExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(Color.black.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                        .opacity(isLocked ? 0.6 : 1)
                        .onTapGesture {
                            if !isLocked {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isObjectiveExpanded.toggle()
                                }
                            }
                        }
                        
                        // Expanded content - BOTH objective types
                        if isObjectiveExpanded && !isLocked {
                            VStack(spacing: 20) {
                                pushupsRowView
                                Divider()
                                runRowView
                                
                                if settings.pushupsIsSet && settings.runIsSet {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle")
                                            .font(.caption2)
                                        Text("Both objectives must be completed daily to succeed")
                                            .font(.system(.caption2, design: .rounded))
                                    }
                                    .foregroundStyle(Color.blue)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .listRowBackground(Color.white)

                    // MARK: - Schedule & Deadline Section
                    Section {
                        // Header row
                        Button(action: { 
                            if !isLocked {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isScheduleExpanded.toggle()
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "clock")
                                    .font(.system(size: 16))
                                    .foregroundStyle(goldColor)
                                
                                Text("Schedule & Deadline")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                    .foregroundStyle(Color.black)
                                
                                Spacer()
                                
                                if !isScheduleExpanded {
                                    Text(settings.scheduleIsSet ? scheduleSummary : "Not Set")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(settings.scheduleIsSet ? Color.green : Color.orange)
                                }
                                
                                Image(systemName: isScheduleExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(Color.black.opacity(0.5))
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.6 : 1)
                        
                        // Expanded content
                        if isScheduleExpanded && !isLocked {
                            scheduleContentView
                        }
                    }
                    .listRowBackground(Color.white)
                    
                    // MARK: - Commitment Lock Section
                    Section {
                        // Header row
                        lockSectionHeader
                        
                        // Expanded content
                        if isLockExpanded && !isLocked {
                            lockContentView
                        }
                    }
                    .listRowBackground(Color.white)

                    // Footer
                    Section(footer: Text("You'll receive a notification if you haven't completed your objectives by the deadline. Miss any set objective = day failed.")
                        .foregroundStyle(Color.white.opacity(0.95))) {
                        EmptyView()
                    }
                }
                .scrollContentBackground(.hidden)
                .tint(goldColor)
            }
            .navigationTitle("My Objective")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                }
            }
            .alert("Lock Your Settings?", isPresented: $showLockConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Lock for \(Int(lockDays)) Days", role: .destructive) {
                    // Set lock expiry
                    settingsLockedUntil = Calendar.current.date(byAdding: .day, value: Int(lockDays), to: Date()) ?? Date()
                    syncLockToBackend()
                    dismiss()
                }
            } message: {
                Text("Are you sure? You will NOT be able to change your objective settings or back out of your commitment for \(Int(lockDays)) days.")
            }
            .alert("Strava Required", isPresented: $showStravaRequiredAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Connect Strava in your Profile to track run objectives. Go to Profile → Account → Strava.")
            }
            .overlay(alignment: .top) {
                if showSuccessBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.white)
                        Text(successMessage)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.green)
                            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
                    )
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showSuccessBanner = false
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Initialize temp values from bindings on first load
            if !hasInitializedFromBindings {
                tempDeadline = deadline
                tempPushupCount = max(objective, tempPushupCount)  // Use higher of binding or persisted
                hasInitializedFromBindings = true
            }
            loadObjectivesFromBackend()
        }
    }
    
    // MARK: - Backend Sync Functions
    
    private func showSuccess(_ message: String = "Saved!") {
        successMessage = message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showSuccessBanner = true
        }
    }
    
    private func setPushups() {
        isSavingPushups = true
        print("💪 Setting pushups: \(tempPushupCount), userId: \(userId)")
        
        let body: [String: Any] = [
            "pushups_count": tempPushupCount,
            "pushups_enabled": true
        ]
        
        saveObjectiveToBackend(body: body) { success in
            DispatchQueue.main.async {
                self.isSavingPushups = false
                if success {
                    self.settings.pushupsIsSet = true
                    self.settings.pushupsEnabled = true
                    self.objective = self.tempPushupCount
                    self.showSuccess("Pushups set!")
                    self.onSave?()
                    print("✅ Pushups set successfully")
                } else {
                    print("❌ Failed to set pushups")
                }
            }
        }
    }
    
    private func unsetPushups() {
        isSavingPushups = true
        print("💪 Unsetting pushups, userId: \(userId)")
        
        let body: [String: Any] = [
            "pushups_enabled": false
        ]
        
        saveObjectiveToBackend(body: body) { success in
            DispatchQueue.main.async {
                self.isSavingPushups = false
                if success {
                    self.settings.pushupsIsSet = false
                    self.settings.pushupsEnabled = false
                    self.showSuccess("Pushups removed")
                    print("✅ Pushups unset successfully")
                } else {
                    print("❌ Failed to unset pushups")
                }
            }
        }
    }
    
    private func setRun() {
        isSavingRun = true
        print("🏃 Setting run: \(tempRunDistance) miles, userId: \(userId)")
        
        let body: [String: Any] = [
            "run_distance": tempRunDistance,
            "run_enabled": true
        ]
        
        saveObjectiveToBackend(body: body) { success in
            DispatchQueue.main.async {
                self.isSavingRun = false
                if success {
                    self.settings.runIsSet = true
                    self.settings.runEnabled = true
                    self.settings.runDistance = self.tempRunDistance
                    self.showSuccess("Run set!")
                    self.onSave?()
                    print("✅ Run set successfully")
                } else {
                    print("❌ Failed to set run")
                }
            }
        }
    }
    
    private func unsetRun() {
        isSavingRun = true
        print("🏃 Unsetting run, userId: \(userId)")
        
        let body: [String: Any] = [
            "run_enabled": false
        ]
        
        saveObjectiveToBackend(body: body) { success in
            DispatchQueue.main.async {
                self.isSavingRun = false
                if success {
                    self.settings.runIsSet = false
                    self.settings.runEnabled = false
                    self.showSuccess("Run removed")
                    print("✅ Run unset successfully")
                } else {
                    print("❌ Failed to unset run")
                }
            }
        }
    }
    
    private func setSchedule() {
        isSavingSchedule = true
        print("📅 Setting schedule: \(tempScheduleType), deadline: \(tempDeadline)")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let deadlineString = formatter.string(from: tempDeadline)
        
        let body: [String: Any] = [
            "objective_schedule": tempScheduleType.lowercased(),
            "objective_deadline": deadlineString
        ]
        
        saveObjectiveToBackend(body: body) { success in
            DispatchQueue.main.async {
                self.isSavingSchedule = false
                if success {
                    self.settings.scheduleIsSet = true
                    self.deadline = self.tempDeadline
                    self.scheduleType = self.tempScheduleType
                    
                    // Schedule notifications
                    self.notificationManager.scheduleObjectiveReminder(
                        deadline: self.deadline,
                        objective: self.tempPushupCount,
                        scheduleType: self.scheduleType
                    )
                    
                    withAnimation {
                        self.isScheduleExpanded = false
                    }
                    self.showSuccess("Schedule saved!")
                    print("✅ Schedule set successfully")
                } else {
                    print("❌ Failed to set schedule")
                }
            }
        }
    }
    
    private func unsetSchedule() {
        isSavingSchedule = true
        print("📅 Unsetting schedule")
        
        // Reset schedule to defaults on backend
        let body: [String: Any] = [
            "objective_schedule": "daily",
            "objective_deadline": "22:00"  // Default to 10 PM
        ]
        
        saveObjectiveToBackend(body: body) { success in
            DispatchQueue.main.async {
                self.isSavingSchedule = false
                if success {
                    self.settings.scheduleIsSet = false
                    self.tempScheduleType = "Daily"
                    // Reset tempDeadline to 10 PM
                    let components = DateComponents(hour: 22, minute: 0)
                    if let defaultTime = Calendar.current.date(from: components) {
                        self.tempDeadline = defaultTime
                    }
                    self.showSuccess("Schedule cleared")
                    print("✅ Schedule unset successfully")
                } else {
                    print("❌ Failed to unset schedule")
                }
            }
        }
    }
    
    private func syncLockToBackend() {
        let isoFormatter = ISO8601DateFormatter()
        let lockDateString = isoFormatter.string(from: settingsLockedUntil)
        
        let body: [String: Any] = [
            "settings_locked_until": lockDateString
        ]
        
        saveObjectiveToBackend(body: body) { _ in }
    }
    
    private func saveObjectiveToBackend(body: [String: Any], completion: @escaping (Bool) -> Void) {
        guard !userId.isEmpty else {
            print("⚠️ No userId, skipping save")
            completion(false)
            return
        }
        
        guard let url = URL(string: "https://api.live-eos.com/objectives/settings/\(userId)") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Save error: \(error)")
                completion(false)
                return
            }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                print("✅ Objective saved to backend")
                completion(true)
            } else {
                print("❌ Save failed: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                completion(false)
            }
        }.resume()
    }
    
    private func loadObjectivesFromBackend() {
        guard !userId.isEmpty else { return }
        
        guard let url = URL(string: "https://api.live-eos.com/objectives/settings/\(userId)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                print("📥 Loading objectives from backend...")
                
                // Load pushups
                if let pushEnabled = json["pushups_enabled"] as? Bool {
                    self.settings.pushupsIsSet = pushEnabled
                    self.settings.pushupsEnabled = pushEnabled
                    print("  - pushups_enabled: \(pushEnabled)")
                }
                if let pushCount = json["pushups_count"] as? Int, pushCount > 0 {
                    self.tempPushupCount = pushCount
                    if json["pushups_enabled"] == nil {
                        // Legacy: if pushups_enabled doesn't exist but count > 0, assume set
                        self.settings.pushupsIsSet = true
                        self.settings.pushupsEnabled = true
                    }
                    print("  - pushups_count: \(pushCount)")
                }
                
                // Load run
                if let runEn = json["run_enabled"] as? Bool {
                    self.settings.runIsSet = runEn
                    self.settings.runEnabled = runEn
                    print("  - run_enabled: \(runEn)")
                }
                if let runDist = json["run_distance"] as? Double, runDist > 0 {
                    self.tempRunDistance = runDist
                    self.settings.runDistance = runDist
                    print("  - run_distance: \(runDist)")
                }
                
                // Sync pushup objective to binding
                if self.settings.pushupsIsSet {
                    self.objective = self.tempPushupCount
                }
                
                // Load schedule
                if let schedule = json["objective_schedule"] as? String {
                    self.tempScheduleType = schedule.capitalized
                    self.scheduleType = schedule.capitalized  // Sync to binding
                    print("  - schedule: \(schedule)")
                }
                if let deadlineStr = json["objective_deadline"] as? String, !deadlineStr.isEmpty {
                    // Handle both "HH:mm" and "HH:mm:ss" formats from backend
                    let cleanDeadline = String(deadlineStr.prefix(5)) // Extract "HH:mm" from "HH:mm:ss"
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    if let parsed = formatter.date(from: cleanDeadline) {
                        self.tempDeadline = parsed
                        self.deadline = parsed  // Sync to binding
                        // Only mark schedule as set if there's actual objective data
                        if self.settings.pushupsIsSet || self.settings.runIsSet {
                            self.settings.scheduleIsSet = true
                        }
                        print("  ✅ Loaded schedule: \(self.tempScheduleType) @ \(cleanDeadline)")
                    } else {
                        print("  ⚠️ Failed to parse deadline: \(deadlineStr)")
                    }
                }
                
                // Collapse sections if set (better UX when data is loaded)
                if self.settings.pushupsIsSet || self.settings.runIsSet {
                    self.isObjectiveExpanded = false
                }
                if self.settings.scheduleIsSet {
                    self.isScheduleExpanded = false
                }
                
                print("📥 Load complete: pushups=\(self.settings.pushupsIsSet), run=\(self.settings.runIsSet), schedule=\(self.settings.scheduleIsSet)")
            }
        }.resume()
    }
}

// MARK: - Camera view model

final class CameraViewModel: NSObject, ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var pushupCount: Int = 0
    @Published var isTracking = false

    private var captureSession: AVCaptureSession?
    private var videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let poseEstimator = PoseEstimator()
    private var outputDelegate: CameraOutputDelegate?

    override init() {
        super.init()
        self.outputDelegate = CameraOutputDelegate(owner: self)
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    func startTracking() {
        isTracking = true
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            return
        }

        session.addInput(input)
        videoOutput.setSampleBufferDelegate(outputDelegate, queue: sessionQueue)
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            } else {
                #if !targetEnvironment(simulator)
                connection.videoOrientation = .portrait
                #endif
            }
            connection.isVideoMirrored = false
        }

        session.startRunning()
        self.captureSession = session
    }

    fileprivate func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.currentFrame = uiImage
            }

            if isTracking {
                poseEstimator.detectPose(in: cgImage) { [weak self] keypoints in
                    self?.processPoseForPushups(keypoints: keypoints)
                }
            }
        }
    }

    private func processPoseForPushups(keypoints: [VNRecognizedPoint]) {
        guard keypoints.count > 0 else { return }

        if let nose = keypoints.first(where: { $0.confidence > 0.3 }) {
            let yPosition = nose.location.y

            if yPosition < 0.4 {
                if !poseEstimator.wasInUpPosition {
                    poseEstimator.wasInUpPosition = true
                }
            } else if yPosition > 0.6 && poseEstimator.wasInUpPosition {
                poseEstimator.wasInUpPosition = false
                DispatchQueue.main.async {
                    self.pushupCount += 1
                }
            }
        }
    }
}

// MARK: - Camera output delegate

private final class CameraOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var owner: CameraViewModel?

    init(owner: CameraViewModel) {
        self.owner = owner
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { @MainActor in
            owner?.processFrame(sampleBuffer)
        }
    }
}

// MARK: - Pose estimator

final class PoseEstimator {
    var wasInUpPosition = false

    func detectPose(in image: CGImage, completion: @escaping ([VNRecognizedPoint]) -> Void) {
        let request = VNDetectHumanBodyPoseRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNHumanBodyPoseObservation],
                  let pose = observations.first else {
                completion([])
                return
            }

            do {
                let keypoints = try pose.recognizedPoints(.all)
                let points = keypoints.values.map { $0 }
                completion(points)
            } catch {
                completion([])
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Notification manager

final class NotificationManager {
    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleObjectiveReminder(deadline: Date, objective: Int, scheduleType: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: centerIdentifiers(for: scheduleType))

        let content = UNMutableNotificationContent()
        content.title = "Push-up Objective Missed"
        content.body = "You didn't complete your \(objective) push-ups today. Your stakes will be forfeited to your designated recipient."
        content.sound = .default

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: deadline)

        if scheduleType == "Weekdays" {
            for weekday in 2...6 {
                var weekdayComponents = components
                weekdayComponents.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: weekdayComponents, repeats: true)

                let request = UNNotificationRequest(
                    identifier: "pushupObjectiveFailure_weekday_\(weekday)",
                    content: content,
                    trigger: trigger
                )

                center.add(request, withCompletionHandler: nil)
            }
        } else {
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let request = UNNotificationRequest(
                identifier: "pushupObjectiveFailure_daily",
                content: content,
                trigger: trigger
            )

            center.add(request, withCompletionHandler: nil)
        }
    }

    private func centerIdentifiers(for scheduleType: String) -> [String] {
        if scheduleType == "Weekdays" {
            return (2...6).map { "pushupObjectiveFailure_weekday_\($0)" }
        } else {
            return ["pushupObjectiveFailure_daily"]
        }
    }
}

// MARK: - Stripe deposit payment helper

final class DepositPaymentService: ObservableObject {
    @Published var paymentSheet: PaymentSheet?

    func preparePaymentSheet(amount: Double, userId: String, completion: @escaping (Error?) -> Void) {
        let cents = max(1, Int((amount * 100).rounded()))
        
        print("💳 preparePaymentSheet - amount: \(cents) cents, userId: '\(userId)'")
        
        guard !userId.isEmpty else {
            completion(NSError(domain: "EOS", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not signed in - please sign in first"]))
            return
        }

        var request = URLRequest(url: StripeConfig.backendURL.appendingPathComponent("create-payment-intent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["amount": cents, "userId": userId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("❌ No data received")
                completion(NSError(domain: "Stripe", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data from server"]))
                return
            }
            
            if let rawString = String(data: data, encoding: .utf8) {
                print("📦 Raw response: \(rawString)")
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let customerId = json["customer"] as? String,
                let ephemeralKeySecret = json["ephemeralKeySecret"] as? String,
                let clientSecret = json["paymentIntentClientSecret"] as? String
            else {
                let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Invalid backend response"
                print("❌ Parse failed: \(errorMsg)")
                completion(NSError(domain: "Stripe", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                return
            }
            
            print("✅ Got payment intent, customer: \(customerId)")

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "EOS"
            configuration.customer = .init(id: customerId, ephemeralKeySecret: ephemeralKeySecret)
            
            // Apple Pay ENABLED
            configuration.applePay = .init(
                merchantId: "merchant.com.emayne.eos",
                merchantCountryCode: "US"
            )
            
            // Allow delayed payment methods if available
            configuration.allowsDelayedPaymentMethods = true
            
            // Return URL for app redirects (required for 3DS authentication)
            configuration.returnURL = "eos-app://stripe-redirect"

            DispatchQueue.main.async {
                self.paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret,
                                                 configuration: configuration)
                completion(nil)
            }
        }.resume()
    }

    func present(completion: @escaping (PaymentSheetResult) -> Void) {
        guard let sheet = paymentSheet else { return }

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return
        }

        let presentingVC = rootVC.presentedViewController ?? rootVC

        guard presentingVC.presentedViewController == nil else {
            completion(.failed(error: PaymentSheetError.alreadyPresented))
            return
        }

        sheet.present(from: presentingVC, completion: completion)
    }
}

// MARK: - Keyboard helpers

extension UIApplication {
    func eos_dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Custom Types

struct CustomRecipient: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let status: String // "pending", "active", "inactive"
    
    init(name: String, email: String) {
        self.id = UUID().uuidString
        self.name = name
        self.email = email
        self.status = "pending"
    }
    
    init(id: String, name: String, email: String, status: String) {
        self.id = id
        self.name = name
        self.email = email
        self.status = status
    }
}

// MARK: - UI Components

struct PayoutTypeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? .white : .black)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : Color.gray.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }
}

struct RecipientRow: View {
    let recipient: CustomRecipient
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    // Status colors based on recipient status
    private var statusBackgroundColor: Color {
        switch recipient.status.lowercased() {
        case "active": return Color.green.opacity(0.15)
        case "available": return Color.blue.opacity(0.15)
        case "pending": return Color.orange.opacity(0.15)
        default: return Color.gray.opacity(0.15)
        }
    }
    
    private var statusForegroundColor: Color {
        switch recipient.status.lowercased() {
        case "active": return Color.green.opacity(0.9)
        case "available": return Color.blue.opacity(0.9)
        case "pending": return Color.orange.opacity(0.9)
        default: return Color.gray.opacity(0.9)
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : Color.black.opacity(0.5))
                    .font(.title3)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipient.name)
                        .font(.system(.body, design: .rounded, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                    Text(recipient.email)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                
                Spacer()
                
                Text(recipient.status)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(statusBackgroundColor)
                    )
                    .foregroundStyle(statusForegroundColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected 
                        ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 0.08))
                        : isPressed 
                            ? Color.gray.opacity(0.1)
                            : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected 
                        ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 0.3))
                        : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Profile view

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("profileUsername") private var profileUsername: String = ""
    @AppStorage("profileEmail") private var profileEmail: String = ""
    @AppStorage("profilePhone") private var profilePhone: String = ""
    @AppStorage("profileCashHoldings") private var profileCashHoldings: Double = 0
    @AppStorage("profileCompleted") private var profileCompleted: Bool = false
    @AppStorage("isSignedIn") private var isSignedIn: Bool = false
    
    // Stakes Destination Settings
    @AppStorage("payoutType") private var payoutType: String = "custom"
    @AppStorage("selectedCharity") private var selectedCharity: String = "GiveDirectly"  // Hidden from UI for now (App Store 3.2.2)
    @AppStorage("customRecipientsData") private var customRecipientsData: Data = Data()
    @AppStorage("cachedRecipientsForUserId") private var cachedRecipientsForUserId: String = ""  // Track which user the cache belongs to
    @AppStorage("selectedRecipientId") private var selectedRecipientId: String = ""
    @AppStorage("missedGoalPayout") private var missedGoalPayout: Double = 0.0
    @AppStorage("payoutCommitted") private var payoutCommitted: Bool = false
    @AppStorage("committedPayoutAmount") private var committedPayoutAmount: Double = 0.0

    @AppStorage("destinationCommitted") private var destinationCommitted: Bool = false
    @AppStorage("committedRecipientId") private var committedRecipientId: String = ""
    @AppStorage("committedDestination") private var committedDestination: String = "custom"
    @AppStorage("userId") private var userId: String = ""
    
    // Objective settings (synced with SettingsView via @AppStorage)
    @AppStorage("pushupObjective") private var pushupObjective: Int = 10
    @AppStorage("objectiveDeadline") private var objectiveDeadline: Date = {
        let components = DateComponents(hour: 22, minute: 0)
        return Calendar.current.date(from: components) ?? Date()
    }()
    @AppStorage("scheduleType") private var scheduleType: String = "Daily"
    @AppStorage("settingsLockedUntil") private var settingsLockedUntil: Date = Date.distantPast
    @AppStorage("stravaConnected") private var stravaConnected: Bool = false
    @AppStorage("stravaAthleteName") private var stravaAthleteName: String = ""
    @AppStorage("objectiveType") private var objectiveType: String = "pushups"
    
    @State private var showDestinationSelector: Bool = false
    @State private var isStravaExpanded: Bool = false
    @State private var isCheckingStrava: Bool = false
    @State private var activeRecipientName: String = ""
    @State private var activeRecipientId: String = ""
    @State private var depositAmount: String = ""
    @State private var showPayoutSelector: Bool = false
    @StateObject private var depositPaymentService = DepositPaymentService()
    @State private var isProcessingDeposit = false
    @State private var depositErrorMessage: String?

    @State private var profilePassword: String = ""
    @State private var profileErrorMessage: String?
    @State private var isSavingProfile = false
    @State private var isAccountExpanded: Bool = false
    
    // Delete account states
    @State private var showDeleteAccountAlert: Bool = false
    @State private var deleteAccountPassword: String = ""
    @State private var isDeletingAccount: Bool = false
    @State private var deleteAccountError: String?
    @State private var customRecipients: [CustomRecipient] = []
    @State private var showingAddRecipient = false
    // Stakes acknowledgment states
    @State private var acknowledgedVoluntary: Bool = false
    @State private var acknowledgedNoRefund: Bool = false
    @State private var acknowledgedOver18: Bool = false
    @State private var showSignInView = false
    @State private var showCreateAccountView = false
    @FocusState private var isPayoutAmountFocused: Bool
    @FocusState private var isDepositAmountFocused: Bool
    @State private var showingCharityPicker = false

    // Charity list - hidden from UI per App Store 3.2.2, kept for future use when nonprofit status acquired
    private let charities = [
        "GiveDirectly",
        "Doctors Without Borders",
        "charity: water",
        "St. Jude Children's Hospital",
        "Feeding America",
        "Direct Relief",
        "World Central Kitchen",
        "American Red Cross",
        "The Nature Conservancy",
        "Habitat for Humanity",
        "UNICEF",
        "Save the Children",
        "American Cancer Society",
        "Wounded Warrior Project",
        "ASPCA",
        "Make-A-Wish Foundation",
        "ACLU",
        "Khan Academy",
        "Against Malaria Foundation"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                // Background color
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                Form {
                    // Account Section - Different based on sign-in state
                    if !isSignedIn {
                        // Not signed in - show sign-in/create options
                        Section {
                            VStack(spacing: 12) {
                                Text("Welcome to EOS")
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .padding(.top, 10)
                                
                                Text("Sign in to access your profile")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                
                                // Create Account Button
                                Button(action: { showCreateAccountView = true }) {
                                    Text("Create Account")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                        )
                                }
                                .buttonStyle(.plain)
                                
                                // Sign In Button
                                Button(action: { showSignInView = true }) {
                                    Text("Sign In")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(Color.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.black, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(.bottom, 8)
                            }
                            .listRowBackground(Color.white)
                        } header: {
                            Text("Account")
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                    } else {
                        // Signed in - show account info button
                        Section {
                            Button(action: { isAccountExpanded.toggle() }) {
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    
                                    Text(profileUsername.isEmpty ? "Account Settings" : profileUsername)
                                        .font(.system(.body, design: .rounded, weight: .medium))
                                        .foregroundStyle(Color.black)
                                    
                                    Spacer()
                                    
                                    Image(systemName: isAccountExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(Color.black.opacity(0.5))
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            
                            if isAccountExpanded {
                                VStack(spacing: 10) {
                                    if !profileCompleted {
                                        HStack(spacing: 6) {
                                            Image(systemName: "info.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(Color.orange)
                                            Text("Save profile to send invites")
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(Color.orange)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    
                                    VStack(spacing: 8) {
                                        HStack {
                                            Image(systemName: "person")
                                                .font(.caption)
                                                .foregroundStyle(Color.black.opacity(0.6))
                                                .frame(width: 20)
                                            TextField("Name", text: $profileUsername)
                                                .font(.system(.subheadline, design: .rounded))
                                                .foregroundStyle(Color.black)
                                        }
                                        Divider()
                                        
                                        HStack {
                                            Image(systemName: "envelope")
                                                .font(.caption)
                                                .foregroundStyle(Color.black.opacity(0.6))
                                                .frame(width: 20)
                                            TextField("Email", text: $profileEmail)
                                                .font(.system(.subheadline, design: .rounded))
                                                .keyboardType(.emailAddress)
                                                .autocapitalization(.none)
                                                .foregroundStyle(Color.black)
                                        }
                                        Divider()
                                        
                                        HStack {
                                            Image(systemName: "lock")
                                                .font(.caption)
                                                .foregroundStyle(Color.black.opacity(0.6))
                                                .frame(width: 20)
                                            SecureField("Password", text: $profilePassword, prompt: Text("Password").foregroundColor(Color.black.opacity(0.5)))
                                                .font(.system(.subheadline, design: .rounded))
                                                .foregroundStyle(Color.black)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    
                                    Button(action: saveProfile) {
                                        HStack {
                                            if isSavingProfile {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            } else {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                            }
                                            Text("Update")
                                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
                                                    .opacity(isSavingProfile || !isProfileValid ? 0.6 : 1.0))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSavingProfile || !isProfileValid)
                                    
                                    // Strava Connection Section
                                    Divider()
                                        .padding(.vertical, 8)
                                    
                                    Button(action: { isStravaExpanded.toggle() }) {
                                        HStack {
                                            Image(systemName: "figure.run")
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.orange)
                                            
                                            Text("Strava")
                                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                                .foregroundStyle(Color.black)
                                            
                                            Spacer()
                                            
                                            if stravaConnected {
                                                Text("Connected")
                                                    .font(.system(.caption2, design: .rounded))
                                                    .foregroundStyle(Color.green)
                                            }
                                            
                                            Image(systemName: isStravaExpanded ? "chevron.up" : "chevron.down")
                                                .font(.caption2)
                                                .foregroundStyle(Color.black.opacity(0.5))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if isStravaExpanded {
                                        VStack(spacing: 12) {
                                            if stravaConnected {
                                                // Connected state
                                                HStack {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(Color.green)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("Connected to Strava")
                                                            .font(.system(.caption, design: .rounded, weight: .medium))
                                                            .foregroundStyle(Color.black)
                                                        if !stravaAthleteName.isEmpty {
                                                            Text(stravaAthleteName)
                                                                .font(.system(.caption2, design: .rounded))
                                                                .foregroundStyle(Color.gray)
                                                        }
                                                    }
                                                    Spacer()
                                                }
                                                
                                                Button(action: disconnectStrava) {
                                                    Text("Disconnect")
                                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                                        .foregroundStyle(Color.red)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 8)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                                        )
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                // Not connected state
                                                Text("Connect Strava to track run objectives automatically")
                                                    .font(.system(.caption2, design: .rounded))
                                                    .foregroundStyle(Color.gray)
                                                    .multilineTextAlignment(.leading)
                                                
                                                Button(action: connectStrava) {
                                                    HStack {
                                                        if isCheckingStrava {
                                                            ProgressView()
                                                                .scaleEffect(0.7)
                                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                        } else {
                                                            Image(systemName: "link")
                                                                .font(.caption)
                                                        }
                                                        Text("Connect Strava")
                                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                                    }
                                                    .foregroundStyle(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.orange)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    
                                    Divider()
                                        .padding(.vertical, 8)
                                    
                                    // Change password link
                                    Button(action: {
                                        if let url = URL(string: "https://live-eos.com/forgot-password") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Text("Change password")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.gray)
                                    }
                                    .padding(.top, 4)
                                    
                                    Button(action: {
                                        // Sign out - Nuclear clear ALL cached data
                                        if let bundleID = Bundle.main.bundleIdentifier {
                                            UserDefaults.standard.removePersistentDomain(forName: bundleID)
                                            UserDefaults.standard.synchronize()
                                        }
                                        // Reset UI state
                                        isAccountExpanded = false
                                        profilePassword = ""
                                    }) {
                                        HStack {
                                            Image(systemName: "arrow.right.square")
                                                .font(.caption)
                                            Text("Sign Out")
                                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                        }
                                        .foregroundStyle(Color.red)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.red, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Delete Account button
                                    Button(action: {
                                        deleteAccountPassword = ""
                                        deleteAccountError = nil
                                        showDeleteAccountAlert = true
                                    }) {
                                        Text("Delete Account")
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundStyle(Color.gray)
                                    }
                                    .padding(.top, 8)
                                    .buttonStyle(.plain)
                                    
                                    if let error = profileErrorMessage {
                                        HStack(spacing: 4) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                            Text(error)
                                                .font(.system(.caption2, design: .rounded))
                                        }
                                        .foregroundStyle(Color.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        } header: {
                            Text("Account")
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                        .listRowBackground(Color.white)
                    }
                
                // Designated Recipient Section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Recipient selector (charity removed per App Store guidelines)
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Recipients")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                    Spacer()
                                    Button(action: { showingAddRecipient = true }) {
                                        Label("Add", systemImage: "plus.circle.fill")
                                            .font(.system(.caption, design: .rounded))
                                    }
                                }
                                
                                if customRecipients.isEmpty {
                                    HStack {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                            .foregroundStyle(Color.black.opacity(0.6))
                                        Text("No recipients yet")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.6))
                                    }
                                    .padding(.vertical, 8)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(Array(customRecipients.enumerated()), id: \.element.id) { index, recipient in
                                            HStack(spacing: 12) {
                                                RecipientRow(
                                                    recipient: recipient,
                                                    isSelected: selectedRecipientId == recipient.id,
                                                    onSelect: { 
                                                        // Only allow selecting active or available recipients
                                                        if recipient.status == "active" || recipient.status == "available" {
                                                            selectRecipient(recipient.id)
                                                        }
                                                    }
                                                )
                                                
                                                // Delete button (always visible)
                                                Button(action: {
                                                    withAnimation(.easeOut(duration: 0.3)) {
                                                        deleteRecipient(at: index)
                                                    }
                                                }) {
                                                    Image(systemName: "trash.circle.fill")
                                                        .font(.title2)
                                                        .foregroundStyle(Color.red.opacity(0.8))
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // Commit Destination Button - ALWAYS visible
                        // Disabled if custom selected but no active recipient
                        Button(action: commitDestination) {
                            HStack {
                                Image(systemName: isCommitButtonDisabled ? "exclamationmark.circle.fill" : (destinationCommitted ? "checkmark.circle.fill" : "lock.fill"))
                                    .font(.body)
                                Text(lockButtonText)
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isCommitButtonDisabled 
                                        ? Color.gray.opacity(0.3) 
                                        : Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                            )
                            .foregroundStyle(isCommitButtonDisabled ? .gray : .white)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCommitButtonDisabled)
                        .padding(.top, 8)
                    }
                    .listRowBackground(Color.white)
                } header: {
                    Text("Designated Recipient")
                        .foregroundStyle(Color.white.opacity(0.95))
                } footer: {
                    Text(destinationCommitted ? "Recipient locked." : "Select who receives your forfeited stakes if you miss your goal.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                
                // Accountability Stakes Section
                Section {
                    VStack(spacing: 16) {
                        // Show minimized committed bar OR full selector
                        if payoutCommitted && !showPayoutSelector {
                            // Minimized committed bar - tap to expand
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showPayoutSelector = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("$\(committedPayoutAmount, specifier: "%.0f") stakes committed")
                                            .font(.system(.body, design: .rounded, weight: .semibold))
                                            .foregroundStyle(Color.black)
                                        Text("Tap to change stakes amount")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.5))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(Color.black.opacity(0.4))
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Full payout selector
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stakes Amount")
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                Text("Amount at risk per goal")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.6))
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                TextField("0.00", value: $missedGoalPayout, format: .number)
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    .keyboardType(.decimalPad)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    .focused($isPayoutAmountFocused)
                            }
                        }
                        
                        // Quick select amounts
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                ForEach([10.0, 50.0, 100.0], id: \.self) { amount in
                                    Button(action: { 
                                        missedGoalPayout = amount
                                            isPayoutAmountFocused = false
                                    }) {
                                        Text("$\(Int(amount))")
                                            .font(.system(.body, design: .rounded, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(missedGoalPayout == amount ? 
                                                        Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : 
                                                        Color.gray.opacity(0.25))
                                            )
                                            .foregroundStyle(Color.black)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Button(action: { 
                                if missedGoalPayout == 10 || missedGoalPayout == 50 || missedGoalPayout == 100 {
                                        missedGoalPayout = 0
                                }
                                    isPayoutAmountFocused = true
                            }) {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.body)
                                    Text("Custom Amount")
                                        .font(.system(.body, design: .rounded, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(missedGoalPayout != 10 && missedGoalPayout != 50 && missedGoalPayout != 100 && missedGoalPayout != 0 ? 
                                            Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : 
                                            Color.gray.opacity(0.25))
                                )
                                .foregroundStyle(Color.black)
                            }
                            .buttonStyle(.plain)
                            }
                            
                            // Stakes acknowledgments - only show when setting stakes for first time
                            if !payoutCommitted && missedGoalPayout > 0 {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("By setting stakes, I acknowledge:")
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.7))
                                        .padding(.top, 8)
                                    
                                    // Voluntary acknowledgment
                                    Button(action: { acknowledgedVoluntary.toggle() }) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: acknowledgedVoluntary ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(acknowledgedVoluntary ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : Color.gray)
                                                .font(.body)
                                            Text("Setting stakes is voluntary. I bear all risk of achieving my commitment.")
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(Color.black.opacity(0.8))
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // No refund acknowledgment
                                    Button(action: { acknowledgedNoRefund.toggle() }) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: acknowledgedNoRefund ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(acknowledgedNoRefund ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : Color.gray)
                                                .font(.body)
                                            Text("Forfeited stakes are non-refundable. If I miss my goal, my stakes go to my designated recipient.")
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(Color.black.opacity(0.8))
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Age acknowledgment
                                    Button(action: { acknowledgedOver18.toggle() }) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: acknowledgedOver18 ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(acknowledgedOver18 ? Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : Color.gray)
                                                .font(.body)
                                            Text("I am at least 18 years of age.")
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(Color.black.opacity(0.8))
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            // Set Stakes Button
                            Button(action: commitPayout) {
                                HStack {
                                    Image(systemName: payoutCommitted ? "checkmark.circle.fill" : "lock.fill")
                                        .font(.body)
                                    Text(payoutCommitted ? "Update Stakes" : "Set Your Stakes")
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(canSetStakes ? 
                                            Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)) : 
                                            Color.gray.opacity(0.3))
                                )
                                .foregroundStyle(canSetStakes ? Color.white : Color.black.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSetStakes)
                            .padding(.top, 4)
                        }
                    }
                    .listRowBackground(Color.white)
                } header: {
                    Text("Accountability Stakes")
                        .foregroundStyle(Color.white.opacity(0.95))
                } footer: {
                    Text(payoutCommitted ? "Stakes committed. Complete your goal to keep your money. Miss it and $\(Int(committedPayoutAmount)) goes to your designated recipient." : "Put your money where your mouth is. Set stakes to hold yourself accountable. Complete your goal and keep your money.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                }

                // Balance Section
                Section {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Available Balance")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.6))
                                Text("$\(profileCashHoldings, specifier: "%.2f")")
                                    .font(.system(.title2, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                            }
                            Spacer()
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                        }

                        HStack(spacing: 12) {
                            HStack {
                                Text("$")
                                    .foregroundStyle(Color.black.opacity(0.6))
                                TextField("0.00", text: $depositAmount)
                                    .keyboardType(.decimalPad)
                                    .focused($isDepositAmountFocused)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.25))
                            .cornerRadius(8)
                            
                            Button(action: startDeposit) {
                                if isProcessingDeposit {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Deposit")
                                        .font(.system(.body, design: .rounded, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(depositAmount.isEmpty || isProcessingDeposit)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))
                                    .opacity(depositAmount.isEmpty || isProcessingDeposit ? 0.5 : 1.0)
                            )
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                        }
                        
                        // Withdraw - links to web portal (uses onTapGesture to avoid Form button tap bleed with Deposit)
                        let isWithdrawLocked = settingsLockedUntil > Date()
                        
                        Text(isWithdrawLocked ? "🔒 Withdraw Locked" : "Withdraw")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(isWithdrawLocked ? Color.gray.opacity(0.3) : Color.white)
                            .foregroundStyle(isWithdrawLocked ? Color.gray : Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isWithdrawLocked ? Color.gray : Color.black, lineWidth: 1)
                            )
                            .cornerRadius(8)
                            .onTapGesture {
                                if !isWithdrawLocked {
                                    if let url = URL(string: "https://live-eos.com/portal") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }

                        if let error = depositErrorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption)
                                Text(error)
                                    .font(.system(.caption, design: .rounded))
                            }
                            .foregroundStyle(Color.red)
                        }
                    }
                } header: {
                    Text("Balance")
                        .foregroundStyle(Color.white.opacity(0.95))
                } footer: {
                    Text("Add funds to back your commitment")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .listRowBackground(Color.white)

                if let error = profileErrorMessage {
                    Section {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.red)
                    }
                }
                
                // Terms & Legal Section
                Section {
                    HStack {
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://live-eos.com/terms") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Terms of Service")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.gray)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                } footer: {
                    Text("By using EOS, you agree to our Terms of Service and Commitment Contract.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .listRowBackground(Color.clear)
            }
                }
                .listRowBackground(Color.white)
                .listRowSeparatorTint(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 0.3)))
            }
            .scrollContentBackground(.hidden)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if profileCompleted {
                        Button("Done") {
                            dismiss()
                        }
                        .font(.system(.body, design: .rounded, weight: .medium))
                    } else {
                        Button(isSavingProfile ? "Saving…" : "Save") {
                            saveProfile()
                        }
                        .disabled(isSavingProfile || !isProfileValid)
                        .font(.system(.body, design: .rounded, weight: .medium))
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        // Dismiss all focused states
                        isDepositAmountFocused = false
                        isPayoutAmountFocused = false
                        // Dismiss keyboard for all other text fields
                        UIApplication.shared.eos_dismissKeyboard()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                }
            }
            .sheet(isPresented: $showingAddRecipient) {
                AddRecipientSheet(
                    payerName: profileUsername,
                    payerEmail: profileEmail,
                    onComplete: { newRecipient in
                        customRecipients.append(newRecipient)
                        saveCustomRecipients()
                        if customRecipients.count == 1 {
                            selectedRecipientId = newRecipient.id
                        }
                    }
                )
            }
            .sheet(isPresented: $showSignInView) {
                SignInView(isSignedIn: $isSignedIn, profileUsername: $profileUsername, profileEmail: $profileEmail, profilePhone: $profilePhone, profileCompleted: $profileCompleted)
            }
            .sheet(isPresented: $showCreateAccountView) {
                CreateAccountView(
                    isSignedIn: $isSignedIn,
                    profileUsername: $profileUsername,
                    profileEmail: $profileEmail,
                    profilePhone: $profilePhone,
                    profileCompleted: $profileCompleted
                )
            }
            // Charity picker - hidden from UI per App Store 3.2.2, kept for future use
            .sheet(isPresented: $showingCharityPicker) {
                NavigationView {
                    List {
                        ForEach(charities, id: \.self) { charity in
                            Button(action: {
                                selectedCharity = charity
                                showingCharityPicker = false
                            }) {
                                HStack {
                                    Text(charity)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    if charity == selectedCharity {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Charity")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingCharityPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                SecureField("Enter your password", text: $deleteAccountPassword)
                Button("Cancel", role: .cancel) {
                    deleteAccountPassword = ""
                    deleteAccountError = nil
                }
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
                .disabled(deleteAccountPassword.isEmpty)
            } message: {
                if let error = deleteAccountError {
                    Text(error)
                } else {
                    Text("This will permanently delete all your data including account info, objectives, sessions, and transaction history. This action cannot be undone.")
                }
            }
            .onChange(of: isSignedIn) { oldValue, newValue in
                if newValue {
                    // User just signed in - clear old recipient cache and fetch fresh
                    let newUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
                    if newUserId != cachedRecipientsForUserId {
                        customRecipients = []
                        customRecipientsData = Data()
                        selectedRecipientId = ""
                        cachedRecipientsForUserId = newUserId
                        print("🔄 User signed in, cleared recipient cache for: \(newUserId)")
                    }
                    // Fetch fresh data for new user
                    syncInviteStatuses()
                }
            }
            .onAppear {
                // Check if user changed - clear recipient cache if so
                let currentUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
                if !currentUserId.isEmpty && currentUserId != cachedRecipientsForUserId {
                    // Different user - clear stale cache
                    customRecipients = []
                    customRecipientsData = Data()
                    selectedRecipientId = ""
                    cachedRecipientsForUserId = currentUserId
                    print("🔄 User changed, cleared recipient cache")
                }
                
                loadCustomRecipients()
                refreshBalance()
                syncInviteStatuses()
                checkStravaStatus()
            }
        }
    
    private var isProfileValid: Bool {
        // Password only required for new accounts, not updates
        // Phone is optional
        let baseValid = !profileUsername.isEmpty && !profileEmail.isEmpty
        return isSignedIn ? baseValid : (baseValid && !profilePassword.isEmpty)
    }

    private var lockButtonText: String {
        // Can't lock custom without an active recipient
        if payoutType.lowercased() == "custom" && !hasActiveRecipient {
            return "Recipient Not Active"
        }
        if !destinationCommitted {
            return "Set Recipient"
        }
        // Check if user changed destination type or recipient
        let destChanged = payoutType.lowercased() != committedDestination.lowercased()
        let recipientChanged = payoutType == "custom" && selectedRecipientId != committedRecipientId && !selectedRecipientId.isEmpty
        if destChanged || recipientChanged {
            return "Update Recipient"
        }
        return "Recipient Set"
    }

    /// Returns true if there's an active recipient selected (for custom payout)
    private var hasActiveRecipient: Bool {
        // If not custom, this check doesn't apply
        if payoutType.lowercased() != "custom" { return true }
        
        // Check if selected recipient exists and is active or available
        guard !selectedRecipientId.isEmpty else { return false }
        
        if let recipient = customRecipients.first(where: { $0.id == selectedRecipientId }) {
            let status = recipient.status.lowercased()
            return status == "active" || status == "available"
        }
        return false
    }
    
    /// Returns true if the commit button should be disabled
    private var isCommitButtonDisabled: Bool {
        // Requires an active recipient to commit stakes
        return !hasActiveRecipient
    }
    
    /// Returns true if user can set stakes (either already committed, or has acknowledged all terms)
    private var canSetStakes: Bool {
        guard missedGoalPayout > 0 else { return false }
        // If already committed, they can update without re-acknowledging
        if payoutCommitted { return true }
        // First time: must check all acknowledgment boxes
        return acknowledgedVoluntary && acknowledgedNoRefund && acknowledgedOver18
    }
    

    private func commitPayout() {
        guard missedGoalPayout > 0 else { return }
        
        // Update committed values
        committedPayoutAmount = missedGoalPayout
        payoutCommitted = true
        showPayoutSelector = false
        
        // Save to backend (using dedicated sync that doesn't require password)
        syncPayoutSettings()
    }

    private func commitDestination() {
        guard !payoutType.isEmpty else { return }
        committedDestination = payoutType
        // Save recipient ID if custom payout type
        if payoutType.lowercased() == "custom" {
            committedRecipientId = selectedRecipientId
        } else {
            committedRecipientId = ""
        }
        destinationCommitted = true
        showDestinationSelector = false
        syncPayoutSettings()
    }
    
    /// Sync payout settings to backend without requiring password
    private func syncPayoutSettings() {
        guard !userId.isEmpty else {
            print("⚠️ No userId, skipping payout sync")
            return
        }
        
        let body: [String: Any] = [
            "email": profileEmail,
            "missed_goal_payout": committedPayoutAmount > 0 ? committedPayoutAmount : missedGoalPayout,
            "payout_destination": payoutType.lowercased(),
            "committedPayoutAmount": committedPayoutAmount,
            "payoutCommitted": payoutCommitted,
            "destinationCommitted": destinationCommitted,
            "committedDestination": committedDestination.lowercased(),
            "committedRecipientId": committedRecipientId,
            "balanceCents": Int((profileCashHoldings * 100).rounded())
        ]
        
        guard let url = URL(string: "/users/profile", relativeTo: StripeConfig.backendURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Payout sync error: \(error)")
                return
            }
            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    print("✅ Payout settings synced to backend")
                } else {
                    print("❌ Payout sync failed with status: \(http.statusCode)")
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        print("Response: \(body)")
                    }
                }
            }
        }.resume()
    }

    private func fetchRecipientStatus() {
        guard let userId = UserDefaults.standard.string(forKey: "userId"), !userId.isEmpty else { return }
        
        guard let url = URL(string: "/users/\(userId)/recipient", relativeTo: StripeConfig.backendURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                if let hasRecipient = json["hasRecipient"] as? Bool, hasRecipient,
                   let recipient = json["recipient"] as? [String: Any] {
                    self.activeRecipientName = recipient["full_name"] as? String ?? ""
                    self.activeRecipientId = recipient["id"] as? String ?? ""
                }
                if let dest = json["destination"] as? String {
                    // Default to custom - charity no longer supported per App Store guidelines
                    self.payoutType = "custom"
                }
            }
        }.resume()
    }
    
    private func syncInviteStatuses() {
        guard let userId = UserDefaults.standard.string(forKey: "userId"), !userId.isEmpty else {
            print("⚠️ syncInviteStatuses: No userId found, skipping")
            return
        }
        
        print("📡 syncInviteStatuses: Fetching for userId: \(userId)")
        
        guard let url = URL(string: "/users/\(userId)/invites", relativeTo: StripeConfig.backendURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let invites = json["invites"] as? [[String: Any]] else { return }
            
            DispatchQueue.main.async {
                // Rebuild customRecipients from backend invites
                var newRecipients: [CustomRecipient] = []
                
                for invite in invites {
                    // ID can be UUID string or Int - handle both
                    let inviteId: String
                    if let idString = invite["id"] as? String {
                        inviteId = idString
                    } else if let idInt = invite["id"] as? Int {
                        inviteId = String(idInt)
                    } else {
                        continue // Skip if no valid ID
                    }
                    
                    guard let status = invite["status"] as? String else { continue }
                    
                    let inviteCode = invite["invite_code"] as? String ?? ""
                    // Backend status mapping:
                    // "accepted" = currently selected recipient → display as "active"
                    // "inactive" = available recipient (not selected) → display as "available"
                    // "pending" = invite not yet accepted → display as "pending"
                    let newStatus: String
                    if status == "accepted" || status == "active" {
                        newStatus = "active"
                    } else if status == "inactive" {
                        newStatus = "available"  // Available to select but not currently active
                    } else {
                        newStatus = status  // pending, expired, etc.
                    }
                    
                    // Get recipient info if they've signed up
                    var recipientName = "Pending Invite"
                    var recipientEmail = inviteCode // Show invite code if no email yet
                    
                    if let recipient = invite["recipient"] as? [String: Any] {
                        if let name = recipient["name"] as? String, !name.isEmpty {
                            recipientName = name
                        }
                        if let email = recipient["email"] as? String, !email.isEmpty {
                            recipientEmail = email
                        }
                    }
                    
                    let recipient = CustomRecipient(
                        id: inviteId,
                        name: recipientName,
                        email: recipientEmail,
                        status: newStatus
                    )
                    newRecipients.append(recipient)
                }
                
                print("📥 syncInviteStatuses: Received \(newRecipients.count) recipients from API")
                self.customRecipients = newRecipients
                self.saveCustomRecipients()
                
                // Auto-select first active recipient if none selected
                if self.selectedRecipientId.isEmpty,
                   let firstActive = newRecipients.first(where: { $0.status == "active" }) {
                    self.selectedRecipientId = firstActive.id
                }
            }
        }.resume()
    }
    
    private func loadCustomRecipients() {
        if let decoded = try? JSONDecoder().decode([CustomRecipient].self, from: customRecipientsData) {
            customRecipients = decoded
        }
    }
    
    /// Select a recipient and sync to backend
    private func selectRecipient(_ recipientId: String) {
        guard let userId = UserDefaults.standard.string(forKey: "userId"), !userId.isEmpty else {
            // No user ID, just update locally
            selectedRecipientId = recipientId
            return
        }
        
        guard let url = URL(string: "/users/\(userId)/select-recipient", relativeTo: StripeConfig.backendURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["recipientId": recipientId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Optimistically update UI
        selectedRecipientId = recipientId
        
        // Update local status - selected becomes "active", others become "available"
        for i in customRecipients.indices {
            if customRecipients[i].id == recipientId {
                customRecipients[i] = CustomRecipient(
                    id: customRecipients[i].id,
                    name: customRecipients[i].name,
                    email: customRecipients[i].email,
                    status: "active"
                )
            } else if customRecipients[i].status == "active" {
                customRecipients[i] = CustomRecipient(
                    id: customRecipients[i].id,
                    name: customRecipients[i].name,
                    email: customRecipients[i].email,
                    status: "available"
                )
            }
        }
        saveCustomRecipients()
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Failed to select recipient: \(error)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            if httpResponse.statusCode == 200 {
                print("✅ Recipient selected successfully")
                // Re-sync to get fresh data
                DispatchQueue.main.async {
                    self.syncInviteStatuses()
                }
            } else {
                print("❌ Failed to select recipient: HTTP \(httpResponse.statusCode)")
            }
        }.resume()
    }
    
    private func saveCustomRecipients() {
        if let encoded = try? JSONEncoder().encode(customRecipients) {
            customRecipientsData = encoded
            // Track which user this cache belongs to
            cachedRecipientsForUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
        }
    }
    
    private func deleteRecipient(at index: Int) {
        guard index >= 0 && index < customRecipients.count else { return }
        
        let recipientToDelete = customRecipients[index]
        
        // Check if we're deleting the selected recipient
        if recipientToDelete.id == selectedRecipientId {
            // Select another recipient if available
            if customRecipients.count > 1 {
                // Select the next recipient, or previous if this was the last one
                let newIndex = index < customRecipients.count - 1 ? index + 1 : index - 1
                if newIndex >= 0 && newIndex < customRecipients.count && newIndex != index {
                    selectedRecipientId = customRecipients[newIndex].id
                } else {
                    selectedRecipientId = ""
                }
            } else {
                selectedRecipientId = ""
            }
        }
        
        // Remove the recipient
        customRecipients.remove(at: index)
        
        // Save changes
        saveCustomRecipients()
        
        // If no recipients left, make sure nothing is selected
        if customRecipients.isEmpty {
            selectedRecipientId = ""
        }
    }

    private func startDeposit() {
        depositErrorMessage = nil
        let sanitized = depositAmount.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(sanitized), amount > 0 else {
            depositErrorMessage = "Enter a valid amount greater than zero."
            return
        }

        isProcessingDeposit = true

        depositPaymentService.preparePaymentSheet(amount: amount, userId: userId) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isProcessingDeposit = false
                    self.depositErrorMessage = "Unable to start payment: \(error.localizedDescription)"
                }
                return
            }

            DispatchQueue.main.async {
                self.depositPaymentService.present { result in
                    switch result {
                    case .completed:
                        self.profileCashHoldings += amount
                        self.depositAmount = ""
                        self.depositErrorMessage = nil
                        // Sync new balance to backend
                        self.syncPayoutSettings()
                    case .canceled, .failed:
                        break
                    }
                    self.isProcessingDeposit = false
                }
            }
        }
    }

    private func formatDeadlineForBackend(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func saveProfile() {
        profileErrorMessage = nil
        let trimmedName = profileUsername.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = profileEmail.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = profilePhone.trimmingCharacters(in: .whitespaces)
        let trimmedPassword = profilePassword.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            profileErrorMessage = "Name is required."
            return
        }
        guard !trimmedEmail.isEmpty else {
            profileErrorMessage = "Email is required."
            return
        }
        // Phone is optional - no validation needed
        guard !trimmedPassword.isEmpty else {
            profileErrorMessage = "Password is required."
            return
        }

        isSavingProfile = true

        let body: [String: Any] = [
            "fullName": trimmedName,
            "email": trimmedEmail,
            "phone": trimmedPhone,
            "password": trimmedPassword,
            "balanceCents": Int((profileCashHoldings * 100).rounded()),
            "objective_type": "pushups",
            "objective_count": pushupObjective,
            "objective_schedule": scheduleType.lowercased(),
            "objective_deadline": formatDeadlineForBackend(objectiveDeadline),
            "missed_goal_payout": committedPayoutAmount > 0 ? committedPayoutAmount : missedGoalPayout,
            "payout_destination": payoutType.lowercased(),
            "committedPayoutAmount": committedPayoutAmount,
            "payoutCommitted": payoutCommitted,
            "destinationCommitted": destinationCommitted,
            "committedDestination": committedDestination,
            "committedRecipientId": committedRecipientId
        ]

        guard let url = URL(string: "/users/profile", relativeTo: StripeConfig.backendURL) else {
            isSavingProfile = false
            profileErrorMessage = "Invalid backend URL."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSavingProfile = false

                if let error = error {
                    self.profileErrorMessage = "Failed to save: \(error.localizedDescription)"
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    self.profileErrorMessage = "No response from server."
                    return
                }

                if !(200..<300).contains(http.statusCode) {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let detail = json["detail"] as? String {
                            self.profileErrorMessage = "Failed to save profile: \(detail)"
                        } else if let msg = json["error"] as? String {
                            self.profileErrorMessage = msg
                        } else {
                            self.profileErrorMessage = "Failed to save profile (status \(http.statusCode))."
                        }
                    } else {
                        self.profileErrorMessage = "Failed to save profile (status \(http.statusCode))."
                    }
                    return
                }

                // Save userId from response (could be String or Int)
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let id = json["id"] as? String {
                        UserDefaults.standard.set(id, forKey: "userId")
                        print("✅ userId saved: \(id)")
                    } else if let id = json["id"] as? Int {
                        UserDefaults.standard.set(String(id), forKey: "userId")
                        print("✅ userId saved: \(id)")
                    }
                }

                self.profileCompleted = true
                self.isSignedIn = true
                self.profilePassword = ""
                self.profileErrorMessage = nil
                self.isAccountExpanded = false
            }
        }.resume()
    }
    
    // MARK: - Delete Account
    
    private func deleteAccount() {
        guard !deleteAccountPassword.isEmpty else {
            deleteAccountError = "Password is required"
            showDeleteAccountAlert = true
            return
        }
        
        guard !userId.isEmpty else {
            deleteAccountError = "No user ID found"
            showDeleteAccountAlert = true
            return
        }
        
        isDeletingAccount = true
        
        let body: [String: Any] = [
            "userId": userId,
            "email": profileEmail,
            "password": deleteAccountPassword
        ]
        
        guard let url = URL(string: "/users/delete-account", relativeTo: StripeConfig.backendURL) else {
            deleteAccountError = "Invalid backend URL"
            isDeletingAccount = false
            showDeleteAccountAlert = true
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isDeletingAccount = false
                
                if let error = error {
                    self.deleteAccountError = "Failed: \(error.localizedDescription)"
                    self.showDeleteAccountAlert = true
                    return
                }
                
                guard let http = response as? HTTPURLResponse else {
                    self.deleteAccountError = "No response from server"
                    self.showDeleteAccountAlert = true
                    return
                }
                
                if http.statusCode == 401 {
                    self.deleteAccountError = "Incorrect password"
                    self.showDeleteAccountAlert = true
                    return
                }
                
                if !(200..<300).contains(http.statusCode) {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = json["error"] as? String {
                        self.deleteAccountError = errorMsg
                    } else {
                        self.deleteAccountError = "Failed to delete account (status \(http.statusCode))"
                    }
                    self.showDeleteAccountAlert = true
                    return
                }
                
                // Success - clear all local data and sign out
                print("✅ Account deleted successfully")
                if let bundleID = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: bundleID)
                    UserDefaults.standard.synchronize()
                }
                
                // Reset UI state
                self.isAccountExpanded = false
                self.deleteAccountPassword = ""
                self.deleteAccountError = nil
                self.dismiss()
            }
        }.resume()
    }
    
    // MARK: - Balance & Payout Functions
    
    private func refreshBalance() {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        guard let url = URL(string: "/users/\(userId)/balance", relativeTo: StripeConfig.backendURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let balanceCents = json["balanceCents"] as? Int else { return }
            
            DispatchQueue.main.async {
                self.profileCashHoldings = Double(balanceCents) / 100.0
            }
        }.resume()
    }
    
    private func triggerMissedObjectivePayout() {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        guard payoutCommitted && missedGoalPayout > 0 else { return }
        guard profileCashHoldings > 0 else { return }
        
        guard let url = URL(string: "/users/\(userId)/trigger-payout", relativeTo: StripeConfig.backendURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                if let newBalanceCents = json["newBalanceCents"] as? Int {
                    self.profileCashHoldings = Double(newBalanceCents) / 100.0
                }
            }
        }.resume()
    }
    
    // MARK: - Strava Functions
    
    private func connectStrava() {
        guard !userId.isEmpty else {
            print("⚠️ No userId, can't connect Strava")
            return
        }
        
        let stravaConnectURL = "https://api.live-eos.com/strava/connect/\(userId)"
        if let url = URL(string: stravaConnectURL) {
            UIApplication.shared.open(url)
        }
    }
    
    private func disconnectStrava() {
        guard !userId.isEmpty else { return }
        
        guard let url = URL(string: "https://api.live-eos.com/strava/disconnect/\(userId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    self.stravaConnected = false
                    self.stravaAthleteName = ""
                    // Reset to pushups if currently on run
                    if self.objectiveType == "run" {
                        self.objectiveType = "pushups"
                    }
                    print("✅ Strava disconnected")
                }
            }
        }.resume()
    }
    
    private func checkStravaStatus() {
        guard !userId.isEmpty else { return }
        
        isCheckingStrava = true
        
        guard let url = URL(string: "https://api.live-eos.com/strava/status/\(userId)") else {
            isCheckingStrava = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isCheckingStrava = false
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                
                self.stravaConnected = json["connected"] as? Bool ?? false
                self.stravaAthleteName = json["athleteName"] as? String ?? ""
            }
        }.resume()
    }
}

// MARK: - Add Recipient Sheet

struct AddRecipientSheet: View {
    let payerName: String
    let payerEmail: String
    let onComplete: (CustomRecipient) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("missedGoalPayout") private var missedGoalPayout: Double = 0.0
    @AppStorage("profileCompleted") private var profileCompleted: Bool = false
    @State private var generatedInviteCode: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    // ## SMS INVITE FLOW - DISABLED FOR NOW ##
    // @State private var recipientName: String = ""
    // @State private var recipientPhone: String = ""
    // @State private var isSending = false
    // @State private var isContactPickerPresented = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Info Notice
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.white.opacity(0.8))
                        Text("Only one recipient can be active at a time. If a new invite is accepted, they will replace your current recipient.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                
                // MARK: - Generate Code UI (Active)
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            generateInviteCode()
                        }) {
                            HStack {
                                Image(systemName: "qrcode")
                                    .font(.title3)
                                Text(isGenerating ? "Generating..." : "Generate a Code")
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)

                        if let code = generatedInviteCode {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tap to copy & share:")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                
                                Button(action: {
                                    let shareText = "Want to get paid when I miss my goals? 💰\n\nSign up here: live-eos.com/invite-simple\nUse code: \(code)"
                                    UIPasteboard.general.string = shareText
                                    errorMessage = "✅ Copied!"
                                }) {
                                    Text("Want to get paid when I miss my goals? 💰\n\nSign up here: live-eos.com/invite-simple\nUse code: \(code)")
                                        .font(.system(.subheadline, design: .rounded))
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.white)
                                        .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Recipient Invite")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send manually for now:")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                        Text("• Share the invite link + code above")
                            .font(.system(.caption2, design: .rounded))
                        Text("• They will receive your forfeited stakes if you miss")
                            .font(.system(.caption2, design: .rounded))
                    }
                    .padding(.top, 4)
                }
                
                // ## SMS INVITE UI - DISABLED FOR NOW ##
                /*
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            isContactPickerPresented = true
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Import from Contacts")
                                        .font(.system(.body, design: .rounded, weight: .medium))
                                    Text("Select a contact to auto-fill details")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.black.opacity(0.6))
                            }
                            .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        TextField("Recipient Name", text: $recipientName)
                        TextField("Phone Number", text: $recipientPhone)
                            .keyboardType(.phonePad)
                    }
                } header: {
                    Text("Recipient Information")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("An SMS invite will be sent with:")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                        Text("• A unique 8-character invite code")
                            .font(.system(.caption2, design: .rounded))
                        Text("• Link to set up receiving details")
                            .font(.system(.caption2, design: .rounded))
                        Text("• Notification that your $\(String(format: "%.2f", missedGoalPayout)) stakes go to them if you miss")
                            .font(.system(.caption2, design: .rounded))
                    }
                    .padding(.top, 4)
                }
                */

                if let error = errorMessage {
                    Section {
                        HStack {
                            if error.hasPrefix("✅") {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.red)
                            }
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                        }
                        .foregroundStyle(error.hasPrefix("✅") ? Color.green : Color.red)
                    }
                }
            }
            .navigationTitle("Add Recipient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            // ## CONTACT PICKER - DISABLED FOR NOW ##
            // .sheet(isPresented: $isContactPickerPresented) {
            //     ContactPickerView { selectedPhone, selectedName in
            //         recipientPhone = selectedPhone
            //         if recipientName.isEmpty {
            //             recipientName = selectedName
            //         }
            //     }
            // }
        }
    }
    
    // MARK: - Generate Code (calls backend to register in database)
    private func generateInviteCode() {
        errorMessage = nil
        isGenerating = true
        
        guard let url = URL(string: "/recipient-invites/code-only", relativeTo: StripeConfig.backendURL) else {
            errorMessage = "Invalid backend URL."
            isGenerating = false
            return
        }
        
        let body: [String: Any] = [
            "payerEmail": payerEmail,
            "payerName": payerName.isEmpty ? "EOS user" : payerName
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isGenerating = false
                
                if let error = error {
                    self.errorMessage = "Failed to generate code: \(error.localizedDescription)"
                    return
                }
                
                guard let http = response as? HTTPURLResponse else {
                    self.errorMessage = "No response from server."
                    return
                }
                
                if !(200..<300).contains(http.statusCode) {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        self.errorMessage = detail
                    } else {
                        self.errorMessage = "Failed to generate code (status \(http.statusCode))."
                    }
                    return
                }
                
                // Parse invite code from response
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let code = json["inviteCode"] as? String {
                    self.generatedInviteCode = code
                    self.errorMessage = "✅ Code generated and registered!"
                } else {
                    self.errorMessage = "Failed to parse invite code."
                }
            }
        }.resume()
    }

    // ## SMS INVITE FUNCTION - DISABLED FOR NOW ##
    /*
    private func sendInvite() {
        errorMessage = nil
        
        // Check if profile is saved
        if !profileCompleted {
            errorMessage = "Please save your profile first (update your account info)"
            return
        }
        
        // Validate and format phone number
        var formattedPhone = recipientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove all non-digit characters except +
        formattedPhone = formattedPhone.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+")).inverted).joined()
        
        // Ensure phone starts with + for international format
        if !formattedPhone.hasPrefix("+") {
            if formattedPhone.hasPrefix("1") && formattedPhone.count == 11 {
                formattedPhone = "+" + formattedPhone
            } else if formattedPhone.count == 10 {
                formattedPhone = "+1" + formattedPhone // Assume US number
            } else {
                errorMessage = "Please enter a valid 10-digit phone number"
                return
            }
        }
        
        // Validate phone format
        guard formattedPhone.count >= 11 && formattedPhone.count <= 15 else {
            errorMessage = "Please enter a valid phone number"
            return
        }
        
        isSending = true

        let body: [String: Any] = [
            "payerEmail": payerEmail,
            "payerName": payerName.isEmpty ? "Eos user" : payerName,
            "phone": formattedPhone
        ]

        guard let url = URL(string: "/recipient-invites", relativeTo: StripeConfig.backendURL) else {
            errorMessage = "Invalid backend URL."
            isSending = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSending = false

                if let error = error {
                    errorMessage = "Failed to send invite: \(error.localizedDescription)"
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    errorMessage = "No response from server."
                    return
                }

                if !(200..<300).contains(http.statusCode) {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let detail = json["detail"] as? String {
                            if detail.lowercased().contains("payer user not found") || detail.lowercased().contains("user not found") {
                                errorMessage = "⚠️ Please update your account first\nGo to Profile → Account → Update Account"
                            } else {
                                errorMessage = "Error: \(detail)"
                            }
                        } else if let msg = json["error"] as? String {
                            errorMessage = msg
                        } else {
                            errorMessage = "Failed to send invite (status \(http.statusCode))."
                        }
                    } else {
                        errorMessage = "Failed to send invite (status \(http.statusCode))."
                    }
                    return
                }
                
                // Parse the invite code from response
                var inviteCode = "SENT"
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let code = json["inviteCode"] as? String {
                    inviteCode = code
                }

                let newRecipient = CustomRecipient(name: recipientName, phone: formattedPhone)
                
                // Show success with invite code before dismissing
                DispatchQueue.main.async {
                    errorMessage = "✅ Invite sent! Code: \(inviteCode)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        onComplete(newRecipient)
                        dismiss()
                    }
                }
            }
        }.resume()
    }
    */
}

// MARK: - Contact picker view

struct ContactPickerView: UIViewControllerRepresentable {
    let onSelectContact: (String, String) -> Void // phone, name
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactGivenNameKey, CNContactFamilyNameKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView

        init(_ parent: ContactPickerView) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let phoneNumber = contact.phoneNumbers.first?.value.stringValue {
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let displayName = fullName.isEmpty ? "Contact" : fullName
                parent.onSelectContact(phoneNumber, displayName)
            }
            // Don't call dismiss here - the picker dismisses itself
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // Don't call dismiss here - the picker dismisses itself
        }
    }
}

// MARK: - Sign In and Create Account Views

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isSignedIn: Bool
    @Binding var profileUsername: String
    @Binding var profileEmail: String
    @Binding var profilePhone: String
    @Binding var profileCompleted: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    
    // === ALL AppStorage populated from server on sign in ===
    
    // User identity
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("profileCashHoldings") private var profileCashHoldings: Double = 0
    @AppStorage("userTimezone") private var userTimezone: String = "America/Los_Angeles"
    
    // Payout settings
    @AppStorage("missedGoalPayout") private var missedGoalPayout: Double = 0.0
    @AppStorage("payoutCommitted") private var payoutCommitted: Bool = false
    @AppStorage("committedPayoutAmount") private var committedPayoutAmount: Double = 0.0
    @AppStorage("payoutType") private var payoutType: String = "custom"  // Charity removed per App Store
    @AppStorage("destinationCommitted") private var destinationCommitted: Bool = false
    @AppStorage("committedRecipientId") private var committedRecipientId: String = ""
    @AppStorage("committedDestination") private var committedDestination: String = "charity"
    
    // Lock status
    @AppStorage("settingsLockedUntil") private var settingsLockedUntil: Date = Date.distantPast
    
    // Objective settings
    @AppStorage("pushupObjective") private var pushupObjective: Int = 10
    @AppStorage("scheduleType") private var scheduleType: String = "Daily"
    @AppStorage("objectiveDeadline") private var objectiveDeadline: Date = {
        let components = DateComponents(hour: 22, minute: 0)
        return Calendar.current.date(from: components) ?? Date()
    }()
    @AppStorage("objectiveType") private var objectiveType: String = "pushups"
    
    // Multi-objective settings
    @AppStorage("pushupsEnabled") private var pushupsEnabled: Bool = true
    @AppStorage("runEnabled") private var runEnabled: Bool = false
    @AppStorage("runDistance") private var runDistance: Double = 2.0
    
    // Strava
    @AppStorage("stravaConnected") private var stravaConnected: Bool = false
    @AppStorage("stravaAthleteName") private var stravaAthleteName: String = ""
    
    // Today's progress
    @AppStorage("todayPushUpCount") private var todayPushUpCount: Int = 0
    @AppStorage("hasCompletedTodayPushUps") private var hasCompletedTodayPushUps: Bool = false
    @AppStorage("todayRunDistance") private var todayRunDistance: Double = 0.0
    @AppStorage("hasCompletedTodayRun") private var hasCompletedTodayRun: Bool = false
    
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 25) {
                    // Logo
                    Image("EOSLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .padding(.top, 40)
                    
                    Text("Welcome Back")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.black, Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    VStack(spacing: 16) {
                        TextField("Email", text: $email, prompt: Text("Email").foregroundColor(Color.black.opacity(0.5)))
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                            )
                            .foregroundStyle(Color.black)
                        
                        SecureField("Password", text: $password, prompt: Text("Password").foregroundColor(Color.black.opacity(0.5)))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                            )
                            .foregroundStyle(Color.black)
                    }
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                    
                    Button(action: signIn) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Sign In")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                    )
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal)
                    
                    // Forgot password link
                    Button(action: {
                        if let url = URL(string: "https://live-eos.com/forgot-password") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Forgot password?")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.gray)
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                }
            }
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.black)
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.eos_dismissKeyboard()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                }
            }
        }
    }
    
    private func signIn() {
        isLoading = true
        errorMessage = nil
        
        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespaces).lowercased(),
            "password": password.trimmingCharacters(in: .whitespaces)
        ]
        
        guard let url = URL(string: "/signin", relativeTo: StripeConfig.backendURL) else {
            errorMessage = "Invalid backend URL."
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Connection error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid server response"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                if httpResponse.statusCode == 401 {
                    self.errorMessage = "Invalid email or password"
                    return
                }
                
                if httpResponse.statusCode >= 300 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        self.errorMessage = detail
                    } else {
                        self.errorMessage = "Sign in failed (status \(httpResponse.statusCode))"
                    }
                    return
                }
                
                // Parse user data from response and populate ALL profile fields
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let user = json["user"] as? [String: Any] {
                    
                    // === IDENTITY ===
                    if let id = user["id"] as? String {
                        self.userId = id
                        UserDefaults.standard.set(id, forKey: "userId")
                    } else if let id = user["id"] as? Int {
                        self.userId = String(id)
                        UserDefaults.standard.set(String(id), forKey: "userId")
                    }
                    
                    if let fullName = user["full_name"] as? String, !fullName.isEmpty {
                        self.profileUsername = fullName
                    }
                    if let phone = user["phone"] as? String, !phone.isEmpty {
                        self.profilePhone = phone
                    }
                    if let userEmail = user["email"] as? String {
                        self.profileEmail = userEmail
                    } else {
            self.profileEmail = self.email
                    }
                    
                    // === BALANCE ===
                    if let balanceCents = user["balance_cents"] as? Int {
                        self.profileCashHoldings = Double(balanceCents) / 100.0
                    } else {
                        self.profileCashHoldings = 0
                    }
                    
                    // === TIMEZONE ===
                    if let tz = user["timezone"] as? String, !tz.isEmpty {
                        self.userTimezone = tz
                    }
                    
                    // === PAYOUT SETTINGS ===
                    if let missedPayout = user["missed_goal_payout"] as? Double {
                        self.missedGoalPayout = missedPayout
                        self.committedPayoutAmount = missedPayout
                    } else {
                        self.missedGoalPayout = 0
                        self.committedPayoutAmount = 0
                    }
                    if let payoutCommit = user["payout_committed"] as? Bool {
                        self.payoutCommitted = payoutCommit
                    } else {
                        self.payoutCommitted = false
                    }
                    if let destination = user["payout_destination"] as? String {
                        // Force to custom - charity no longer supported
                        self.payoutType = "custom"
                    } else {
                        self.payoutType = "custom"
                    }
                    if let destCommit = user["destination_committed"] as? Bool {
                        self.destinationCommitted = destCommit
                    } else {
                        self.destinationCommitted = false
                    }
                    if let commitDest = user["committed_destination"] as? String {
                        self.committedDestination = commitDest
                    }
                    
                    // === OBJECTIVE SETTINGS ===
                    if let objType = user["objective_type"] as? String {
                        self.objectiveType = objType
                    } else {
                        self.objectiveType = "pushups"
                    }
                    if let objCount = user["objective_count"] as? Int {
                        self.pushupObjective = objCount
                    } else if let pushCount = user["pushups_count"] as? Int {
                        self.pushupObjective = pushCount
                    } else if let pushCount = user["pushups_count"] as? Double {
                        self.pushupObjective = Int(pushCount)
                    }
                    if let objSchedule = user["objective_schedule"] as? String {
                        self.scheduleType = objSchedule.capitalized
                    } else {
                        self.scheduleType = "Daily"
                    }
                    if let objDeadline = user["objective_deadline"] as? String, !objDeadline.isEmpty {
                        // Handle both "HH:mm" and "HH:mm:ss" formats from backend
                        let cleanDeadline = String(objDeadline.prefix(5))
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        if let time = formatter.date(from: cleanDeadline) {
                            self.objectiveDeadline = time
                        }
                    }
                    
                    // === MULTI-OBJECTIVE ===
                    if let pushEnabled = user["pushups_enabled"] as? Bool {
                        self.pushupsEnabled = pushEnabled
                    } else {
                        self.pushupsEnabled = true
                    }
                    if let runEn = user["run_enabled"] as? Bool {
                        self.runEnabled = runEn
                    } else {
                        self.runEnabled = false
                    }
                    if let runDist = user["run_distance"] as? Double {
                        self.runDistance = runDist
                    } else if let runDist = user["run_distance"] as? Int {
                        self.runDistance = Double(runDist)
                    }
                    
                    // === STRAVA ===
                    if let stravaConn = user["strava_connected"] as? Bool {
                        self.stravaConnected = stravaConn
                    } else {
                        self.stravaConnected = false
                    }
                    // Reset athlete name if not connected
                    if !self.stravaConnected {
                        self.stravaAthleteName = ""
                    }
                    
                    // === SETTINGS LOCK ===
                    if let lockDateStr = user["settings_locked_until"] as? String, !lockDateStr.isEmpty {
                        let isoFormatter = ISO8601DateFormatter()
                        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let lockDate = isoFormatter.date(from: lockDateStr) {
                            self.settingsLockedUntil = lockDate
                        } else {
                            isoFormatter.formatOptions = [.withInternetDateTime]
                            if let lockDate = isoFormatter.date(from: lockDateStr) {
                                self.settingsLockedUntil = lockDate
                            } else {
                                self.settingsLockedUntil = Date.distantPast
                            }
                        }
                    } else {
                        self.settingsLockedUntil = Date.distantPast
                    }
                    
                    // === TODAY'S PROGRESS ===
                    if let todayProgress = user["today_progress"] as? [String: Any] {
                        // Pushups progress
                        if let pushups = todayProgress["pushups"] as? [String: Any] {
                            if let completed = pushups["completed"] as? Int {
                                self.todayPushUpCount = completed
                            }
                            if let status = pushups["status"] as? String {
                                self.hasCompletedTodayPushUps = (status == "completed")
                            }
                        } else {
                            self.todayPushUpCount = 0
                            self.hasCompletedTodayPushUps = false
                        }
                        
                        // Run progress
                        if let run = todayProgress["run"] as? [String: Any] {
                            if let completed = run["completed"] as? Double {
                                self.todayRunDistance = completed
                            } else if let completed = run["completed"] as? Int {
                                self.todayRunDistance = Double(completed)
                            }
                            if let status = run["status"] as? String {
                                self.hasCompletedTodayRun = (status == "completed")
                            }
                        } else {
                            self.todayRunDistance = 0.0
                            self.hasCompletedTodayRun = false
                        }
                    } else {
                        self.todayPushUpCount = 0
                        self.hasCompletedTodayPushUps = false
                        self.todayRunDistance = 0.0
                        self.hasCompletedTodayRun = false
                    }
                    
                    // === COMPLETE SIGN IN ===
            self.isSignedIn = true
                    self.profileCompleted = true
            self.dismiss()
                    
                    print("✅ Sign-in complete - loaded all user data")
                } else {
                    self.errorMessage = "Failed to parse user data"
        }

            }
        }.resume()
    }
}

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isSignedIn: Bool
    @Binding var profileUsername: String
    @Binding var profileEmail: String
    @Binding var profilePhone: String
    @Binding var profileCompleted: Bool
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Logo
                        Image("EOSLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .padding(.top, 20)
                        
                        Text("Create Account")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.black, Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1))],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        VStack(spacing: 16) {
                            TextField("Name", text: $name, prompt: Text("Name").foregroundColor(Color.black.opacity(0.5)))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                )
                                .foregroundStyle(Color.black)
                            
                            TextField("Email", text: $email, prompt: Text("Email").foregroundColor(Color.black.opacity(0.5)))
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                )
                                .foregroundStyle(Color.black)
                            
                            SecureField("Password", text: $password, prompt: Text("Password").foregroundColor(Color.black.opacity(0.5)))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                )
                                .foregroundStyle(Color.black)
                        }
                        .padding(.horizontal)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                        
                        Button(action: createAccount) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Create Account")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                        )
                        .disabled(isLoading || name.isEmpty || email.isEmpty || password.isEmpty)
                        .padding(.horizontal)
                        
                        Text("By creating an account, you agree to our Terms of Service")
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.black)
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.eos_dismissKeyboard()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                }
            }
        }
    }
    
    private func createAccount() {
        isLoading = true
        errorMessage = nil
        
        // Save to backend (createOnly blocks duplicate emails)
        let body: [String: Any] = [
            "fullName": name.trimmingCharacters(in: .whitespaces),
            "email": email.trimmingCharacters(in: .whitespaces),
            "password": password.trimmingCharacters(in: .whitespaces),
            "balanceCents": 0,
            "createOnly": true
        ]
        
        guard let url = URL(string: "/users/profile", relativeTo: StripeConfig.backendURL) else {
            errorMessage = "Invalid backend URL."
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Failed to create account: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 300 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        self.errorMessage = detail
                    } else {
                        self.errorMessage = "Failed to create account (status \(httpResponse.statusCode))"
                    }
                    return
                }
                
                // Successfully created account - extract and save userId
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let id = json["id"] as? String {
                        UserDefaults.standard.set(id, forKey: "userId")
                        print("✅ New account created, userId saved: \(id)")
                    } else if let id = json["id"] as? Int {
                        UserDefaults.standard.set(String(id), forKey: "userId")
                        print("✅ New account created, userId saved: \(id)")
                    }
                }
                
                self.profileUsername = self.name
                self.profileEmail = self.email
                self.profilePhone = self.phone
                self.profileCompleted = true
                self.isSignedIn = true
                self.dismiss()
            }
        }.resume()
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}