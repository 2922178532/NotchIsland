import AppKit
import QuickLookThumbnailing

/// 生成并缓存刘海岛文件的预览缩略图。
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func cacheKey(for item: ShelfItem, size: CGSize, scale: CGFloat) -> NSString {
        "\(item.storageID)-\(size.width)x\(size.height)@\(scale)" as NSString
    }

    static func thumbnail(for item: ShelfItem, at url: URL, size: CGSize) async -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = cacheKey(for: item, size: size, scale: scale)
        if let hit = cache.object(forKey: key) { return hit }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }

        // 大图不能复用卡片的 128pt 缩略图，否则悬浮预览会模糊。
        cache.totalCostLimit = 48 * 1024 * 1024
        let cost = Int(size.width * size.height * scale * scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
