#!/usr/bin/env swift
// 枚举状态栏图标窗口，观察被刘海遮挡的图标在窗口层面的真实状态，
// 并验证 ScreenCaptureKit 能否截到不在屏幕上的窗口。
// 用法：swift scripts/menubar-diagnose.swift

import AppKit
import CoreGraphics
import ScreenCaptureKit

for screen in NSScreen.screens {
    let inset = screen.safeAreaInsets
    print("屏幕 \(screen.localizedName): frame=\(screen.frame) safeTop=\(inset.top)")
    if inset.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
        let notchWidth = screen.frame.width - left.width - right.width
        print("  刘海(CG坐标): x=\(left.width) 宽=\(notchWidth) 高=\(inset.top)")
    }
}
print("屏幕录制权限: \(CGPreflightScreenCaptureAccess())  辅助功能权限: \(AXIsProcessTrusted())")
print("")

guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    print("无法获取窗口列表")
    exit(1)
}

var hiddenIDs: [CGWindowID] = []
print("layer 20~30 的窗口（按 layer, x 排序）：")
var rows: [(layer: Int, x: CGFloat, line: String)] = []
for window in list {
    guard let layer = window[kCGWindowLayer as String] as? Int, (20...30).contains(layer) else { continue }
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    let pid = window[kCGWindowOwnerPID as String] as? Int ?? 0
    let name = window[kCGWindowName as String] as? String ?? ""
    let windowID = window[kCGWindowNumber as String] as? Int ?? 0
    let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
    var bounds = CGRect.zero
    if let dict = window[kCGWindowBounds as String] as? NSDictionary,
       let rect = CGRect(dictionaryRepresentation: dict) {
        bounds = rect
    }
    rows.append((
        layer, bounds.minX,
        String(
            format: "L%d | x=%6.0f y=%4.0f 宽=%4.0f 高=%3.0f | onScreen=%@ | id=%d pid=%d | %@ %@",
            layer, bounds.minX, bounds.minY, bounds.width, bounds.height,
            onScreen ? "是" : "否", windowID, pid, owner, name.isEmpty ? "" : "(\(name))"
        )
    ))
    if layer == 25, !onScreen, bounds.minY < 5 {
        hiddenIDs.append(CGWindowID(windowID))
    }
}
for row in rows.sorted(by: { ($0.layer, $0.x) < ($1.layer, $1.x) }) {
    print("  " + row.line)
}

// 验证 SCK 对隐藏窗口的截图能力
guard let firstHidden = hiddenIDs.first else {
    print("\n当前没有被吞的状态栏图标，跳过截图验证")
    exit(0)
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    defer { semaphore.signal() }
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let statusWindows = content.windows.filter { $0.windowLayer == 25 }
        print("\nSCK 看到的状态栏层窗口: \(statusWindows.count) 个")
        guard let target = statusWindows.first(where: { $0.windowID == firstHidden }) else {
            print("SCK 找不到被吞的窗口 id=\(firstHidden)")
            return
        }
        print("目标窗口: \(target.owningApplication?.applicationName ?? "?") \(target.title ?? "") frame=\(target.frame) isOnScreen=\(target.isOnScreen)")
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        config.width = Int(target.frame.width) * 2
        config.height = Int(target.frame.height) * 2
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: "/tmp/notchisland-test/hidden-item.png")
            try data.write(to: url)
            print("已截到被吞窗口的图像 \(image.width)x\(image.height) -> \(url.path)")
        }
    } catch {
        print("SCK 失败: \(error)")
    }
}
semaphore.wait()
