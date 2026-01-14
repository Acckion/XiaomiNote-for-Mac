//
//  HeadingLevelPriorityTests.swift
//  MiNoteMac
//
//  headingLevel 属性优先级验证测试
//  验证格式检测时优先使用 headingLevel 属性，忽略字体大小
//
//  _需求: 2.1, 2.2, 2.3, 4.5_
//

import XCTest
import AppKit
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
    
    // MARK: - headingLevel 属性优先级测试
    
    /// 测试当 headingLevel=1 且字体大小为 13pt 时，应该识别为大标题
    /// _需求: 2.1, 2.2, 4.5_
    func testHeadingLevel1WithSmallFontSize() {
        // 创建一个带有 headingLevel=1 但字体大小为 13pt 的文本
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 13)  // 正文字体大小
        
        // 添加字体属性
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        
        // 添加 headingLevel 自定义属性
        text.addAttribute(.headingLevel, value: 1, range: NSRange(location: 0, length: text.length))
        
        // 加载到编辑器
        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)
        
        // 等待格式检测完成
        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 验证：应该识别为大标题（headingLevel 优先级高于字体大小）
        XCTAssertTrue(editorContext.currentFormats.contains(.heading1), 
                     "当 headingLevel=1 时，即使字体大小为 13pt，也应该识别为大标题")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading2), 
                      "不应该识别为二级标题")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading3), 
                      "不应该识别为三级标题")
    }
    
    /// 测试当 headingLevel=2 且字体大小为 13pt 时，应该识别为二级标题
    /// _需求: 2.1, 2.2, 4.5_
    func testHeadingLevel2WithSmallFontSize() {
        // 创建一个带有 headingLevel=2 但字体大小为 13pt 的文本
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 13)  // 正文字体大小
        
        // 添加字体属性
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        
        // 添加 headingLevel 自定义属性
        text.addAttribute(.headingLevel, value: 2, range: NSRange(location: 0, length: text.length))
        
        // 加载到编辑器
        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)
        
        // 等待格式检测完成
        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 验证：应该识别为二级标题（headingLevel 优先级高于字体大小）
        XCTAssertTrue(editorContext.currentFormats.contains(.heading2), 
                     "当 headingLevel=2 时，即使字体大小为 13pt，也应该识别为二级标题")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading1), 
                      "不应该识别为大标题")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading3), 
                      "不应该识别为三级标题")
    }
    
    /// 测试当 headingLevel=3 且字体大小为 13pt 时，应该识别为三级标题
    /// _需求: 2.1, 2.2, 4.5_
    func testHeadingLevel3WithSmallFontSize() {
        // 创建一个带有 headingLevel=3 但字体大小为 13pt 的文本
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 13)  // 正文字体大小
        
        // 添加字体属性
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        
        // 添加 headingLevel 自定义属性
        text.addAttribute(.headingLevel, value: 3, range: NSRange(location: 0, length: text.length))
        
        // 加载到编辑器
        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)
        
        // 等待格式检测完成
        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 验证：应该识别为三级标题（headingLevel 优先级高于字体大小）
        XCTAssertTrue(editorContext.currentFormats.contains(.heading3), 
                     "当 headingLevel=3 时，即使字体大小为 13pt，也应该识别为三级标题")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading1), 
                      "不应该识别为大标题")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading2), 
                      "不应该识别为二级标题")
    }
    
    /// 测试当没有 headingLevel 且字体大小为 20pt 时，应该识别为大标题
    /// _需求: 2.1, 2.2, 4.5_
    func testNoHeadingLevelWithLargeFontSize() {
        // 创建一个没有 headingLevel 但字体大小为 20pt 的文本
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 20)  // 大标题字体大小
        
        // 添加字体属性
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        
        // 不添加 headingLevel 属性
        
        // 加载到编辑器
        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)
        
        // 等待格式检测完成
        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 验证：应该通过字体大小识别为大标题
        XCTAssertTrue(editorContext.currentFormats.contains(.heading1), 
                     "当没有 headingLevel 且字体大小为 20pt 时，应该识别为大标题")
    }
    
    /// 测试当 headingLevel=1 且字体大小为 20pt 时，应该识别为大标题
    /// 验证 headingLevel 和字体大小一致时的行为
    /// _需求: 2.1, 2.2, 4.5_
    func testHeadingLevel1WithMatchingFontSize() {
        // 创建一个带有 headingLevel=1 且字体大小为 20pt 的文本
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 20)  // 大标题字体大小
        
        // 添加字体属性
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        
        // 添加 headingLevel 自定义属性
        text.addAttribute(.headingLevel, value: 1, range: NSRange(location: 0, length: text.length))
        
        // 加载到编辑器
        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)
        
        // 等待格式检测完成
        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 验证：应该识别为大标题
        XCTAssertTrue(editorContext.currentFormats.contains(.heading1), 
                     "当 headingLevel=1 且字体大小为 20pt 时，应该识别为大标题")
    }
    
    /// 测试当 headingLevel=3 且字体大小为 20pt 时，应该识别为三级标题
    /// 验证 headingLevel 优先级高于字体大小（即使字体大小更大）
    /// _需求: 2.1, 2.2, 4.5_
    func testHeadingLevel3WithLargeFontSize() {
        // 创建一个带有 headingLevel=3 但字体大小为 20pt 的文本
        let text = NSMutableAttributedString(string: "测试标题")
        let font = NSFont.systemFont(ofSize: 20)  // 大标题字体大小
        
        // 添加字体属性
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        
        // 添加 headingLevel 自定义属性（与字体大小不匹配）
        text.addAttribute(.headingLevel, value: 3, range: NSRange(location: 0, length: text.length))
        
        // 加载到编辑器
        editorContext.updateNSContent(text)
        editorContext.updateCursorPosition(0)
        
        // 等待格式检测完成
        let expectation = XCTestExpectation(description: "格式检测完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 验证：应该识别为三级标题（headingLevel 优先级高于字体大小）
        XCTAssertTrue(editorContext.currentFormats.contains(.heading3), 
                     "当 headingLevel=3 时，即使字体大小为 20pt，也应该识别为三级标题（headingLevel 优先）")
        XCTAssertFalse(editorContext.currentFormats.contains(.heading1), 
                      "不应该识别为大标题（即使字体大小符合大标题）")
    }
}
