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
}
