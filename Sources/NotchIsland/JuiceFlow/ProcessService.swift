import AppKit
import Observation

/// Consommation agrégée d'une application (ou d'un daemon système) :
/// tous ses processus regroupés sous le PID responsable.
struct AppPower: Identifiable {
    let id: pid_t
    var name: String
    var bundleID: String?
    var icon: NSImage?
    /// Métrique de classement. En estimation : score façon Moniteur
    /// d'activité (~100 ≈ un cœur saturé). En précision : milliwatts.
    var energyImpact: Double
    /// Puissance réelle en watts — uniquement en mode précision.
    var watts: Double?
    var cpuPercent: Double     // % d'un cœur (peut dépasser 100 en multithread)
    var wakeupsPerSec: Double
    var processCount: Int
    /// Dernières valeurs lissées (~2 min), pour sparkline et détection.
    var history: [Double] = []
    /// Les sous-processus les plus gourmands du groupe (max 3).
    /// `metric` : milliwatts en précision, % CPU en estimation.
    var topChildren: [ProcessShare] = []
    /// GPU en % d'utilisation équivalente — mode précision uniquement.
    var gpuPercent: Double = 0
    /// 🔥 : consommation en forte hausse par rapport à sa propre moyenne.
    var isRunaway = false
    /// 🌙 : app graphique qui consomme alors qu'elle n'est pas au premier plan.
    var isBackgroundActive = false

    /// Puissance soutenue (moyenne ~1 min de l'historique lissé) : la valeur
    /// à utiliser pour les projections d'autonomie, pas l'instantanée.
    var sustainedWatts: Double? {
        guard watts != nil, !history.isEmpty else { return watts }
        let window = history.suffix(20)
        return window.reduce(0, +) / Double(window.count) / 1000
    }
}

struct ProcessShare: Equatable, Sendable {
    var name: String
    var metric: Double
}

extension AppPower: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.energyImpact == rhs.energyImpact
            && lhs.watts == rhs.watts && lhs.cpuPercent == rhs.cpuPercent
            && lhs.processCount == rhs.processCount && lhs.history == rhs.history
            && lhs.isRunaway == rhs.isRunaway
            && lhs.isBackgroundActive == rhs.isBackgroundActive
            && lhs.topChildren == rhs.topChildren && lhs.gpuPercent == rhs.gpuPercent
    }
}

@MainActor
@Observable
final class ProcessService {
    enum ImpactSource: Equatable {
        case estimation   // deltas CPU libproc, sans privilèges
        case precision    // powermetrics : mesure officielle Apple
    }

    private(set) var apps: [AppPower] = []
    private(set) var trackedProcessCount = 0
    private(set) var source: ImpactSource = .estimation
    let powerMetrics = PowerMetricsService()

    @ObservationIgnored private var previous: ProcessSampler.Snapshot?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var iconCache: [pid_t: NSImage] = [:]
    @ObservationIgnored private var smoothedImpacts: [pid_t: Double] = [:]
    @ObservationIgnored private var histories: [pid_t: [Double]] = [:]

    @ObservationIgnored private var hasViewers = false
    @ObservationIgnored private var windowVisible = false

    init() {
        previous = ProcessSampler.snapshot()
        // Bascule en précision dès le premier échantillon powermetrics, sans
        // attendre le tick suivant : au lancement, les watts remplacent le
        // spinner directement — jamais le score pour 3 s d'abord.
        powerMetrics.onSample = { [weak self] in
            guard let self, source != .precision else { return }
            refresh()
        }
        restartPolling(every: .seconds(3))
    }

    // MARK: - Cadence pilotée par la visibilité

