import SwiftUI

/// 岛的根视图。所有状态下都保持「顶部贴屏幕上沿、水平居中于刘海」，
/// 因此在尺寸变化时内容不会发生位移，看起来就像刘海本身在生长。
struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: ShelfStore
    @ObservedObject var menuBarMonitor: MenuBarItemMonitor
    @ObservedObject var preferences = Preferences.shared
    let power: PowerCenter
    let hoverPreview: ShelfHoverPreviewController
    var onTogglePin: () -> Void
    var onRequestCollapse: () -> Void
    var onOpenSettings: () -> Void
    var onActivateMenuBarItem: (MenuBarItem) -> Void
    var onRequestAccessibility: () -> Void
    var onOpenPowerDashboard: () -> Void

    /// 当前选中的分类筛选，nil 表示全部。
    @State private var filter: ShelfCategory?
    /// 刚存入新内容时为真，刘海下沿的提示条短暂变宽变亮。
    @State private var celebrating = false
    @State private var celebrateTask: Task<Void, Never>?
    /// 展开时顶栏里短暂替换「n 项 · 大小」的操作反馈文案。
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    /// 点了一次「清空」、正在等用户再点一次确认。
    @State private var confirmingClear = false
    @State private var confirmClearTask: Task<Void, Never>?
    /// 卡片列表当前加载到第几项。每次滚到末尾再加载一页，避免一次建出几百张卡片。
    @State private var loadedCount = Self.pageSize

    static let pageSize = 30

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
        // 隐藏了常驻提示的用户，存入成功时也短暂露一下，否则静默收存毫无反馈。
        model.mode == .collapsed && !store.isEmpty && (!preferences.hideIdleIndicator || celebrating)
    }

    private var islandSize: CGSize {
        guard showsCollapsedTongue else { return model.islandSize }
        return CGSize(width: 96, height: model.metrics.notchSize.height + 5)
    }

    /// 收起和悬停时保持纯黑，与物理刘海融为一体；展开和拖入提示换成液态玻璃。
    private var backgroundMaterial: IslandBackground.Material {
        switch model.mode {
        case .collapsed, .hovering: .black
        case .expanded: .glass
        case .dragPrompt: .tintedGlass
        }
    }

    private var shape: NotchShape {
        NotchShape(
            bottomCornerRadius: showsCollapsedTongue ? 9 : model.bottomCornerRadius,
            topCornerRadius: model.topCornerRadius
        )
    }

    var body: some View {
        island
            .background(alignment: .top) {
                // 提示色块比刘海窄，无刘海机型也保留完整的黑色岛顶。
                if model.mode == .dragPrompt {
                    NotchShape(bottomCornerRadius: 10, topCornerRadius: 0)
                        .fill(.black)
                        .frame(width: model.metrics.notchSize.width,
                               height: model.metrics.notchSize.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 岛的文字和图标都是按深色底设计的，玻璃也固定用深色外观，浅色壁纸上才看得清。
            .environment(\.colorScheme, .dark)
            .onChange(of: store.importSerial) { celebrateImport() }
            .onChange(of: model.mode) {
                // 每次重新展开都从第一页开始，也放弃没确认的清空。
                guard model.mode != .expanded else { return }
                loadedCount = Self.pageSize
                cancelClearConfirmation()
            }
            .onChange(of: store.messageSerial) { showToast(store.lastMessage) }
    }

    private func celebrateImport() {
        celebrateTask?.cancel()
        withAnimation(IslandStyle.reduceMotion ? .easeOut(duration: 0.15)
                      : .spring(response: 0.3, dampingFraction: 0.55)) {
            celebrating = true
        }
        celebrateTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { celebrating = false }
        }
    }

    private func showToast(_ text: String?) {
        guard let text, isExpanded else { return }
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { toastText = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toastText = nil }
        }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandBackground(
                shape: shape,
                size: islandSize,
                material: backgroundMaterial,
                headerHeight: model.metrics.notchSize.height
            )

            content
                .clipShape(shape)
        }
        .frame(width: islandSize.width, height: islandSize.height)
        .animation(IslandStyle.contentSpring, value: store.items.map(\.id))
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .collapsed, .hovering:
            compactIndicator
        case .dragPrompt:
            dragPrompt
        case .expanded:
            expandedContent
                // 进场由各区块的错开动画负责，这里只管退场时快速淡出。
                .transition(.asymmetric(insertion: .identity,
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
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
                        .fill(IslandStyle.brandGradient())
                        .frame(width: celebrating ? 70 : 46, height: 3)
                        .brightness(celebrating ? 0.25 : 0)
                        .shadow(color: IslandStyle.brandBlue.opacity(celebrating ? 0.9 : 0), radius: 4)
                        .padding(.bottom, 2)
                }
            }
        case .expanded, .dragPrompt:
            EmptyView()
        }
    }

    private var dragPrompt: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.metrics.notchSize.height)
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: !IslandStyle.reduceMotion)
                Text("拖到这里")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .glassLegible()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // 有液态玻璃时只叠一层淡淡的品牌渐变，让背后的桌面透出来。
                IslandStyle.brandGradient(startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(IslandStyle.supportsGlass ? 0.12 : 1)
            }
        }
        .accessibilityLabel("拖入文字、图片或文件，展开刘海岛")
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
                .contentTransition(.numericText())
                .animation(.snappy, value: power.wattsText)
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
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - 展开

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.metrics.notchSize.height)
                .staggeredAppear(0)
            if model.menuBarStripVisible && !model.isDropTargeted {
                VStack(spacing: 0) {
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
                .staggeredAppear(1)
            }
            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .staggeredAppear(2)
        }
    }

    /// 顶部一行必须避开中间的物理刘海，内容只能放在刘海左右两侧。
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandStyle.brandGradient(startPoint: .top, endPoint: .bottom))
                Text("刘海岛")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                if let toastText {
                    Label(toastText, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if !store.isEmpty {
                    Text("\(store.items.count) 项 · \(ByteCountFormatter.string(fromByteCount: store.totalSize, countStyle: .file))")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .transition(.opacity)
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
                    clearButton
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

    /// 清空按钮：开着二次确认时，第一次点击原地变成红色的「确认清空」，3 秒内再点才真正删除。
    @ViewBuilder
    private var clearButton: some View {
        if confirmingClear {
            Button {
                cancelClearConfirmation()
                withAnimation(IslandStyle.contentSpring) { store.removeAll() }
            } label: {
                Label("确认清空 \(store.items.count) 项", systemImage: "trash.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(IslandPressStyle())
            .help("再点一次删除全部暂存内容，3 秒后自动取消")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            IslandButton(systemName: "trash", help: "清空全部内容") {
                if preferences.confirmBeforeClear {
                    beginClearConfirmation()
                } else {
                    withAnimation(IslandStyle.contentSpring) { store.removeAll() }
                }
            }
            .transition(.opacity)
        }
    }

    private func beginClearConfirmation() {
        withAnimation(IslandStyle.contentSpring) { confirmingClear = true }
        confirmClearTask?.cancel()
        confirmClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(IslandStyle.contentSpring) { confirmingClear = false }
        }
    }

    private func cancelClearConfirmation() {
        confirmClearTask?.cancel()
        confirmClearTask = nil
        if confirmingClear {
            withAnimation(IslandStyle.contentSpring) { confirmingClear = false }
        }
    }

    @ViewBuilder
    private var panelBody: some View {
        Group {
            // 拖入展开时只创建轻量接收层，避免文件卡片与缩略图在首帧同时布局。
            if model.isDropTargeted {
                dropOverlay.transition(.opacity)
            } else if store.isEmpty, store.importingCount == 0 {
                emptyState
            } else {
                fileArea
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
        .glassLegible()
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
                // LazyHStack 只为滚到可见范围附近的卡片建视图、请求缩略图；
                // 再按页截断，滚到末尾时追加下一页。
                LazyHStack(spacing: 10) {
                    if store.importingCount > 0 {
                        importingCard
                    }
                    let items = filteredItems
                    ForEach(items.prefix(loadedCount)) { item in
                        ShelfItemView(item: item, store: store, hoverPreview: hoverPreview) {
                            model.beginDraggingOut()
                        }
                        .transition(cardTransition)
                    }
                    if items.count > loadedCount {
                        loadMoreCard(remaining: items.count - loadedCount)
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

    /// 列表末尾的「加载更多」占位：滚到这里自动加载下一页，也可以点击。
    private func loadMoreCard(remaining: Int) -> some View {
        Button {
            loadNextPage()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(IslandStyle.wellFill())
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.7))
                }
                .frame(width: 60, height: 60)
                Text("还有 \(remaining) 项")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .glassLegible()
                    .frame(width: 74)
            }
            .padding(.vertical, 4)
            .cardTile()
        }
        .buttonStyle(.plain)
        .onAppear { loadNextPage() }
    }

    private func loadNextPage() {
        loadedCount += Self.pageSize
    }

    /// 新卡片从左侧弹入，移除时缩小淡出。
    private var cardTransition: AnyTransition {
        guard !IslandStyle.reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.6).combined(with: .opacity).combined(with: .offset(x: -12)),
            removal: .scale(scale: 0.7).combined(with: .opacity)
        )
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
            withAnimation(IslandStyle.contentSpring) {
                filter = category
                loadedCount = Self.pageSize
            }
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
            .background {
                if isSelected {
                    Capsule().fill(IslandStyle.brandGradient().opacity(0.85))
                } else {
                    Capsule().fill(IslandStyle.chipFill())
                }
            }
        }
        .buttonStyle(IslandPressStyle())
    }

    private var importingCard: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(IslandStyle.wellFill())
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
        .cardTile()
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
            Capsule().fill(IslandStyle.chipFill())
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
                .fill(IslandStyle.brandGradient(startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.18))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    IslandStyle.brandGradient(startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .symbolEffect(.pulse, options: .repeating, isActive: !IslandStyle.reduceMotion)
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
                    .contentTransition(.numericText())
                    .animation(.snappy, value: power.wattsText)
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.8))
                    // 空间不足时 SwiftUI 会优先把文字压缩到零宽，必须固定尺寸。
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule().fill(IslandStyle.chipFill(hovering: isHovering))
            )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovering in
            withAnimation(IslandStyle.hoverFade) { isHovering = hovering }
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
                .foregroundStyle(isActive ? IslandStyle.brandBlue : .white.opacity(isHovering ? 1 : 0.7))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isActive
                                  ? IslandStyle.brandBlue.opacity(0.2)
                                  : IslandStyle.chipFill(hovering: isHovering))
                )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovering in
            withAnimation(IslandStyle.hoverFade) { isHovering = hovering }
        }
        .help(help)
    }
}

