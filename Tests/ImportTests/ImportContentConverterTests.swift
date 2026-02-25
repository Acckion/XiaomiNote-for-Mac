//
//  ImportContentConverterTests.swift
//  MiNoteLibraryTests
//
//  导入内容转换器回归测试
//  验证 plainTextToXML、markdownToXML、rtfToXML 的转换产出格式正确
//

import XCTest
@testable import MiNoteLibrary

final class ImportContentConverterTests: XCTestCase {

    // MARK: - plainTextToXML

    func testPlainTextToXML_singleLine() {
        let result = ImportContentConverter.plainTextToXML("Hello World")

        XCTAssertTrue(result.contains("<text indent=\"1\">"))
        XCTAssertTrue(result.contains("Hello World"))
    }

    func testPlainTextToXML_multipleLines() {
        let result = ImportContentConverter.plainTextToXML("Line1\nLine2\nLine3")

        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("Line1"))
        XCTAssertTrue(lines[1].contains("Line2"))
        XCTAssertTrue(lines[2].contains("Line3"))
    }

    func testPlainTextToXML_emptyInput() {
        let result = ImportContentConverter.plainTextToXML("")

        XCTAssertEqual(result, "<text indent=\"1\"></text>")
    }

    // MARK: - markdownToXML 标题

    func testMarkdownToXML_heading1() {
        let result = ImportContentConverter.markdownToXML("# Title")

        XCTAssertTrue(result.contains("<head level=\"1\">"))
        XCTAssertTrue(result.contains("Title"))
    }

    func testMarkdownToXML_heading2() {
        let result = ImportContentConverter.markdownToXML("## Subtitle")

        XCTAssertTrue(result.contains("<head level=\"2\">"))
        XCTAssertTrue(result.contains("Subtitle"))
    }

    func testMarkdownToXML_heading3() {
        let result = ImportContentConverter.markdownToXML("### Section")

        XCTAssertTrue(result.contains("<head level=\"3\">"))
        XCTAssertTrue(result.contains("Section"))
    }

    // MARK: - markdownToXML 列表

    func testMarkdownToXML_unorderedList() {
        let result = ImportContentConverter.markdownToXML("- Item A")

        XCTAssertTrue(result.contains("<list type=\"unordered\">"))
        XCTAssertTrue(result.contains("Item A"))
    }

    func testMarkdownToXML_orderedList() {
        let result = ImportContentConverter.markdownToXML("1. First")

        XCTAssertTrue(result.contains("<list type=\"ordered\">"))
        XCTAssertTrue(result.contains("First"))
    }

    // MARK: - markdownToXML 待办

    func testMarkdownToXML_uncheckedTodo() {
        let result = ImportContentConverter.markdownToXML("- [ ] Task")

        XCTAssertTrue(result.contains("<todo checked=\"false\">"))
        XCTAssertTrue(result.contains("Task"))
    }

    func testMarkdownToXML_checkedTodo() {
        let result = ImportContentConverter.markdownToXML("- [x] Done")

        XCTAssertTrue(result.contains("<todo checked=\"true\">"))
        XCTAssertTrue(result.contains("Done"))
    }

    // MARK: - markdownToXML 引用

    func testMarkdownToXML_quote() {
        let result = ImportContentConverter.markdownToXML("> Quote text")

        XCTAssertTrue(result.contains("<quote>"))
        XCTAssertTrue(result.contains("Quote text"))
    }

    // MARK: - markdownToXML 空输入

    func testMarkdownToXML_emptyInput() {
        let result = ImportContentConverter.markdownToXML("")

        XCTAssertEqual(result, "<text indent=\"1\"></text>")
    }

    // MARK: - rtfToXML

    func testRtfToXML_validRTF() {
        // 构造一个简单的 RTF 数据
        let rtfString = "{\\rtf1\\ansi Hello RTF}"
        guard let rtfData = rtfString.data(using: .utf8) else {
            XCTFail("RTF 数据构造失败")
            return
        }

        let result = ImportContentConverter.rtfToXML(rtfData)

        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("<text indent=\"1\">"))
    }

    func testRtfToXML_invalidData() {
        let invalidData = Data([0x00, 0x01, 0x02])

        let result = ImportContentConverter.rtfToXML(invalidData)

        // 无效数据应降级为空内容
        XCTAssertEqual(result, "<text indent=\"1\"></text>")
    }
}