    /// Recale l'état « quelqu'un regarde » sur la visibilité RÉELLE des
    /// fenêtres. Compter les onAppear/onDisappear ne marche pas : selon la
    /// version de macOS, SwiftUI garde les vues vivantes (fenêtre fermée ou
    /// app masquée sans onDisappear) et le compteur restait bloqué — cadence
    /// rapide à vie. Ici, constat idempotent : appelé par les callbacks des
    /// vues quand ils arrivent (réaction immédiate), et par chaque tick de
    /// sondage en filet de sécurité (auto-réparation en ≤ 3 s en cadence
    /// rapide, ≤ 30 s en lente).
    func syncViewers() {
        applyViewerState()
        // Les fenêtres changent d'état au tour de boucle qui SUIT
        // l'événement (onAppear précède l'affichage réel) : second constat.
        DispatchQueue.main.async { [weak self] in self?.applyViewerState() }
    }

    private func applyViewerState() {
        let mainVisible = NSApp.windows.contains {
            $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true
        }
        let popoverVisible = NSApp.windows.contains {
            $0.isVisible && String(describing: type(of: $0)).hasPrefix("MenuBarExtraWindow")
        }

        if mainVisible != windowVisible {
            windowVisible = mainVisible
            // Présence dans le Dock alignée sur la fenêtre : app normale
            // quand elle est visible, accessoire (barre des menus) sinon.
            NSApp.setActivationPolicy(mainVisible ? .regular : .accessory)
        }

        let watching = mainVisible || popoverVisible
        guard watching != hasViewers else { return }
        hasViewers = watching
        if watching {
            restartPolling(every: .seconds(3))
            powerMetrics.setCadence(seconds: 3)
            Task { await powerMetrics.resumeIfAuthorized() }
            refresh()
        } else {
            // Cadence lente mais jamais d'arrêt : l'historique par app
            // continue de s'écrire pour quelques milliwatts.
            powerMetrics.setCadence(seconds: 30)
            restartPolling(every: .seconds(30))
        }
    }

