#!/usr/bin/env swift
// 验证：通过辅助功能 API 能否枚举各应用的状态栏附加项（含被刘海吞掉的）。
// 用法：swift scripts/ax-diagnose.swift

import AppKit
import ApplicationServices

guard AXIsProcessTrusted() else {
    print("当前进程没有辅助功能权限")
    exit(1)
}

func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func stringValue(_ element: AXUIElement, _ name: String) -> String? {
    copyAttribute(element, name) as? String
}

func pointValue(_ element: AXUIElement, _ name: String) -> CGPoint? {
    guard let raw = copyAttribute(element, name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func sizeValue(_ element: AXUIElement, _ name: String) -> CGSize? {
    guard let raw = copyAttribute(element, name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
    return size
}

for app in NSWorkspace.shared.runningApplications {
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    guard let extrasRaw = copyAttribute(ax, "AXExtrasMenuBar") else { continue }
    let extras = extrasRaw as! AXUIElement
    guard let children = copyAttribute(extras, kAXChildrenAttribute as String) as? [AXUIElement],
          !children.isEmpty else { continue }

    print("\(app.localizedName ?? "?") (pid \(app.processIdentifier)) 有 \(children.count) 个状态栏项:")
    for child in children {
        let position = pointValue(child, kAXPositionAttribute as String)
        let size = sizeValue(child, kAXSizeAttribute as String)
        let title = stringValue(child, kAXTitleAttribute as String) ?? ""
        let description = stringValue(child, kAXDescriptionAttribute as String) ?? ""
        var actionNames: CFArray?
        AXUIElementCopyActionNames(child, &actionNames)
        let actions = (actionNames as? [String]) ?? []
        print(String(
            format: "  pos=%@ size=%@ | %@ %@ | 动作: %@",
            position.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "nil",
            size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil",
            title, description, actions.joined(separator: ",")
        ))
    }
}
