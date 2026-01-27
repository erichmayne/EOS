import SwiftUI
import AVFoundation
import Vision
import StripePaymentSheet
import ContactsUI
import Combine

// MARK: - Main content view

struct ContentView: View {
    @AppStorage("hasCompletedTodayPushUps") private var hasCompletedTodayPushUps: Bool = false
    @AppStorage("todayPushUpCount") private var todayPushUpCount: Int = 0
    @AppStorage("pushupObjective") private var pushupObjective: Int = 10
    @AppStorage("objectiveDeadline") private var objectiveDeadline: Date = {
        let components = DateComponents(hour: 22, minute: 0)
        return Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? Date()
    }()
    @AppStorage("scheduleType") private var scheduleType: String = "Daily"
    @AppStorage("profileUsername") private var profileUsername: String = ""
    @AppStorage("profileEmail") private var profileEmail: String = ""
    @AppStorage("profileCompleted") private var profileCompleted: Bool = false

    @State private var showObjectiveSettings = false
    @State private var showProfileView = false
    @State private var showPushUpSession = false

    private let notificationManager = NotificationManager()

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
        todayPushUpCount >= pushupObjective
    }

    var timeUntilDeadline: String {
        if !shouldShowObjective {
            return "No objective today"
        }

        let now = Date()
        let todayDeadline = combineDateWithTodayTime(objectiveDeadline)
        let timeInterval = todayDeadline.timeIntervalSince(now)

        if timeInterval <= 0 {
            return "Deadline passed"
        }

        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        let seconds = Int(timeInterval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
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
                        VStack(spacing: 16) {
                            Text("Today's Goal: \(pushupObjective) Pushups")
                                .font(.system(.title3, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.black)

                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                                VStack(spacing: 20) {
                                    HStack {
                                        Text("\(todayPushUpCount)")
                                            .font(.system(size: 72, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.black)
                                        Text("/ \(pushupObjective)")
                                            .font(.system(size: 36, weight: .light, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.4))
                                    }

                                    if shouldShowObjective {
                                        HStack {
                                            Circle()
                                                .fill(objectiveMet ? Color.green : Color.red.opacity(0.8))
                                                .frame(width: 10, height: 10)
                                            Text(objectiveMet ? "Objective met" : "Objective not met")
                                                .font(.system(.subheadline, design: .rounded))
                                                .foregroundStyle(objectiveMet ? Color.green : Color.red.opacity(0.8))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill((objectiveMet ? Color.green : Color.red).opacity(0.1))
                                        )
                                    }

                                    if shouldShowObjective {
                                        let deadline = combineDateWithTodayTime(objectiveDeadline)
                                        Text("Complete by: \(deadline, style: .time) - \(timeUntilDeadline)")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(0.65))
                                    }
                                }
                                .padding(30)
                            }
                            .frame(maxWidth: 350)
                        }
                        .padding(.horizontal)

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
                    objective: $pushupObjective,
                    deadline: $objectiveDeadline,
                    scheduleType: $scheduleType
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
                                todayPushUpCount += cameraViewModel.pushupCount
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
}

// MARK: - Objective settings view

struct ObjectiveSettingsView: View {
    @Binding var objective: Int
    @Binding var deadline: Date
    @Binding var scheduleType: String
    @Environment(\.dismiss) private var dismiss
    @State private var tempObjective: Int = 10
    @State private var tempDeadline: Date = Date()
    @State private var tempScheduleType: String = "Daily"

    private let notificationManager = NotificationManager()

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                Form {
                    Section(header: Text("Daily Push-up Objective")
                        .foregroundStyle(Color.white)) {
                        Picker("", selection: $tempObjective) {
                            ForEach(1...100, id: \.self) { count in
                                Text("\(count) pushups")
                                    .tag(count)
                                    .foregroundStyle(Color.black)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                        .labelsHidden()
                    }
                    .listRowBackground(Color.white)

                    Section(header: Text("Schedule & Deadline")
                        .foregroundStyle(Color.white)) {
                        VStack(spacing: 16) {
                            Picker("", selection: $tempScheduleType) {
                                Text("Daily").tag("Daily")
                                Text("Weekdays (Mon-Fri)").tag("Weekdays")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onAppear {
                                UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)
                                UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                                UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black], for: .normal)
                            }
                            
                            Text(tempScheduleType == "Daily" ? "Complete every day" : "Complete Monday through Friday")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.8))
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            DatePicker("", selection: $tempDeadline, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: 120)
                                .tint(Color.black)
                                .colorScheme(.light)
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.white)

                    Section(footer: Text("You'll receive a notification if you haven't completed your objective by the deadline.")
                        .foregroundStyle(Color.white.opacity(0.95))) {
                        EmptyView()
                    }
                }
                .scrollContentBackground(.hidden)
                .tint(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
            }
            .navigationTitle("My Objective")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        objective = tempObjective
                        deadline = tempDeadline
                        scheduleType = tempScheduleType
                        notificationManager.scheduleObjectiveReminder(
                            deadline: deadline,
                            objective: objective,
                            scheduleType: scheduleType
                        )
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                }
            }
        }
        .onAppear {
            tempObjective = objective
            tempDeadline = deadline
            tempScheduleType = scheduleType
        }
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
        content.body = "You didn't complete your \(objective) push-ups today. Payout will be sent to your selected recipient."
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

    func preparePaymentSheet(amount: Double, completion: @escaping (Error?) -> Void) {
        let cents = max(1, Int((amount * 100).rounded()))

        var request = URLRequest(url: StripeConfig.backendURL.appendingPathComponent("/create-payment-intent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
        let payload: [String: Any] = ["amount": cents, "userId": userId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(error)
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let customerId = json["customer"] as? String,
                let ephemeralKeySecret = json["ephemeralKeySecret"] as? String,
                let clientSecret = json["paymentIntentClientSecret"] as? String
            else {
                completion(NSError(domain: "Stripe", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"]))
                return
            }

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "EOS"
            configuration.customer = .init(id: customerId, ephemeralKeySecret: ephemeralKeySecret)
            
            // Apple Pay disabled temporarily until account approval
            configuration.applePay = nil
            // configuration.applePay = .init(
            //     merchantId: "merchant.com.emayne.eos",
            //     merchantCountryCode: "US"
            // )
            
            // Allow delayed payment methods if available
            configuration.allowsDelayedPaymentMethods = true
            
            // Return URL for app redirects (optional)
            // configuration.returnURL = "eos-app://stripe-redirect"

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
    let phone: String
    let status: String // "pending", "active", "inactive"
    
    init(name: String, phone: String) {
        self.id = UUID().uuidString
        self.name = name
        self.phone = phone
        self.status = "pending"
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
                        .foregroundStyle(.primary)
                    Text(recipient.phone)
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
                            .fill(recipient.status == "active" 
                                ? Color.green.opacity(0.15) 
                                : Color.orange.opacity(0.15))
                    )
                    .foregroundStyle(recipient.status == "active" 
                        ? Color.green.opacity(0.9) 
                        : Color.orange.opacity(0.9))
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
    
    // Payout Destination Settings
    @AppStorage("payoutType") private var payoutType: String = "charity"
    @AppStorage("selectedCharity") private var selectedCharity: String = "Global Learning Fund"
    @AppStorage("customRecipientsData") private var customRecipientsData: Data = Data()
    @AppStorage("selectedRecipientId") private var selectedRecipientId: String = ""
    @AppStorage("missedGoalPayout") private var missedGoalPayout: Double = 0.0
    @AppStorage("payoutCommitted") private var payoutCommitted: Bool = false
    @AppStorage("committedPayoutAmount") private var committedPayoutAmount: Double = 0.0

    @State private var depositAmount: String = ""
    @State private var showPayoutSelector: Bool = false
    @StateObject private var depositPaymentService = DepositPaymentService()
    @State private var isProcessingDeposit = false
    @State private var depositErrorMessage: String?

    @State private var profilePassword: String = ""
    @State private var profileErrorMessage: String?
    @State private var isSavingProfile = false
    @State private var isAccountExpanded: Bool = false
    @State private var customRecipients: [CustomRecipient] = []
    @State private var showingAddRecipient = false
    @State private var showSignInView = false
    @State private var showCreateAccountView = false
    @FocusState private var isPayoutAmountFocused: Bool
    @FocusState private var isDepositAmountFocused: Bool

    private let charities = [
        "Global Learning Fund",
        "Clean Water Initiative",
        "Open Source Labs",
        "Youth Sports Foundation",
        "Environmental Defense Fund",
        "Doctors Without Borders"
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
                                            Image(systemName: "phone")
                                                .font(.caption)
                                                .foregroundStyle(Color.black.opacity(0.6))
                                                .frame(width: 20)
                                            TextField("Phone", text: $profilePhone)
                                                .font(.system(.subheadline, design: .rounded))
                                                .keyboardType(.phonePad)
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
                                    
                                    Button(action: {
                                        // Sign out
                                        isSignedIn = false
                                        profileUsername = ""
                                        profileEmail = ""
                                        profilePhone = ""
                                        profilePassword = ""
                                        profileCompleted = false
                                        isAccountExpanded = false
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
                
                // Payout Destination Section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Type selector
                        HStack(spacing: 12) {
                            PayoutTypeButton(
                                title: "Charity",
                                icon: "heart.fill",
                                isSelected: payoutType == "charity",
                                action: { payoutType = "charity" }
                            )
                            PayoutTypeButton(
                                title: "Custom",
                                icon: "person.2.fill",
                                isSelected: payoutType == "custom",
                                action: { payoutType = "custom" }
                            )
                        }
                        .padding(.vertical, 4)
                        
                        // Content based on selection
                        if payoutType == "charity" {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Select charity")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.6))
                                Picker("Charity", selection: $selectedCharity) {
                                    ForEach(charities, id: \.self) { charity in
                                        Text(charity).tag(charity)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        } else {
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
                                                        selectedRecipientId = recipient.id 
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
                        
                    }
                    .listRowBackground(Color.white)
                } header: {
                    Text("Payout Destination")
                        .foregroundStyle(Color.white.opacity(0.95))
                } footer: {
                    Text("Select where missed goal payouts will be sent.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                
                // Missed Goal Payout Amount - Separate prominent section
                Section {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Payout Amount")
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                Text("Amount sent per missed goal")
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
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("Done") {
                                                isPayoutAmountFocused = false
                                            }
                                            .font(.system(.body, design: .rounded, weight: .medium))
                                            .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                                        }
                                    }
                            }
                        }
                        
                        // Quick select amounts
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                ForEach([10.0, 50.0, 100.0], id: \.self) { amount in
                                    Button(action: { 
                                        missedGoalPayout = amount
                                        isPayoutAmountFocused = false // Dismiss keyboard
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
                                // Focus on the text field and clear if it's a preset amount
                                if missedGoalPayout == 10 || missedGoalPayout == 50 || missedGoalPayout == 100 {
                                    missedGoalPayout = 0 // Clear for new custom input
                                }
                                isPayoutAmountFocused = true // Show keyboard
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
                    }
                    .listRowBackground(Color.white)
                } header: {
                    Text("Missed Goal Payout")
                        .foregroundStyle(Color.white.opacity(0.95))
                } footer: {
                    Text("This amount will be deducted from your balance and sent to your selected destination each time you miss your daily goal.")
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
                    Text("Add funds to cover missed goal payouts")
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
                        UIApplication.shared.eos_dismissKeyboard()
                    }
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isDepositAmountFocused = false
                        isPayoutAmountFocused = false
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Color(UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)))
                }
            }
            .sheet(isPresented: $showSignInView) {
                SignInView(isSignedIn: $isSignedIn, profileEmail: $profileEmail)
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
            .onAppear {
                loadCustomRecipients()
            }
        }
    
    private var isProfileValid: Bool {
        !profileUsername.isEmpty && !profileEmail.isEmpty && 
        !profilePhone.isEmpty && !profilePassword.isEmpty
    }
    
    private func loadCustomRecipients() {
        if let decoded = try? JSONDecoder().decode([CustomRecipient].self, from: customRecipientsData) {
            customRecipients = decoded
        }
    }
    
    private func saveCustomRecipients() {
        if let encoded = try? JSONEncoder().encode(customRecipients) {
            customRecipientsData = encoded
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

        depositPaymentService.preparePaymentSheet(amount: amount) { error in
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
                        // SYNC BALANCE TO SERVER
                        self.syncBalanceToServer(newBalance: self.profileCashHoldings)
                    case .canceled, .failed:
                        break
                    }
                    self.isProcessingDeposit = false
                }
            }
        }
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
        guard !trimmedPhone.isEmpty else {
            profileErrorMessage = "Phone number is required."
            return
        }
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
            "objective_count": 50,
            "objective_schedule": "daily",
            "objective_deadline": "09:00",
            "missed_goal_payout": committedPayoutAmount > 0 ? committedPayoutAmount : missedGoalPayout,
            "payout_destination": payoutType.lowercased(),
            "committedPayoutAmount": committedPayoutAmount,
            "payoutCommitted": payoutCommitted
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

                self.profileCompleted = true
                self.isSignedIn = true
                self.profilePassword = ""
                self.profileErrorMessage = nil
                self.isAccountExpanded = false
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
    @State private var recipientName: String = ""
    @State private var recipientPhone: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isContactPickerPresented = false

    var body: some View {
        NavigationView {
            Form {
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
                        Text("• Link to set up payout details")
                            .font(.system(.caption2, design: .rounded))
                        Text("• Notification that they'll receive $\(String(format: "%.2f", missedGoalPayout)) per missed goal")
                            .font(.system(.caption2, design: .rounded))
                    }
                    .padding(.top, 4)
                }

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
                    Button(isSending ? "Sending…" : "Send Invite") {
                        sendInvite()
                    }
                    .disabled(isSending || recipientName.isEmpty || recipientPhone.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.eos_dismissKeyboard()
                    }
                }
            }
            .sheet(isPresented: $isContactPickerPresented) {
                ContactPickerView { selectedPhone, selectedName in
                    recipientPhone = selectedPhone
                    if recipientName.isEmpty {
                        recipientName = selectedName
                    }
                }
            }
        }
    }

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
    @Binding var profileEmail: String
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
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
                    
                    Spacer()
                }
            }
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.black)
            )
        }
    }
    
    private func signIn() {
        isLoading = true
        errorMessage = nil
        
        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespaces),
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
                
                // Parse user data from response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let user = json["user"] as? [String: Any] {
                    // Populate profile fields from database
                    if let fullName = user["full_name"] as? String {
                        self.profileUsername = fullName
                    }
                    if let phone = user["phone"] as? String {
                        self.profilePhone = phone
                    }
                }
                
                self.profileEmail = self.email
                self.isSignedIn = true
                self.profileCompleted = true
                self.dismiss()
            }
        }.resume()
    }
}

// Bindings extension for SignInView
extension SignInView {
    @Binding var profileUsername: String { get { _profileUsername } }
    @Binding var profilePhone: String { get { _profilePhone } }
    @Binding var profileCompleted: Bool { get { _profileCompleted } }
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
                            
                            TextField("Phone", text: $phone, prompt: Text("Phone").foregroundColor(Color.black.opacity(0.5)))
                                .keyboardType(.phonePad)
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
                        .disabled(isLoading || name.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty)
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
        }
    }
    
    private func createAccount() {
        isLoading = true
        errorMessage = nil
        
        // Save to backend
        let body: [String: Any] = [
            "fullName": name.trimmingCharacters(in: .whitespaces),
            "email": email.trimmingCharacters(in: .whitespaces),
            "phone": phone.trimmingCharacters(in: .whitespaces),
            "password": password.trimmingCharacters(in: .whitespaces),
            "balanceCents": 0
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
                
                // Successfully created account
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

// MARK: - Previewstruct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