    private func restartPolling(every interval: Duration) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // La tolérance laisse macOS regrouper nos réveils (App Nap).
                try? await Task.sleep(for: interval, tolerance: .seconds(1))
                self?.refresh()
            }
        }
    }

    private func refresh() {
        applyViewerState()

        if powerMetrics.isFresh {
            publish(Self.fromPowerMetrics(powerMetrics.tasks, iconCache: &iconCache),
                    processCount: powerMetrics.tasks.count,
                    source: .precision)
            // Pas de re-échantillonnage libproc ici : les compteurs CPU sont
            // cumulatifs, le snapshot `previous` restera une base valide au
            // moment du repli (moyenne sur la période écoulée).
            return
        }

        // Flux précision en cours de (re)démarrage : on garde l'affichage tel
        // quel quelques secondes plutôt que de flasher le score estimation
        // puis de rebasculer en watts. Si le flux reste muet, `isWarmingUp`
        // expire de lui-même et le repli estimation reprend au tick suivant.
        if powerMetrics.isWarmingUp, source == .precision || apps.isEmpty { return }

        let current = ProcessSampler.snapshot()
        if let previous {
            publish(Self.aggregate(from: previous, to: current, iconCache: &iconCache),
                    processCount: current.usage.count,
                    source: .estimation)
        }
        previous = current
    }

    /// Lissage EMA, historique, badges, tri : commun aux deux sources.
    private func publish(_ freshList: [AppPower], processCount: Int, source: ImpactSource) {
        if source != self.source {
            // Changement d'unité (score ⇄ milliwatts) : on repart à zéro.
            smoothedImpacts.removeAll()
            histories.removeAll()
        }
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let runawayFloor = source == .precision ? 1000.0 : 60.0      // 1 W / gros score
        let backgroundFloor = source == .precision ? 800.0 : 50.0

        var list = freshList
        for index in list.indices {
            let id = list[index].id
            if let prior = smoothedImpacts[id] {
                list[index].energyImpact = prior * 0.55 + list[index].energyImpact * 0.45
            }
            let smoothed = list[index].energyImpact
            smoothedImpacts[id] = smoothed

            var history = histories[id] ?? []
            history.append(smoothed)
            if history.count > 40 { history.removeFirst(history.count - 40) }
            histories[id] = history
            list[index].history = history

            // 🔥 : nettement au-dessus de sa propre moyenne récente
            // (le badge s'éteint de lui-même quand la moyenne rattrape).
            if history.count >= 8 {
                let baseline = history.dropLast(4).suffix(16)
                let average = baseline.reduce(0, +) / Double(baseline.count)
                list[index].isRunaway = smoothed > max(average * 3, runawayFloor)
            }

            // 🌙 : app graphique, pas au premier plan, consommation notable.
            list[index].isBackgroundActive = list[index].icon != nil
                && list[index].id != frontmostPid
                && smoothed > backgroundFloor
        }

        let alive = Set(list.map(\.id))
        smoothedImpacts = smoothedImpacts.filter { alive.contains($0.key) }
        histories = histories.filter { alive.contains($0.key) }
        if source == .precision {
            // En précision, la métrique lissée est en milliwatts.
            for index in list.indices { list[index].watts = list[index].energyImpact / 1000 }
        }
        apps = list.sorted { $0.energyImpact > $1.energyImpact }
        trackedProcessCount = processCount
        self.source = source
    }

    /// Construit le classement depuis les tâches powermetrics, regroupées par
    /// application via le PID responsable (comme le mode estimation).
    static func fromPowerMetrics(
        _ pmTasks: [PMTask], iconCache: inout [pid_t: NSImage]
    ) -> [AppPower] {
        struct Group {
            var impact = 0.0
            var cpuMs = 0.0
            var gpuMs = 0.0
            var count = 0
            var leaderName: String?
            var members: [(name: String, impact: Double)] = []
        }
        var groups: [pid_t: Group] = [:]

        for task in pmTasks {
            let rpid = task.pid > 0 ? ProcessSampler.responsiblePid(task.pid) : task.pid
            var group = groups[rpid, default: Group()]
            group.impact += task.energyImpact
            group.cpuMs += task.cpuMsPerS
            group.gpuMs += task.gpuMsPerS
            group.count += 1
            if rpid == task.pid { group.leaderName = task.name }
            group.members.append((task.name, task.energyImpact))
            groups[rpid] = group
        }

        return groups.compactMap { rpid, group in
            guard group.impact >= 5 else { return nil }  // < 5 mW : bruit
            var identity = resolveIdentity(rpid, iconCache: &iconCache)
            // powermetrics voit des processus que libproc ne peut pas nommer
            // sans privilèges (WindowServer, kernel…) : son nom fait foi.
            if identity.icon == nil, identity.name.hasPrefix("PID "), let leader = group.leaderName {
                identity.name = friendlyDaemonNames[leader] ?? leader
            }
            let children = group.members.sorted { $0.impact > $1.impact }.prefix(3)
                .map { ProcessShare(name: $0.name, metric: $0.impact) }
                .filter { $0.metric >= 1 }  // pas de lignes « 0 mW »
            return AppPower(
                id: rpid,
                name: identity.name,
                bundleID: identity.bundleID,
                icon: identity.icon,
                energyImpact: group.impact,  // milliwatts
                watts: group.impact / 1000,
                cpuPercent: group.cpuMs / 10,  // ms par seconde → % d'un cœur
                wakeupsPerSec: 0,
                processCount: group.count,
                topChildren: Array(children),
                gpuPercent: group.gpuMs / 10
            )
        }
        .sorted { $0.energyImpact > $1.energyImpact }
    }

    /// Agrège les deltas d'énergie/CPU entre deux échantillons par application.
    /// Statique et réutilisée par le mode CLI `--top`.
    static func aggregate(
        from previous: ProcessSampler.Snapshot,
        to current: ProcessSampler.Snapshot,
        iconCache: inout [pid_t: NSImage]
    ) -> [AppPower] {
        let components = previous.instant.duration(to: current.instant).components
        let elapsed = max(Double(components.seconds) + Double(components.attoseconds) / 1e18, 0.1)

        struct Group {
            var cpuNS: UInt64 = 0
            var wakeups: UInt64 = 0
            var count = 0
            var members: [(pid: pid_t, cpuNS: UInt64)] = []
        }
        var groups: [pid_t: Group] = [:]

        for (pid, now) in current.usage {
            // Processus apparu en cours de fenêtre : servira de base au tour suivant.
            guard let before = previous.usage[pid], now.cpuNS >= before.cpuNS else { continue }
            let rpid = ProcessSampler.responsiblePid(pid)
            var group = groups[rpid, default: Group()]
            group.cpuNS += now.cpuNS - before.cpuNS
            group.wakeups += now.idleWakeups >= before.idleWakeups
                ? now.idleWakeups - before.idleWakeups : 0
            group.count += 1
            group.members.append((pid, now.cpuNS - before.cpuNS))
            groups[rpid] = group
        }

        return groups.compactMap { rpid, group in
            let cpuPercent = Double(group.cpuNS) / 1e9 / elapsed * 100
            let wakeupsPerSec = Double(group.wakeups) / elapsed
            // Approximation du « impact énergétique » du Moniteur d'activité.
            let impact = cpuPercent + 0.2 * wakeupsPerSec
            guard impact >= 0.1 else { return nil }  // bruit
            let identity = resolveIdentity(rpid, iconCache: &iconCache)
            let children = group.members.sorted { $0.cpuNS > $1.cpuNS }.prefix(3)
                .map {
                    ProcessShare(name: ProcessSampler.name(of: $0.pid) ?? "PID \($0.pid)",
                                 metric: Double($0.cpuNS) / 1e9 / elapsed * 100)
                }
                .filter { $0.metric >= 0.1 }  // pas de lignes « 0 % »
            return AppPower(
                id: rpid,
                name: identity.name,
                bundleID: identity.bundleID,
                icon: identity.icon,
                energyImpact: impact,
                cpuPercent: cpuPercent,
                wakeupsPerSec: wakeupsPerSec,
                processCount: group.count,
                topChildren: Array(children)
            )
        }
        .sorted { $0.energyImpact > $1.energyImpact }
    }

    // MARK: - Identité des apps

    private static func resolveIdentity(
        _ pid: pid_t, iconCache: inout [pid_t: NSImage]
    ) -> (name: String, bundleID: String?, icon: NSImage?) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if iconCache[pid] == nil, let icon = app.icon {
                iconCache[pid] = icon
            }
            return (app.localizedName ?? ProcessSampler.name(of: pid) ?? "PID \(pid)",
                    app.bundleIdentifier, iconCache[pid])
        }
        let rawName = ProcessSampler.name(of: pid) ?? "PID \(pid)"
        return (Self.friendlyDaemonNames[rawName] ?? rawName, nil, nil)
    }

    /// Noms lisibles pour les daemons système les plus courants.
    private static let friendlyDaemonNames: [String: String] = [
        "WindowServer": "显示 (WindowServer)",
        "kernel_task": "macOS 内核",
        "launchd": "launchd (系统)",
        "mds": "Spotlight (索引)",
        "mds_stores": "Spotlight (索引)",
        "mdworker_shared": "Spotlight (索引)",
        "corespotlightd": "Spotlight",
        "bird": "iCloud 云盘",
        "cloudd": "iCloud (同步)",
        "backupd": "Time Machine",
        "coreaudiod": "系统音频",
        "logd": "系统日志",
        "trustd": "安全 (trustd)",
        "mediaanalysisd": "媒体分析",
        "photoanalysisd": "照片 (分析)",
        "bluetoothd": "蓝牙",
        "airportd": "Wi-Fi",
    ]
}
