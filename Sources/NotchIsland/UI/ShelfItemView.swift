import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 刘海岛里的单个文件卡片：可拖出、可双击打开、可右键操作。
struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    /// 拖拽开始时通知外部，避免岛在拖到一半时收起。
    var onDragOut: () -> Void = {}

    @State private var thumbnail: NSImage?
    @State private var textPreview: String?
    @State private var isHovering = false

    private let iconSize = CGSize(width: 60, height: 60)

    private var isLink: Bool {
        item.contentType?.conforms(to: .internetShortcut) == true
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.16 : 0.09))

                if item.category == .text {
                    textCard
                } else if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize.width - 12, height: iconSize.height - 12)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.6))
                }
            }
            .frame(width: iconSize.width, height: iconSize.height)
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button {
                        store.remove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            Text(item.fileName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 74)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help(helpText)
        .onDrag {
            makeDragProvider()
        } preview: {
            dragPreview
        }
        .onTapGesture(count: 2) {
            store.open(item)
        }
        .contextMenu {
            Button("打开") { store.open(item) }
            Button("复制到剪贴板") { store.copyToPasteboard(item) }
            Button("在访达中显示") { store.revealInFinder(item) }
            if item.originalPath != nil {
                Button("显示原始位置") { store.revealOriginal(item) }
            }
            Divider()
            Button("移除", role: .destructive) { store.remove(item) }
        }
        .task(id: item.id) {
            let url = store.fileURL(for: item)
            if item.category == .text {
                textPreview = Self.loadTextPreview(from: url)
            } else {
                thumbnail = await ThumbnailLoader.thumbnail(for: item, at: url, size: CGSize(width: 128, height: 128))
            }
        }
    }

    /// 文本 / 链接的「小便签」卡片：直接把内容画出来，
    /// 比 QuickLook 的整页文档缩略图直观得多。
    @ViewBuilder
    private var textCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(white: 0.94))

            if let textPreview {
                if isLink {
                    VStack(alignment: .leading, spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text(linkDisplayText(textPreview))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.85))
                            .lineLimit(4)
                    }
                    .padding(5)
                } else {
                    Text(textPreview)
                        .font(.system(size: 6.5))
                        .foregroundStyle(.black.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .lineLimit(7)
                        .padding(5)
                }
            }
        }
        .frame(width: iconSize.width - 12, height: iconSize.height - 12)
    }

    private var helpText: String {
        if item.category == .text, let textPreview, !textPreview.isEmpty {
            return String(textPreview.prefix(200)) + "\n—\n\(item.formattedSize) · 拖出到任意应用"
        }
        return "\(item.fileName)\n\(item.formattedSize) · 拖出到任意应用"
    }

    /// 链接只显示域名和路径开头，去掉协议前缀的噪音。
    private func linkDisplayText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    /// 读取文本开头一小段作预览；`.url` 链接文件解析出其中的网址。
    private static func loadTextPreview(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2048), !data.isEmpty else { return "" }

        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("[InternetShortcut]") {
            if let urlLine = text.split(separator: "\n").first(where: { $0.hasPrefix("URL=") }) {
                text = String(urlLine.dropFirst(4))
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dragPreview: some View {
        HStack(spacing: 6) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            Text(item.fileName)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 以「复制」语义提供文件：接收方拿到的是副本，刘海岛里的暂存文件不会被移走。
    private func makeDragProvider() -> NSItemProvider {
        onDragOut()
        let url = store.fileURL(for: item)
        let provider = NSItemProvider()
        provider.suggestedName = item.fileName

        // 文本 / 链接条目只提供文字本身，不附带文件形态：
        // 微信这类应用只要在拖拽里发现文件就会当附件处理，完全无视格式优先级，
        // 想让它们插入文字，就不能给它们文件可选。需要原始 txt 时用右键「在访达中显示」。
        if let text = store.textContent(of: item) {
            provider.registerObject(text as NSString, visibility: .all)

            // 不同 App 对文本拖拽读取的 UTI 不一致：现代 App 通常读取
            // `public.utf8-plain-text`，部分原生/老 App 只请求
            // `public.plain-text` 或 UTF-16，富文本编辑器则优先 RTF/HTML。
            // 同时注册多种表示，让接收方按自己支持的类型协商，不改变
            // 文本条目“不提供文件 URL”的语义。
            registerTextRepresentations(text, on: provider)
            return provider
        }

        // 标准文件路径（public.file-url)：微信、QQ 这类自绘界面的应用
        // 只认这种「和从访达拖出一样」的格式，缺了它们就收不到文件。
        provider.registerObject(url as NSURL, visibility: .all)

        // 2) 文件内容承诺：现代应用走这条路，接收方会复制副本。
        let type = item.contentType ?? (item.isDirectory ? .folder : .data)
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(url, false, nil)
            return nil
        }
        return provider
    }

    /// 为同一段文字注册常见的拖拽表示，覆盖原生控件、老式 App 和富文本编辑器。
    private func registerTextRepresentations(_ text: String, on provider: NSItemProvider) {
        let utf8 = Data(text.utf8)

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.text.identifier,
            visibility: .all
        ) { completion in
            completion(utf8, nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(utf8, nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(utf8, nil)
            return nil
        }
        // 两种 UTF-16 的约定不同，数据不能共用：
        // `public.utf16-external-plain-text` 要求带 BOM 声明字节序；
        // `public.utf16-plain-text` 是主机字节序且不带 BOM，混用会让接收方
        // 把 BOM 当成正文，开头多出一个不可见的 U+FEFF。
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf16ExternalPlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Self.utf16ExternalData(for: text), nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf16PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Self.utf16HostData(for: text), nil)
            return nil
        }

        if let rtf = NSAttributedString(string: text).rtf(
            from: NSRange(location: 0, length: text.utf16.count),
            documentAttributes: [:]
        ) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.rtf.identifier,
                visibility: .all
            ) { completion in
                completion(rtf, nil)
                return nil
            }
        }

        let html = Self.htmlRepresentation(for: text)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.html.identifier,
            visibility: .all
        ) { completion in
            completion(html, nil)
            return nil
        }
    }

    /// `public.utf16-external-plain-text`：带 BOM，接收方靠 BOM 判断字节序。
    static func utf16ExternalData(for text: String) -> Data {
        text.data(using: .utf16) ?? Data()
    }

    /// `public.utf16-plain-text`：主机字节序、不带 BOM。
    /// Apple 现役平台都是小端，这里仍按运行时字节序取，避免写死假设。
    static func utf16HostData(for text: String) -> Data {
        let encoding: String.Encoding = CFByteOrderGetCurrent() == Int(CFByteOrderBigEndian.rawValue)
            ? .utf16BigEndian
            : .utf16LittleEndian
        return text.data(using: encoding) ?? Data()
    }

    /// 生成最小 HTML 表示，保留换行并避免文本被解释成标签或实体。
    static func htmlRepresentation(for text: String) -> Data {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>\n")
        let html = "<meta charset=\"utf-8\"><div>\(escaped)</div>"
        return Data(html.utf8)
    }
}
