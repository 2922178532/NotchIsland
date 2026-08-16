import SwiftUI

/// Dashboard principal.
/// Bandeau héros : jauge (autonomie au centre), flux d'énergie, stats.
/// Dessous : classement des apps + panneau détail permanent (master-detail).
struct ContentView: View {
    enum Tab { case live, history }

    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes
    @State private var showPrecisionSetup = false
    @State private var selectedAppID: pid_t?
    @State private var tab: Tab = .live
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if battery.hasBattery {
                dashboard(battery.snapshot)
            } else {
                ContentUnavailableView(
                    "未检测到电池",
                    systemImage: "battery.slash",
                    description: Text("JuiceFlow 需要 Mac 笔记本电脑。")
                )
                .padding(40)
            }
        }
        // Pilote la cadence de mesure et la présence dans le Dock :
        // fenêtre fermée → mode économie + app « accessoire » (barre des
        // menus uniquement, plus d'icône Dock ni de point blanc).
        //
        // La logique vit dans `syncViewers` (constat de visibilité réelle,
        // idempotent) : onAppear/onDisappear et les notifications NSWindow
        // ne sont que des accélérateurs — selon la version de macOS,
        // certains ne tirent jamais (SwiftUI garde la vue vivante après
        // fermeture). Le tick de sondage rattrape toujours.
        .onAppear {
            processes.syncViewers()
            if !hasOnboarded { showOnboarding = true }
        }
        .onDisappear { processes.syncViewers() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            processes.syncViewers()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            processes.syncViewers()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasOnboarded = true
                showOnboarding = false
            }
        }
    }

    /// L'app affichée dans le panneau : la sélection, sinon la plus gourmande.
    private var selectedApp: AppPower? {
        processes.apps.first { $0.id == selectedAppID } ?? processes.apps.first
    }

    private func dashboard(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("实时").tag(Tab.live)
                Text("历史").tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            headerRow(snap)

            Group {
                if tab == .live {
                    HStack(alignment: .top, spacing: 14) {
                        appsSection
                            .frame(maxWidth: .infinity)
                        AppDetailPanel(app: selectedApp)
                            .frame(width: 320)
                    }
                } else {
                    HistoryView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 880, height: 660, alignment: .top)
        .padding(20)
        // Pas d'animation d'arbre global : le snapshot change toutes les 3 s
        // (au centième de volt près) et forcerait tout le dashboard — halo,
        // ombres — à re-rendre 60 fps pendant 0,5 s. Chaque composant anime
        // localement ce qui le concerne.
    }

    // MARK: - Bandeau héros

    /// Une seule carte unifiée : jauge (niveau), titre temporel (la réponse
    /// à « combien de temps ? »), flux d'énergie, stats derrière un filet.
    private func headerRow(_ snap: BatterySnapshot) -> some View {
        HStack(spacing: 18) {
            BatteryGauge(snapshot: snap, size: 140)
                .animation(.spring(duration: 0.8), value: snap.percentage)

            VStack(alignment: .leading, spacing: 12) {
                headline(snap)
                    .animation(.default, value: snap)
                PowerFlowCard(snapshot: snap)
                    .animation(.default, value: snap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 6)

            statsColumn(snap)
                .animation(.default, value: snap)
                .frame(width: 165)
        }
        .padding(18)
        .card()
        .frame(height: 196)
    }

    private func statsColumn(_ snap: BatterySnapshot) -> some View {
        let score = SessionScore.compute(battery: battery, processes: processes)
        return VStack(alignment: .leading, spacing: 10) {
            StatChip(icon: "speedometer", color: score.color,
                     value: "\(score.value)",
                     label: "本次评分",
                     showsBackground: false)
                .help(score.factors.isEmpty
                      ? "本次使用状态良好，暂无异常。"
                      : score.factors.joined(separator: "\n"))
            StatChip(icon: "heart.fill", color: .pink,
                     value: String(format: "%.0f %%", snap.healthPercent),
                     label: "健康度 · \(snap.nominalCapacity) mAh",
                     showsBackground: false)
            StatChip(icon: "thermometer.medium", color: .orange,
                     value: String(format: "%.1f °C", snap.temperature),
                     label: snap.temperature < 40 ? "温度正常" : "温度偏高",
                     showsBackground: false)
            StatChip(icon: "arrow.triangle.2.circlepath", color: .blue,
                     value: "\(snap.cycleCount)",
                     label: "循环次数 · 约 1000 次",
                     showsBackground: false)
        }
    }

    /// Le gros titre contextuel du bandeau : toujours une réponse en temps.
    private func headline(_ snap: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(headlineValue(snap))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(headlineLabel(snap))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(headlineSubtitle(snap))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }

    private func headlineValue(_ snap: BatterySnapshot) -> String {
        switch snap.state {
        case .discharging:
            return battery.estimatedAutonomyHours.map { TimeFormat.hours($0) } ?? "…"
        case .charging:
            return snap.timeRemainingMinutes.map { TimeFormat.hours(Double($0) / 60) } ?? "充电中"
        case .full, .pluggedNotCharging:
            return battery.estimatedAutonomyHours.map { "≈ \(TimeFormat.hours($0))" } ?? "已接通电源"
        }
    }

    private func headlineLabel(_ snap: BatterySnapshot) -> String {
        switch snap.state {
        case .discharging: "剩余续航"
        case .charging: snap.timeRemainingMinutes != nil ? "后充满" : ""
        case .full, .pluggedNotCharging:
            battery.estimatedAutonomyHours != nil ? "拔掉电源后可用" : ""
        }
    }

    private func headlineSubtitle(_ snap: BatterySnapshot) -> String {
        let drain = battery.smoothedDrainWatts.map { String(format: "%.1f W", $0) } ?? "…"
        switch snap.state {
        case .discharging:
            return "按最近 2 分钟平均速率 · \(drain)"
        case .charging:
            let autonomy = battery.estimatedAutonomyHours
                .map { "拔掉电源后约 \(TimeFormat.hours($0))" } ?? "正在计算"
            return "\(autonomy) · 平均功耗 \(drain)"
        case .full:
            return "电池已充满 · 平均功耗 \(drain)"
        case .pluggedNotCharging:
            return "充电已暂停 · 平均功耗 \(drain)"
        }
    }

    // MARK: - Classement

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("能耗影响")
                    .font(.headline)
                sourceBadge
                Spacer()
                Text("\(processes.trackedProcessCount) 个进程")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .help(processes.source == .precision
                ? "Apple 官方 powermetrics 真实瓦数：含 CPU（P/E 核）、GPU、唤醒次数及系统进程。"
                : "根据 CPU 估算的分数（与活动监视器类似：约 100 ≈ 单核满载）。开启精确模式可显示真实瓦数、GPU 及系统进程。")
            .alert("开启精确模式", isPresented: $showPrecisionSetup) {
                Button("开启") {
                    Task { await processes.powerMetrics.installAuthorizationAndStart() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("""
                JuiceFlow 将使用 Apple 的 powermetrics 测量工具，\
                精确显示各 App 能耗：含 P/E 核、GPU 及系统进程（如 WindowServer）。

                将为你的用户创建一条仅限 powermetrics 的 sudo 规则，\
                只需输入一次管理员密码。
                """)
            }

            if processes.apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在进行首次测量…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                let top = Array(processes.apps.prefix(8))
                let maxImpact = top.first?.energyImpact ?? 1
                VStack(spacing: 8) {
                    ForEach(top) { app in
                        AppEnergyRow(app: app, maxImpact: maxImpact,
                                     isSelected: app.id == selectedApp?.id)
                            .onTapGesture { selectedAppID = app.id }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
        .animation(.spring(duration: 0.5), value: processes.apps)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if processes.source == .precision {
            badgeLabel("精确", color: .teal)
        } else {
            badgeLabel("估算", color: .orange)
            if case .unavailable = processes.powerMetrics.state {
                Button("开启精确模式") { showPrecisionSetup = true }
                    .buttonStyle(.link)
                    .font(.caption2)
            } else if case .failed = processes.powerMetrics.state {
                badgeLabel("powermetrics 错误", color: .red)
                    .help("powermetrics 数据流中断 — 已自动回退到估算模式。")
            }
        }
    }

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
