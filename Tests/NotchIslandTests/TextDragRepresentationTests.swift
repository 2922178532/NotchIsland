import XCTest
@testable import NotchIsland

/// 文本拖出时提供给接收方的各种表示形式。纯编码转换，不涉及真实拖拽。
final class TextDragRepresentationTests: XCTestCase {

    // MARK: - UTF-16

    /// `public.utf16-external-plain-text` 靠 BOM 声明字节序，必须带 BOM。
    func testExternalUTF16StartsWithBOM() {
        let data = ShelfItemView.utf16ExternalData(for: "刘海")
        XCTAssertGreaterThanOrEqual(data.count, 2)
        let bom = [data[data.startIndex], data[data.startIndex + 1]]
        XCTAssertTrue(bom == [0xFF, 0xFE] || bom == [0xFE, 0xFF], "缺少 BOM：\(bom)")
    }

    /// `public.utf16-plain-text` 是主机字节序且不带 BOM，
    /// 混用带 BOM 的数据会让接收方在正文开头多出一个 U+FEFF。
    func testHostUTF16HasNoBOM() {
        let data = ShelfItemView.utf16HostData(for: "刘海")
        XCTAssertEqual(data.count, 4, "两个汉字应为 4 字节，多出来的就是 BOM")
        let head = [data[data.startIndex], data[data.startIndex + 1]]
        XCTAssertNotEqual(head, [0xFF, 0xFE])
        XCTAssertNotEqual(head, [0xFE, 0xFF])
    }

    /// 两者都必须能被按各自约定解回原文。
    func testUTF16RoundTrips() {
        let text = "hello 刘海岛\n第二行"
        XCTAssertEqual(
            String(data: ShelfItemView.utf16ExternalData(for: text), encoding: .utf16),
            text
        )
        let hostEncoding: String.Encoding = CFByteOrderGetCurrent() == Int(CFByteOrderBigEndian.rawValue)
            ? .utf16BigEndian
            : .utf16LittleEndian
        XCTAssertEqual(
            String(data: ShelfItemView.utf16HostData(for: text), encoding: hostEncoding),
            text
        )
    }

    /// 主机表示比外部表示正好少一个 BOM（2 字节）。
    func testHostUTF16IsExactlyBOMShorter() {
        let text = "abc"
        XCTAssertEqual(
            ShelfItemView.utf16ExternalData(for: text).count - ShelfItemView.utf16HostData(for: text).count,
            2
        )
    }

    func testUTF16HandlesEmptyString() {
        XCTAssertTrue(ShelfItemView.utf16HostData(for: "").isEmpty)
    }

    /// 代理对（emoji）不能在编码时被截断。
    func testUTF16KeepsSurrogatePairs() {
        let text = "🏝️岛"
        XCTAssertEqual(
            String(data: ShelfItemView.utf16ExternalData(for: text), encoding: .utf16),
            text
        )
    }

    // MARK: - HTML

    func testHTMLEscapesMarkupCharacters() {
        let html = String(decoding: ShelfItemView.htmlRepresentation(for: "a<b>&\"c\""), as: UTF8.self)
        XCTAssertTrue(html.contains("a&lt;b&gt;&amp;&quot;c&quot;"), html)
        XCTAssertFalse(html.contains("<b>"))
    }

    /// `&` 必须先转义，否则 `<` 转出来的 `&lt;` 会被二次转义成 `&amp;lt;`。
    func testHTMLDoesNotDoubleEscapeAmpersand() {
        let html = String(decoding: ShelfItemView.htmlRepresentation(for: "<"), as: UTF8.self)
        XCTAssertTrue(html.contains("&lt;"), html)
        XCTAssertFalse(html.contains("&amp;lt;"), html)
    }

    func testHTMLConvertsNewlinesToBreaks() {
        let html = String(decoding: ShelfItemView.htmlRepresentation(for: "第一行\n第二行"), as: UTF8.self)
        XCTAssertTrue(html.contains("第一行<br>"), html)
        XCTAssertTrue(html.contains("第二行"), html)
    }

    /// 缺少 charset 声明时，中文会在部分接收方里变成乱码。
    func testHTMLDeclaresUTF8Charset() {
        let html = String(decoding: ShelfItemView.htmlRepresentation(for: "刘海岛"), as: UTF8.self)
        XCTAssertTrue(html.contains("charset=\"utf-8\""), html)
        XCTAssertTrue(html.contains("刘海岛"), html)
    }

    func testHTMLHandlesEmptyString() {
        let html = String(decoding: ShelfItemView.htmlRepresentation(for: ""), as: UTF8.self)
        XCTAssertTrue(html.contains("<div></div>"), html)
    }
}
