import AppKit
import UserNotifications

/// Sensibilité des alertes, réglable dans les Réglages.
enum AlertSensitivity: String, CaseIterable, Identifiable {
    case low, normal, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "宽松"
        case .normal: "正常"
        case .high: "敏感"
        }
    }

    var runawayWatts: Double {
        switch self { case .low: 2.5; case .normal: 1.5; case .high: 1.0 }
    }
    var backgroundWatts: Double {
        switch self { case .low: 3.0; case .normal: 2.0; case .high: 1.5 }
    }
    var runawayImpact: Double {
        switch self { case .low: 160; case .normal: 100; case .high: 70 }
    }
    var backgroundImpact: Double {
        switch self { case .low: 220; case .normal: 150; case .high: 100 }
    }
    /// Nombre de constats consécutifs (espacés de 15 s) avant notification.
    var requiredStreak: Int {
        switch self { case .low: 4; case .normal: 3; case .high: 2 }
    }
}

/// Le garde du corps : surveille le classement et notifie quand une app
/// s'emballe ou pèse lourd en arrière-plan — uniquement sur batterie, là où
/// ça coûte des minutes d'autonomie.
///
/// Anti-spam : condition soutenue (3 constats espacés de 15 s), silence de
/// 30 min par app après notification, « Ignorer » = 2 h.
@MainActor
@Observable
final class AlertService {
    private static let category = "juiceflow.appAlert"

    @ObservationIgnored private let battery: BatteryService
    @ObservationIgnored private let processes: ProcessService
    @ObservationIgnored private var streaks: [String: Int] = [:]
    @ObservationIgnored private var cooldowns: [String: Date] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let delegate = NotificationDelegate()

    init(battery: BatteryService, processes: ProcessService) {
        self.battery = battery
        self.processes = processes

        // UNUserNotificationCenter exige un vrai bundle .app et fait aborter
        // le processus sinon : lancé en binaire nu (`swift run`), le garde
        // du corps reste au vestiaire plutôt que de crasher l'app.
        guard Bundle.main.bundleIdentifier != nil else { return }
        configureNotifications()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15), tolerance: .seconds(3))
                self?.evaluate()
            }
        }

        // Test de bout en bout du tuyau (permission, bannière, actions) :
        // build/JuiceFlow.app/Contents/MacOS/JuiceFlow --test-alert
        if ProcessInfo.processInfo.arguments.contains("--test-alert") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.sendTestAlert()
            }
        }
    }

    // MARK: - Configuration

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        let quit = UNNotificationAction(identifier: "quit", title: "退出 App",
                                        options: [.destructive])
        let snooze = UNNotificationAction(identifier: "snooze", title: "忽略 2 小时")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [quit, snooze],
                                   intentIdentifiers: [])
        ])

        delegate.onQuit = { pid in
            Task { @MainActor in
                NSRunningApplication(processIdentifier: pid)?.terminate()
            }
        }
        delegate.onSnooze = { [weak self] name in
            Task { @MainActor in
                self?.cooldowns[name] = .now.addingTimeInterval(2 * 3600)
            }
        }
        center.delegate = delegate

        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    // MARK: - Surveillance

    private var alertsEnabled: Bool {
        UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool ?? true
    }

    private var sensitivity: AlertSensitivity {
        AlertSensitivity(rawValue: UserDefaults.standard.string(forKey: "alertSensitivity") ?? "")
            ?? .normal
    }

    private func evaluate() {
        // Branché, une app gourmande ne coûte pas d'autonomie : silence.
        guard alertsEnabled, battery.snapshot.state == .discharging else {
            streaks.removeAll()
            return
        }

        let sensitivity = sensitivity
        var stillHeavy = Set<String>()
        for app in processes.apps.prefix(12) {
            let heavyRunaway = app.isRunaway
                && (app.watts.map { $0 >= sensitivity.runawayWatts }
                    ?? (app.energyImpact >= sensitivity.runawayImpact))
            let heavyBackground = app.isBackgroundActive
                && (app.watts.map { $0 >= sensitivity.backgroundWatts }
                    ?? (app.energyImpact >= sensitivity.backgroundImpact))
            guard heavyRunaway || heavyBackground else { continue }

            stillHeavy.insert(app.name)
            streaks[app.name, default: 0] += 1
            guard streaks[app.name, default: 0] >= sensitivity.requiredStreak,
                  cooldowns[app.name].map({ $0 < .now }) ?? true else { continue }

            notify(app, runaway: heavyRunaway)
            cooldowns[app.name] = .now.addingTimeInterval(30 * 60)
            streaks[app.name] = 0
        }
        // Une app revenue à la normale repart de zéro.
        streaks = streaks.filter { stillHeavy.contains($0.key) }
    }

    private func notify(_ app: AppPower, runaway: Bool) {
        let content = UNMutableNotificationContent()
        content.title = runaway
            ? "\(app.name) 功耗异常 🔥"
            : "\(app.name) 后台耗电 🌙"
        var body = "当前约 \(app.displayValue)。"
        if let watts = app.sustainedWatts,
           let gain = battery.autonomyGainMinutes(freeingWatts: watts) {
            body += " 退出可多 \(TimeFormat.gain(gain)) 续航。"
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["pid": Int(app.id), "name": app.name]

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "juiceflow.alert.\(app.name)",
                                  content: content, trigger: nil)
        )
    }

    private func sendTestAlert() {
        let content = UNMutableNotificationContent()
        content.title = "JuiceFlow 测试 🔥"
        content.body = "通知通道正常。退出 / 忽略按钮已连接。"
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["pid": -1, "name": "test"]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "juiceflow.alert.test", content: content, trigger: nil)
        )
    }
}

/// Réceptionne les actions des notifications (fil quelconque → MainActor).
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onQuit: (@Sendable (pid_t) -> Void)?
    var onSnooze: (@Sendable (String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case "quit":
            if let pid = info["pid"] as? Int, pid > 0 { onQuit?(pid_t(pid)) }
        case "snooze":
            if let name = info["name"] as? String { onSnooze?(name) }
        default:
            break
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
