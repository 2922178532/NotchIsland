import AppKit
import ApplicationServices
import ScreenCaptureKit

/// 一个被刘海挡住（或被系统挤出菜单栏）的状态栏图标。
struct MenuBarItem: Identifiable {
    let id: String
    let ownerPID: pid_t
    let ownerBundleID: String?
    let appName: String
    let tooltip: String
    /// 图标自带的状态文字（电量、温度、功耗等），直接显示在岛里。
    let statusText: String
    /// 对应的辅助功能元素，点击时对它执行 AXPress。
    let element: AXUIElement
    /// 仍保有菜单栏窗口时的窗口编号，用来截取真实图标。
    let windowID: CGWindowID?
    /// 显示用图像：默认是所属应用的图标，能截到真实图标时会被替换。
    var image: NSImage
}

/// 枚举所有应用的状态栏项，找出被刘海吞掉的那些。
///
/// 实测（macOS 26 刘海屏）被吞的状态栏项有两种形态：
/// 1. 坐标被系统丢到屏幕底部（y ≈ 屏幕高度），窗口被置零，常见于第三方应用；
/// 2. 坐标还留在菜单栏里但与刘海矩形相交，窗口仍在渲染（onScreen=false），
///    常见于控制中心的模块，这种可以用 ScreenCaptureKit 截到真实图标。
/// 无论哪种，对应的辅助功能元素都可以执行 AXPress 来打开它的菜单。
@MainActor
final class MenuBarItemMonitor: ObservableObject {
    @Published private(set) var hiddenItems: [MenuBarItem] = []
    @Published private(set) var isRefreshing = false

    /// 列表或图像有更新时通知外部（用来联动面板高度）。
    var onUpdate: (() -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAt = Date.distantPast

    /// 每个进程的辅助功能查询超时。无响应的进程直接跳过，避免整体卡住。
    private nonisolated static let perAppTimeout: Float = 0.25

    func refresh(metrics: NotchMetrics, force: Bool = false) {
        guard Preferences.shared.menuBarManagerEnabled, MenuBarPermissions.accessibilityGranted else {
            if !hiddenItems.isEmpty {
                hiddenItems = []
                onUpdate?()
            }
            return
        }
        guard refreshTask == nil else { return }
        guard force || Date().timeIntervalSince(lastRefreshAt) > 2 else { return }
        lastRefreshAt = Date()
        isRefreshing = true

        let apps = Self.candidateApps()
        let geometry = Self.geometry(from: metrics)

        refreshTask = Task { [weak self] in
            let started = Date()
            let items = await Task.detached(priority: .userInitiated) {
                Self.collectHiddenItems(apps: apps, geometry: geometry)
            }.value

            if ProcessInfo.processInfo.environment["NOTCHISLAND_DEBUG"] == "1" {
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                FileHandle.standardError.write(Data("状态栏扫描：\(items.count) 个被挡住，耗时 \(elapsed)ms\n".utf8))
            }

            guard let self else { return }
            self.hiddenItems = items
            self.isRefreshing = false
            self.refreshTask = nil
            self.onUpdate?()
            await self.captureRealIcons()
        }
    }

    /// 模拟点击一个状态栏项。放到后台线程执行，目标应用无响应时不会卡住界面。
    nonisolated static func press(_ item: MenuBarItem) {
        DispatchQueue.global(qos: .userInteractive).async {
            AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        }
    }

    // MARK: - 几何

    private struct Geometry {
        /// 刘海矩形，CG 坐标（主屏左上角为原点，y 向下）。
        let notch: CGRect
        let menuBarHeight: CGFloat
    }

    private static func geometry(from metrics: NotchMetrics) -> Geometry {
        // AppKit 全局坐标（y 向上）转 CG 坐标（y 向下）。
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? metrics.screenFrame.maxY
        let notch = CGRect(
            x: metrics.notchRect.minX,
            y: primaryHeight - metrics.notchRect.maxY,
            width: metrics.notchRect.width,
            height: metrics.notchRect.height
        )
        return Geometry(notch: notch, menuBarHeight: max(metrics.notchRect.height, 24))
    }

    // MARK: - 枚举

    private struct AppInfo {
        let pid: pid_t
        let bundleID: String?
        let name: String
        let icon: NSImage
        let isSelf: Bool
    }

    private static func candidateApps() -> [AppInfo] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let excluded = Set(Preferences.shared.hiddenMenuBarApps)
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .filter { app in
                guard let bundleID = app.bundleIdentifier else { return true }
                return !excluded.contains(bundleID)
            }
            .map {
                AppInfo(
                    pid: $0.processIdentifier,
                    bundleID: $0.bundleIdentifier,
                    name: $0.localizedName ?? "未知应用",
                    icon: $0.icon ?? NSWorkspace.shared.icon(for: .application),
                    isSelf: $0.processIdentifier == selfPID
                )
            }
    }

