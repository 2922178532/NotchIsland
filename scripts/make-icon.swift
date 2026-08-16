#!/usr/bin/env swift
// 生成 Resources/AppIcon.icns。
// 用法：swift scripts/make-icon.swift

import AppKit
import Foundation

let referenceSize: CGFloat = 1024

/// 按 macOS 图标规范：内容是一块 824×824 的圆角方板，四周留出投影空间。
func drawIcon(pixelSize: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixelSize)
    let scale = size / referenceSize

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("无法创建位图")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let plate = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185 * scale, yRadius: 185 * scale)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.62, green: 0.36, blue: 0.98, alpha: 1),
    ])!
    gradient.draw(in: platePath, angle: -60)

    platePath.setClip()

    // 顶部的刘海：顶边平直，底部两角收圆。
    let notchWidth = 340 * scale
    let notchHeight = 112 * scale
    let radius = 54 * scale
    let notch = NSRect(
        x: plate.midX - notchWidth / 2,
        y: plate.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight
    )

    let notchPath = NSBezierPath()
    notchPath.move(to: NSPoint(x: notch.minX, y: notch.maxY))
    notchPath.line(to: NSPoint(x: notch.minX, y: notch.minY + radius))
    notchPath.appendArc(
        withCenter: NSPoint(x: notch.minX + radius, y: notch.minY + radius),
        radius: radius,
        startAngle: 180,
        endAngle: 270
    )
    notchPath.line(to: NSPoint(x: notch.maxX - radius, y: notch.minY))
    notchPath.appendArc(
        withCenter: NSPoint(x: notch.maxX - radius, y: notch.minY + radius),
        radius: radius,
        startAngle: 270,
        endAngle: 360
    )
    notchPath.line(to: NSPoint(x: notch.maxX, y: notch.maxY))
    notchPath.close()
    NSColor.black.setFill()
    notchPath.fill()

    // 刘海下方的托盘符号。
    let symbolSize = 340 * scale
    let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let target = NSRect(
            x: plate.midX - symbol.size.width / 2,
            y: plate.midY - symbol.size.height / 2 - 44 * scale,
            width: symbol.size.width,
            height: symbol.size.height
        )
        // 染色必须在独立的透明画布里做，否则 sourceAtop 会把底下的渐变一起染白。
        let white = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        white.draw(in: target)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = projectRoot.appendingPathComponent("build/AppIcon.iconset")
let outputURL = projectRoot.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = drawIcon(pixelSize: variant.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("无法编码 \(variant.name)")
    }
    try data.write(to: iconsetURL.appendingPathComponent("\(variant.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconsetURL.path, "--output", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil 失败")
}
print("已生成 \(outputURL.path)")