/// 岛的底板：纯黑或液态玻璃。两层同时存在、靠不透明度交叉过渡，
/// 所以从刘海展开成面板时，黑色会在弹簧动画里逐渐化成玻璃。
struct IslandBackground: View {
    enum Material: Equatable {
        case black
        case glass
        case tintedGlass
    }

    let shape: NotchShape
    let size: CGSize
    let material: Material
    /// 顶栏高度（等于菜单栏高度）。这一条压在菜单栏上方，背后的菜单栏图标会透出来，
    /// 和岛上的按钮叠在一起，所以只在这里加一道渐隐的暗色。
    var headerHeight: CGFloat = 0

    private var usesGlass: Bool {
        IslandStyle.supportsGlass && material != .black
    }

    var body: some View {
        ZStack(alignment: .top) {
            if IslandStyle.supportsGlass, #available(macOS 26.0, *) {
                glassLayer
                    .opacity(usesGlass ? 1 : 0)
            }
            shape
                .fill(Color.black)
                .opacity(usesGlass ? 0 : 1)
                .overlay {
                    shape.stroke(Color.white.opacity(material == .glass && !usesGlass ? 0.1 : 0), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(material == .black || usesGlass ? 0 : 0.5),
                radius: 18, y: 10)
    }

    /// 玻璃只在视图范围内渲染，所以把视图左右各加宽一个反向圆角，
    /// 再用「圆角画在内侧」的形状裁切，外形与黑色底板完全重合。
    @available(macOS 26.0, *)
    private var glassLayer: some View {
        let glassShape = NotchShape(
            bottomCornerRadius: shape.bottomCornerRadius,
            topCornerRadius: shape.topCornerRadius,
            earsInside: true
        )
        return Color.clear
            .frame(width: size.width + shape.topCornerRadius * 2, height: size.height)
            .glassEffect(glass, in: glassShape)
            .overlay(alignment: .top) {
                if material == .glass, headerHeight > 0 {
                    glassShape
                        .fill(LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.7), location: 0),
                                .init(color: .black.opacity(0.55), location: headerHeight / max(size.height, 1)),
                                .init(color: .black.opacity(0), location: (headerHeight + 18) / max(size.height, 1)),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .allowsHitTesting(false)
                }
            }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        switch material {
        case .tintedGlass:
            .clear.tint(IslandStyle.brandBlue.opacity(0.18))
        case .black, .glass:
            // 透明款，背后内容清楚可见、边缘有折射；顶栏的可读性靠上面的渐隐暗色保证。
            .clear
        }
    }
}