    /// 用户点了「不再显示」：加入排除名单并立即从列表移除。
    func exclude(_ item: MenuBarItem) {
        guard let bundleID = item.ownerBundleID else { return }
        if !Preferences.shared.hiddenMenuBarApps.contains(bundleID) {
            Preferences.shared.hiddenMenuBarApps.append(bundleID)
        }
        hiddenItems.removeAll { $0.ownerBundleID == bundleID }
        onUpdate?()
    }

    private nonisolated static func collectHiddenItems(apps: [AppInfo], geometry: Geometry) -> [MenuBarItem] {
        let hiddenWindows = hiddenStatusWindows(menuBarHeight: geometry.menuBarHeight)

        // 每个进程一次同步 IPC，串行扫完几十个应用要将近 10 秒，必须并发。
        var scanned = [[(x: CGFloat?, item: MenuBarItem)]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let found = hiddenItems(in: apps[index], geometry: geometry, hiddenWindows: hiddenWindows)
            guard !found.isEmpty else { return }
            lock.lock()
            scanned[index] = found
            lock.unlock()
        }

        let all = scanned.flatMap { $0 }
        // 仍留在菜单栏里的按原有顺序排，被丢出去的按应用名排在后面。
        let inBand = all
            .compactMap { entry -> (CGFloat, MenuBarItem)? in
                entry.x.map { ($0, entry.item) }
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        let offloaded = all
            .filter { $0.x == nil }
            .map(\.item)
            .sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
        return inBand + offloaded
    }

    /// 扫描单个应用，返回它被挡住的状态栏项；`x` 为 nil 表示已被系统丢出菜单栏。
    private nonisolated static func hiddenItems(
        in app: AppInfo,
        geometry: Geometry,
        hiddenWindows: [(id: CGWindowID, bounds: CGRect)]
    ) -> [(x: CGFloat?, item: MenuBarItem)] {
        // 自己的设置入口已经放在岛面板上，不用再列出来。
        if app.isSelf { return [] }

        let axApp = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(axApp, perAppTimeout)

        guard let extras = copyElement(axApp, "AXExtrasMenuBar"),
              let children = copyValue(extras, kAXChildrenAttribute as String) as? [AXUIElement],
              !children.isEmpty
        else { return [] }

        var results: [(x: CGFloat?, item: MenuBarItem)] = []
        for (index, child) in children.enumerated() {
            guard let position = pointValue(child, kAXPositionAttribute as String) else { continue }
            let size = sizeValue(child, kAXSizeAttribute as String) ?? .zero
            guard isHidden(position: position, size: size, geometry: geometry) else { continue }

            let title = ((copyValue(child, kAXTitleAttribute as String) as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            let description = ((copyValue(child, kAXDescriptionAttribute as String) as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            let detail = [title, description].filter { !$0.isEmpty }.joined(separator: " ")

            let inMenuBarBand = position.y > -1 && position.y < geometry.menuBarHeight
            let windowID = inMenuBarBand
                ? hiddenWindows.first(where: { abs($0.bounds.minX - position.x) <= 4 })?.id
                : nil

            let item = MenuBarItem(
                id: "\(app.pid)-\(index)",
                ownerPID: app.pid,
                ownerBundleID: app.bundleID,
                appName: app.name,
                tooltip: detail.isEmpty ? app.name : "\(app.name) · \(detail)",
                statusText: meaningfulStatus(title.isEmpty ? description : title),
                element: child,
                windowID: windowID,
                image: app.icon
            )
            results.append((inMenuBarBand ? position.x : nil, item))
        }
        return results
    }

    /// 从状态栏项的标题里筛出值得直接展示的动态状态。
    ///
    /// 标题内容质量参差：有的是「12.3 W」「85%」这类度量值（有用），
    /// 有的是图标资源名或应用名（噪音）。只保留数字开头的短文本，其余进悬停提示。
    private nonisolated static func meaningfulStatus(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // 至少 3 个字符（如「85%」「9 W」），过滤掉「1」这类没有单位的裸数字。
        guard (3...12).contains(trimmed.count), trimmed.first?.isNumber == true else { return "" }
        return trimmed
    }

    /// 一个状态栏项是否「本应显示却被刘海遮挡/挤出」。
    ///
    /// 屏幕外的项有两种来源，必须区分：
    /// - 被系统因空间不足挤出的：保留着有效的排布坐标（x 为小正数），要显示；
    /// - 应用自己隐藏的（isVisible=false 或用户在应用设置里关了菜单栏图标）：
    ///   坐标是无效标记（第三方为 -1，控制中心关闭的模块为 0 且零尺寸），
    ///   它们本来就不该出现在菜单栏上，不显示。
    private nonisolated static func isHidden(position: CGPoint, size: CGSize, geometry: Geometry) -> Bool {
        guard size.width > 1 else { return false }

        let inMenuBarBand = position.y > -1 && position.y < geometry.menuBarHeight
        if !inMenuBarBand {
            // 屏幕外：只有保留了有效排布坐标的才是被挤出的。
            return position.x > 0
        }
        // 留在菜单栏里但和刘海重叠。
        let maxX = position.x + size.width
        return position.x < geometry.notch.maxX && maxX > geometry.notch.minX
    }

    /// 菜单栏那一条里不再渲染到屏幕上的状态项窗口（用于对照截图）。
    private nonisolated static func hiddenStatusWindows(menuBarHeight: CGFloat) -> [(id: CGWindowID, bounds: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [(CGWindowID, CGRect)] = []
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 25,
                  let windowID = window[kCGWindowNumber as String] as? Int,
                  (window[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict)
            else { continue }
            guard bounds.minY > -1, bounds.minY < 5, bounds.height <= menuBarHeight + 2, bounds.width > 1 else { continue }
            result.append((CGWindowID(windowID), bounds))
        }
        return result
    }

    // MARK: - 截取真实图标

    /// 对仍保有窗口的项（主要是控制中心模块）截取真实图标替换应用图标。
    private func captureRealIcons() async {
        guard MenuBarPermissions.screenCaptureGranted,
              hiddenItems.contains(where: { $0.windowID != nil })
        else { return }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return
        }

        var updated = false
        for index in hiddenItems.indices {
            guard let windowID = hiddenItems[index].windowID,
                  let window = content.windows.first(where: { $0.windowID == windowID })
            else { continue }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(window.frame.width) * 2, 2)
            configuration.height = max(Int(window.frame.height) * 2, 2)
            configuration.showsCursor = false

            guard let cgImage = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) else { continue }

            // 被吞的窗口有时已停止渲染，截出来是全透明——那就保留应用图标。
            guard !Self.isMostlyTransparent(cgImage) else { continue }

            hiddenItems[index].image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: window.frame.width, height: window.frame.height)
            )
            updated = true
        }
        if updated { onUpdate?() }
    }

    /// 抽样判断图像是否基本透明（16 个采样点的透明度都接近 0）。
    private nonisolated static func isMostlyTransparent(_ image: CGImage) -> Bool {
        let width = 4, height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 8 {
            return false
        }
        return true
    }

    // MARK: - AX 工具

    private nonisolated static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private nonisolated static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyValue(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private nonisolated static func pointValue(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = copyValue(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private nonisolated static func sizeValue(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = copyValue(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
