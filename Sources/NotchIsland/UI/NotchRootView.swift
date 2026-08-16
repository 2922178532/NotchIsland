import SwiftUI

/// 岛的根视图。所有状态下都保持「顶部贴屏幕上沿、水平居中于刘海」，
/// 因此在尺寸变化时内容不会发生位移，看起来就像刘海本身在生长。
struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: ShelfStore
    @ObservedObject var menuBarMonitor: MenuBarItemMonitor
    @ObservedObject var preferences = Preferences.shared
    let power: PowerCenter
    var onTogglePin: () -> Void
    var onRequestCollapse: () -> Void
    var onOpenSettings: () -> Void
    var onActivateMenuBarItem: (MenuBarItem) -> Void
    var onRequestAccessibility: () -> Void
    var onOpenPowerDashboard: () -> Void

    /// 当前选中的分类筛选，nil 表示全部。
    @State private var filter: ShelfCategory?

    private var isExpanded: Bool { model.mode == .expanded }

    /// 有内容的分类（用于决定是否显示筛选行）。
    private var categoriesWithItems: [ShelfCategory] {
        ShelfCategory.allCases.filter { category in
            store.items.contains { $0.category == category }
        }
    }

    /// 选中的分类若已没有内容，自动回落到「全部」。
    private var activeFilter: ShelfCategory? {
        guard let filter, store.items.contains(where: { $0.category == filter }) else { return nil }
        return filter
    }

    private var filteredItems: [ShelfItem] {
        guard let activeFilter else { return store.items }
        return store.items.filter { $0.category == activeFilter }
    }

    /// 收起且刘海岛非空时，从刘海下沿探出一小截提示。
    /// 宽度要小于刘海，这样探出的部分是一个独立的小圆角块，也不会遮住菜单栏。
    /// 用户可以在菜单里选择隐藏它，让刘海保持原生外观（交互不受影响）。
    private var showsCollapsedTongue: Bool {
        model.mode == .collapsed && !store.isEmpty && !preferences.hideIdleIndicator
    }

    private var islandSize: CGSize {
        guard showsCollapsedTongue else { return model.islandSize }
        return CGSize(width: 96, height: model.metrics.notchSize.height + 5)
    }

    private var shape: NotchShape {
        NotchShape(
            bottomCornerRadius: showsCollapsedTongue ? 9 : model.bottomCornerRadius,
            topCornerRadius: model.topCornerRadius
        )
    }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(isExpanded ? 0.1 : 0), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(isExpanded ? 0.5 : 0), radius: 18, y: 10)

            content
                .clipShape(shape)
        }
        .frame(width: islandSize.width, height: islandSize.height)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: store.items.count)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .collapsed, .hovering:
            compactIndicator
        case .expanded:
            expandedContent
                .transition(.opacity)
        }
    }

    // MARK: - 收起 / 悬停

    /// 刘海区域没有物理像素，所以内容只画在岛底部多出来的部分上。
    @ViewBuilder
    private var compactIndicator: some View {
        switch model.mode {
        case .hovering:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                hoverStatusLine
                    .padding(.bottom, 5)
            }
        case .collapsed:
            if showsCollapsedTongue {
                VStack {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.6, blue: 1.0), Color(red: 0.68, green: 0.45, blue: 1.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 46, height: 3)
                        .padding(.bottom, 2)
                }
            }
        case .expanded:
            EmptyView()
        }
    }

    /// 悬停时露出的一行：实时功耗 + 刘海岛文件数。
    private var hoverStatusLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
                .foregroundStyle(.yellow.opacity(0.9))
            Text(power.wattsText ?? "…")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
            if !store.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.35))
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(store.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - 展开

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.metrics.notchSize.height)
            if model.menuBarStripVisible {
                MenuBarStripView(
                    monitor: menuBarMonitor,
                    onActivate: onActivateMenuBarItem,
                    onRequestAccessibility: onRequestAccessibility
                )
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
            }
            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 顶部一行必须避开中间的物理刘海，内容只能放在刘海左右两侧。
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.4, green: 0.65, blue: 1.0), Color(red: 0.7, green: 0.45, blue: 1.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("刘海岛")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                if !store.isEmpty {
                    Text("\(store.items.count) 项 · \(ByteCountFormatter.string(fromByteCount: store.totalSize, countStyle: .file))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)

            Spacer(minLength: 0)
                .frame(width: model.metrics.notchSize.width)

            HStack(spacing: 8) {
                powerChip
                if !store.isEmpty {
                    IslandButton(systemName: "doc.on.doc", help: "复制全部到剪贴板") {
                        store.copyAllToPasteboard()
                    }
                    IslandButton(systemName: "trash", help: "清空全部内容") {
                        store.removeAll()
                    }
                }
                IslandButton(
                    systemName: model.isPinned ? "pin.fill" : "pin",
                    help: model.isPinned ? "取消固定" : "固定展开",
                    isActive: model.isPinned
                ) {
                    onTogglePin()
                }
                IslandButton(systemName: "gearshape", help: "设置") {
                    onOpenSettings()
                }
                IslandButton(systemName: "chevron.up", help: "收起") {
                    onRequestCollapse()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 18)
        }
    }

    @ViewBuilder
    private var panelBody: some View {
        ZStack {
            if store.isEmpty, store.importingCount == 0 {
                emptyState
            } else {
                fileArea
            }

            if model.isDropTargeted {
                dropOverlay
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("把文件拖到刘海这里暂存")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Text("需要时再从这里拖进任意应用")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.white.opacity(0.14))
        }
    }

    private var fileArea: some View {
        VStack(spacing: 6) {
            if categoriesWithItems.count >= 2 {
                categoryFilterRow
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if store.importingCount > 0 {
                        importingCard
                    }
                    ForEach(filteredItems) { item in
                        ShelfItemView(item: item, store: store) {
                            model.beginDraggingOut()
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)

            if !filteredItems.isEmpty {
                dragAllHandle
            }
        }
    }

    /// 分类筛选行：全部 / 文件 / 图片 / 文本，只列出有内容的分类。
    private var categoryFilterRow: some View {
        HStack(spacing: 6) {
            filterChip(for: nil, label: "全部", count: store.items.count)
            ForEach(categoriesWithItems) { category in
                filterChip(
                    for: category,
                    label: category.rawValue,
                    count: store.items.filter { $0.category == category }.count
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func filterChip(for category: ShelfCategory?, label: String, count: Int) -> some View {
        let isSelected = activeFilter == category
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = category }
        } label: {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 8))
                }
                Text("\(label) \(count)")
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : .white.opacity(0.6))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? Color.accentColor.opacity(0.75) : .white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private var importingCard: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.7))
            }
            .frame(width: 60, height: 60)

            Text("存入中")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 74)
        }
        .padding(.vertical, 4)
    }

    /// 一次拖走当前列表全部内容的把手，跟随分类筛选。
    private var dragAllHandle: some View {
        let items = filteredItems
        let label = activeFilter.map { "\($0.rawValue)" } ?? ""
        return HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 10))
            Text("拖住这里可一次取走全部 \(items.count) 项\(label)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.white.opacity(0.08))
        )
        .overlay {
            MultiFileDragView(
                urls: { items.map { store.fileURL(for: $0) } },
                onDragStart: { model.beginDraggingOut() },
                onDragEnd: { model.endDraggingOut() }
            )
        }
    }

    /// 实时功耗徽章，点击打开完整的功耗监测面板。
    private var powerChip: some View {
        PowerChipButton(power: power, action: onOpenPowerDashboard)
    }

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                Text("松开即可存入")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

/// 显示实时功耗的胶囊按钮。
private struct PowerChipButton: View {
    let power: PowerCenter
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow.opacity(0.9))
                Text(power.wattsText ?? "功耗")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.8))
                    // 空间不足时 SwiftUI 会优先把文字压缩到零宽，必须固定尺寸。
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule().fill(.white.opacity(isHovering ? 0.18 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("打开功耗监测面板")
    }
}

/// 岛上使用的小圆形按钮。
private struct IslandButton: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .white.opacity(isHovering ? 1 : 0.7))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(.white.opacity(isHovering ? 0.18 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
    }
}
