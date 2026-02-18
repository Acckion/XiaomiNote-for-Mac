//
//  HeadingLevelPriorityTests.swift
//  MiNoteMac
//
//  字体大小标题检测测试
//  验证格式检测完全基于字体大小，因为在小米笔记中字体大小和标题类型是一一对应的
//
//  _需求: 2.1, 2.2, 2.3, 4.5_
//

import AppKit
import XCTest
@testable import MiNoteLibrary

@MainActor
final class HeadingLevelPriorityTests: XCTestCase {

    var editorContext: NativeEditorContext!

    override func setUp() async throws {
        try await super.setUp()
        editorContext = NativeEditorContext()
    }

    override func tearDown() async throws {
        editorContext = nil
        try await super.tearDown()
    }

    // MARK: - 字体大小标题检测测试

    /// 测试 23pt 字体应该识别为大标题
    /// _需求: 2.1, 4.5_
    func testFontSize23ptIsHeading1() {
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 23)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(
            editorContext.currentFormats.contains(.heading1),
            "23pt 字体应该识别为大标题"
        )
    }

    /// 测试 20pt 字体应该识别为二级标题
    /// _需求: 2.2, 4.5_
    func testFontSize20ptIsHeading2() {
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 20)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(
            editorContext.currentFormats.contains(.heading2),
            "20pt 字体应该识别为二级标题"
        )
    }

    /// 测试 17pt 字体应该识别为三级标题
    /// _需求: 2.3, 4.5_
    func testFontSize17ptIsHeading3() {
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 17)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(
            editorContext.currentFormats.contains(.heading3),
            "17pt 字体应该识别为三级标题"
        )
    }

    /// 测试 14pt 字体应该识别为正文（不是标题）
    /// _需求: 4.5_
    func testFontSize14ptIsBody() {
        let text = NSMutableAttributedString(string: "测试正文")
        let font = NSFont.systemFont(ofSize: 14)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading1),
            "14pt 字体不应该识别为大标题"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading2),
            "14pt 字体不应该识别为二级标题"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading3),
            "14pt 字体不应该识别为三级标题"
        )
    }

    /// 测试 13pt 字体应该识别为正文（不是标题）
    /// _需求: 4.5_
    func testFontSize13ptIsBody() {
        let text = NSMutableAttributedString(string: "测试正文")
        let font = NSFont.systemFont(ofSize: 13)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading1),
            "13pt 字体不应该识别为大标题"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading2),
            "13pt 字体不应该识别为二级标题"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading3),
            "13pt 字体不应该识别为三级标题"
        )
    }

    /// 测试边界值：22pt 应该识别为二级标题（小于 23pt 阈值）
    func testFontSize22ptIsHeading2() {
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 22)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(
            editorContext.currentFormats.contains(.heading2),
            "22pt 字体应该识别为二级标题（小于 23pt 阈值）"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading1),
            "22pt 字体不应该识别为大标题"
        )
    }

    /// 测试边界值：19pt 应该识别为三级标题（小于 20pt 阈值）
    func testFontSize19ptIsHeading3() {
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 19)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(
            editorContext.currentFormats.contains(.heading3),
            "19pt 字体应该识别为三级标题（小于 20pt 阈值）"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading2),
            "19pt 字体不应该识别为二级标题"
        )
    }

    /// 测试边界值：16pt 应该识别为正文（小于 17pt 阈值）
    func testFontSize16ptIsBody() {
        let text = NSMutableAttributedString(string: "测试正文")
        let font = NSFont.systemFont(ofSize: 16)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))

        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)

        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading3),
            "16pt 字体不应该识别为三级标题（小于 17pt 阈值）"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading2),
            "16pt 字体不应该识别为二级标题"
        )
        XCTAssertFalse(
            editorContext.currentFormats.contains(.heading1),
            "16pt 字体不应该识别为大标题"
        )
    }
}
