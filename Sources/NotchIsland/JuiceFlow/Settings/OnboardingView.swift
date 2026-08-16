import SwiftUI

/// 首次打开引导：三个核心功能介绍，以及精确模式入口。
struct OnboardingView: View {
    @Environment(ProcessService.self) private var processes
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.23, blue: 0.16),
                                              Color(red: 0.10, green: 0.72, blue: 0.42)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: 68, height: 68)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 6) {
                Text("欢迎使用 JuiceFlow")
                    .font(.title2.bold())
                Text("一眼看清是什么在消耗你的电池。")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                feature("gauge.with.needle", .green, "全部实时显示",
                        "剩余续航、充电器 → Mac → 电池的能量流向，以及耗电 App 排行榜。")
                feature("scope", .teal, "每个 App 的真实瓦数",
                        "精确模式使用 Apple 的 powermetrics，并换算成「每个 App 少续航多少分钟」。")
                feature("bell.badge", .indigo, "低调的后台守护",
                        "常驻菜单栏；用电池时若某 App 异常耗电，通知里可直接退出。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .unavailable = processes.powerMetrics.state {
                Button("开启精确模式…") {
                    Task { await processes.powerMetrics.installAuthorizationAndStart() }
                }
            }

            Button("开始使用") { done() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 470)
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
