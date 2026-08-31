import SwiftUI

/// 展开面板里的一行：被刘海挡住的状态栏图标，点一下等于点了菜单栏上的原图标。
struct MenuBarStripView: View {
    @ObservedObject var monitor: MenuBarItemMonitor
    var onActivate: (MenuBarItem) -> Void
    var onRequestAccessibility: () -> Void

    private var accessibilityGranted: Bool { MenuBarPermissions.accessibilityGranted }

    var body: some View {
        HStack(spacing: 10) {
            if accessibilityGranted {
                grantedContent
            } else {
                permissionPrompt
            }
        }
        .padding(.horizontal, 16)
        .frame(height: NotchLayout.menuBarStripHeight)
    }

    @ViewBuilder
    private var grantedContent: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye.slash")
                .font(.system(size: 9))
            Text("刘海下")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.42))
        .fixedSize()

        if monitor.hiddenItems.isEmpty {
            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white.opacity(0.6))
                Text("正在扫描菜单栏…")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                Text("没有被挡住的图标")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(monitor.hiddenItems) { item in
                        MenuBarItemButton(
                            item: item,
                            action: { onActivate(item) },
                            onExclude: { monitor.exclude(item) }
                        )
                    }
                }
            }
        }
    }

    private var permissionPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text("授权「辅助功能」后，被刘海挡住的菜单栏图标会显示在这里")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                Text("若设置里已开启仍提示授权，请先关闭再重新打开「刘海岛」，然后重启应用（更新后签名会变）")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(3)
            }
            Spacer(minLength: 4)
            Button(action: onRequestAccessibility) {
                Text("去授权")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
    }
}

/// 单个被挡住的图标：应用图标或截到的真实菜单栏图标，旁边带实时状态文字。
private struct MenuBarItemButton: View {
    let item: MenuBarItem
    let action: () -> Void
    var onExclude: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 56)
                    .frame(height: 20)

                if !item.statusText.isEmpty {
                    Text(item.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 72)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.18 : 0.07))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(item.tooltip)
        .contextMenu {
            Button("打开菜单") { action() }
            Button("激活「\(item.appName)」") {
                NSRunningApplication(processIdentifier: item.ownerPID)?
                    .activate(options: [.activateAllWindows])
            }
            Divider()
            Button("不再显示此图标") { onExclude() }
            Button("退出「\(item.appName)」", role: .destructive) {
                NSRunningApplication(processIdentifier: item.ownerPID)?.terminate()
            }
        }
    }
}
