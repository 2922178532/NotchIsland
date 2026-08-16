import AppKit
import QuickLookThumbnailing

/// 生成并缓存刘海岛文件的预览缩略图。
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func cached(for item: ShelfItem) -> NSImage? {
        cache.object(forKey: item.storageID as NSString)
    }

    static func thumbnail(for item: ShelfItem, at url: URL, size: CGSize) async -> NSImage {
        if let hit = cached(for: item) { return hit }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }

        cache.setObject(image, forKey: item.storageID as NSString)
        return image
    }
}
