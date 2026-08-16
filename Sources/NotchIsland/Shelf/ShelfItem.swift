import AppKit
import UniformTypeIdentifiers

/// 刘海岛内容的分类，用于展开面板里的筛选。
enum ShelfCategory: String, CaseIterable, Identifiable {
    case file = "文件"
    case image = "图片"
    case text = "文本"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .file: "doc.fill"
        case .image: "photo.fill"
        case .text: "text.alignleft"
        }
    }
}

/// 刘海岛里的一项暂存内容。
///
/// 文件本体被复制到应用的暂存目录中（`storageID` 对应的子目录），
/// 因此原文件被移动或删除后，刘海岛里的副本依然可用。
struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    /// 暂存目录中的子目录名，等于 `id.uuidString`。
    let storageID: String
    /// 展示与拖出时使用的文件名，保留原始扩展名。
    var fileName: String
    /// 加入刘海岛前的原始路径，用于「在访达中显示原位置」。
    var originalPath: String?
    var addedAt: Date
    var byteSize: Int64
    var isDirectory: Bool
    var typeIdentifier: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        originalPath: String?,
        addedAt: Date = Date(),
        byteSize: Int64,
        isDirectory: Bool,
        typeIdentifier: String?
    ) {
        self.id = id
        self.storageID = id.uuidString
        self.fileName = fileName
        self.originalPath = originalPath
        self.addedAt = addedAt
        self.byteSize = byteSize
        self.isDirectory = isDirectory
        self.typeIdentifier = typeIdentifier
    }

    var contentType: UTType? {
        if let typeIdentifier, let type = UTType(typeIdentifier) { return type }
        return UTType(filenameExtension: (fileName as NSString).pathExtension)
    }

    var category: ShelfCategory {
        if isDirectory { return .file }
        guard let type = contentType else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .text) || type.conforms(to: .internetShortcut) { return .text }
        return .file
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
