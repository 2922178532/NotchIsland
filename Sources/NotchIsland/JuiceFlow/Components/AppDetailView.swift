import AppKit
import SwiftUI

/// 主界面右侧详情面板：选中 App 的实时功耗与续航代价。
struct AppDetailPanel: View {
    @Environment(BatteryService.self) private var battery
    @Environment(ProcessService.self) private var processes
    let app: AppPower?

    var body: some View {
        Group {
            if let app {
                detail(app)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("请选择一个应用程序")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func detail(_ app: AppPower) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                iconView(app)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.bundleID ?? "系统进程 · PID \(app.id)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(app.displayValue)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(app.displayColor)
                Text(processes.source == .precision ? "当前" : "影响分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Sparkline(values: app.history, color: app.displayColor)
                    .frame(height: 42)
                Text("最近 2 分钟")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            autonomyCost(app)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("CPU").foregroundStyle(.secondary)
                    Text(cpuText(app.cpuPercent))
                }
                if app.gpuPercent > 0.5 {
                    GridRow {
                        Text("GPU").foregroundStyle(.secondary)
                        Text(cpuText(app.gpuPercent))
                    }
                }
                GridRow {
                    Text("进程").foregroundStyle(.secondary)
                    Text("\(app.processCount)")
                }
            }
            .font(.caption)

            if !app.topChildren.isEmpty,
               app.topChildren.count > 1 || app.topChildren.first?.name != app.name {
                VStack(alignment: .leading, spacing: 5) {
                    Text("进程分布")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(app.topChildren, id: \.name) { child in
                        HStack {
                            Text(child.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 10)
                            Text(childMetricText(child.metric))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    if app.processCount > app.topChildren.count {
                        let others = app.processCount - app.topChildren.count
                        Text(others == 1 ? "另有 1 个进程" : "另有 \(others) 个进程")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if app.isRunaway || app.isBackgroundActive {
                VStack(alignment: .leading, spacing: 4) {
                    if app.isRunaway {
                        Label("功耗急剧上升", systemImage: "flame.fill")
                            .foregroundStyle(.red)
                    }
                    if app.isBackgroundActive {
                        Label("后台仍在耗电", systemImage: "moon.fill")
                            .foregroundStyle(.indigo)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 0)

            if let running = NSRunningApplication(processIdentifier: app.id),
               running.activationPolicy == .regular,
               running.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        running.terminate()
                    } label: {
                        Label("退出 App", systemImage: "xmark.circle")
                    }
                    Text("相当于 ⌘Q")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.default, value: app)
    }

    @ViewBuilder
    private func autonomyCost(_ app: AppPower) -> some View {
        let snap = battery.snapshot
        VStack(alignment: .leading, spacing: 4) {
            Text("续航代价")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let watts = app.sustainedWatts,
               let gain = battery.autonomyGainMinutes(freeingWatts: watts),
               let now = battery.estimatedAutonomyHours {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(TimeFormat.gain(gain))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.green)
                    Text("退出此 App 可多得")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("续航 \(TimeFormat.hours(now)) → \(TimeFormat.hours(now + gain / 60))"
                     + (snap.isExternalConnected ? " · 若当前用电池" : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if processes.source == .estimation {
                Text("开启精确模式后可显示「少续航多少分钟」。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("对续航影响可忽略。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.07))
        )
    }

    @ViewBuilder
    private func iconView(_ app: AppPower) -> some View {
        if let icon = app.icon {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            let glyph = DaemonGlyph.forApp(app)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(glyph.color.opacity(0.16))
                .overlay {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(glyph.color)
                }
        }
    }

    private func cpuText(_ percent: Double) -> String {
        percent >= 100
            ? String(format: "≈ %.1f 核", percent / 100)
            : String(format: "%.0f %% 单核", percent)
    }

    private func childMetricText(_ metric: Double) -> String {
        if processes.source == .precision {
            return metric < 1000
                ? String(format: "%.0f mW", metric)
                : String(format: "%.1f W", metric / 1000)
        }
        return String(format: "%.0f %% CPU", metric)
    }

}
