import SwiftUI

/// 功耗监测设置：告警与精确模式。
/// 登录启动、更新等应用级设置由 NotchIsland 的菜单统一负责。
struct SettingsView: View {
    @Environment(ProcessService.self) private var processes

    @AppStorage("alertsEnabled") private var alertsEnabled = true
    @AppStorage("alertSensitivity") private var sensitivityRaw = AlertSensitivity.normal.rawValue

    var body: some View {
        Form {
            Section {
                Toggle("用电池时 App 异常耗电则提醒", isOn: $alertsEnabled)
                Picker("灵敏度", selection: $sensitivityRaw) {
                    ForEach(AlertSensitivity.allCases) { sensitivity in
                        Text(sensitivity.label).tag(sensitivity.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!alertsEnabled)
            } header: {
                Text("告警")
            } footer: {
                Text("仅在用电池且持续高功耗时触发告警。同一 App 触发后 30 分钟内不再提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("测量") {
                LabeledContent("能耗影响") {
                    measureStatus
                }
                if processes.powerMetrics.state == .running {
                    Button("移除 powermetrics 授权…", role: .destructive) {
                        Task { await processes.powerMetrics.removeAuthorization() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    @ViewBuilder
    private var measureStatus: some View {
        switch processes.powerMetrics.state {
        case .running:
            Label("精确模式已开启（powermetrics）", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.teal)
        case .unavailable:
            Button("开启精确模式…") {
                Task { await processes.powerMetrics.installAuthorizationAndStart() }
            }
        case .probing:
            Label("正在验证…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .failed:
            Label("错误 — 已回退到估算模式", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
