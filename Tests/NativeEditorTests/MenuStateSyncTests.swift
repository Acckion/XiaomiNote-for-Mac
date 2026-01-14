//
//  MenuStateSyncTests.swift
//  MiNoteLibraryTests
//
//  格式菜单状态同步测试 - 验证格式菜单能正确反映段落样式变化
//  验证需求: 1.4, 1.5, 3.1, 3.2, 3.3
//
//  Feature: format-menu-paragraph-style-fix, Task 6: 测试格式菜单状态同步
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 格式菜单状态同步测试
/// 
/// 本测试套件验证格式菜单能正确反映段落样式变化，包括：
/// 1. 正文、大标题、二级标题、三级标题的格式状态检测
/// 2. 格式状态互斥性（只有一个段落样式被激活）
/// 3. 状态同步的及时性
@MainActor
final class MenuStateSyncTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var formatStateManager: FormatStateManager!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的编辑器上下文
        editorContext = NativeEditorContext()
        
        // 获取格式状态管理器的共享实例
        formatStateManager = FormatStateManager.shared
        
        print("[MenuStateSyncTests] 测试环境设置完成")
    }
    
    override func tearDown() async throws {
        // 清理
        editorContext = nil
        formatStateManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - 测试：正文格式状态检测
    // 验证需求: 1.4, 1.5, 3.2
    
    /// 测试正文格式时状态正确
    /// 
    /// **验证**: 当段落样式为正文时，格式状态应该正确反映为正文
    /// **需求**: 1.4, 1.5, 3.2
    func testBodyTextFormatState() async throws {
        print("\n[Test] 测试正文格式状态检测")
        
        // 1. 设置正文文本
        let bodyText = "这是一段正文内容"
        let attributedString = NSMutableAttributedString(string: bodyText)
        let bodyFont = NSFont.systemFont(ofSize: 13)  // 正文字体大小
        attributedString.addAttribute(.font, value: bodyFont, range: NSRange(location: 0, length: bodyText.count))
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        editorContext.forceUpdateFormats()
        
        // 3. 等待状态更新
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 4. 获取当前格式状态（直接从编辑器上下文）
        let currentFormats = editorContext.currentFormats
        
        // 5. 验证段落格式为正文（没有标题格式）
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        XCTAssertFalse(currentFormats.contains(.heading3), "不应该包含三级标题格式")
        
        // 6. 验证段落样式字符串
        let paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "body", "段落样式应该是 body")
        
        print("[Test] ✓ 正文格式状态检测测试通过")
    }
    
    // MARK: - 测试：大标题格式状态检测
    // 验证需求: 1.4, 1.5, 3.2
    
    /// 测试大标题格式时状态正确
    /// 
    /// **验证**: 当段落样式为大标题时，格式状态应该正确反映为大标题
    /// **需求**: 1.4, 1.5, 3.2
    func testHeading1FormatState() async throws {
        print("\n[Test] 测试大标题格式状态检测")
        
        // 1. 设置大标题文本
        let headingText = "这是大标题"
        let attributedString = NSMutableAttributedString(string: headingText)
        let headingFont = NSFont.systemFont(ofSize: 22)  // 大标题字体大小
        attributedString.addAttribute(.font, value: headingFont, range: NSRange(location: 0, length: headingText.count))
        
        // 添加 headingLevel 属性
        attributedString.addAttribute(
            NSAttributedString.Key("headingLevel"),
            value: 1,
            range: NSRange(location: 0, length: headingText.count)
        )
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        editorContext.forceUpdateFormats()
        
        // 3. 等待状态更新
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 4. 获取当前格式状态
        let currentFormats = editorContext.currentFormats
        
        // 5. 验证包含大标题格式
        XCTAssertTrue(currentFormats.contains(.heading1), "应该包含大标题格式")
        
        // 6. 验证格式状态互斥性
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        XCTAssertFalse(currentFormats.contains(.heading3), "不应该包含三级标题格式")
        
        // 7. 验证段落样式字符串
        let paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "heading", "段落样式应该是 heading")
        
        print("[Test] ✓ 大标题格式状态检测测试通过")
    }
    
    // MARK: - 测试：二级标题格式状态检测
    // 验证需求: 1.4, 1.5, 3.2
    
    /// 测试二级标题格式时状态正确
    /// 
    /// **验证**: 当段落样式为二级标题时，格式状态应该正确反映为二级标题
    /// **需求**: 1.4, 1.5, 3.2
    func testHeading2FormatState() async throws {
        print("\n[Test] 测试二级标题格式状态检测")
        
        // 1. 设置二级标题文本
        let headingText = "这是二级标题"
        let attributedString = NSMutableAttributedString(string: headingText)
        let headingFont = NSFont.systemFont(ofSize: 18)  // 二级标题字体大小
        attributedString.addAttribute(.font, value: headingFont, range: NSRange(location: 0, length: headingText.count))
        
        // 添加 headingLevel 属性
        attributedString.addAttribute(
            NSAttributedString.Key("headingLevel"),
            value: 2,
            range: NSRange(location: 0, length: headingText.count)
        )
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        editorContext.forceUpdateFormats()
        
        // 3. 等待状态更新
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 4. 获取当前格式状态
        let currentFormats = editorContext.currentFormats
        
        // 5. 验证包含二级标题格式
        XCTAssertTrue(currentFormats.contains(.heading2), "应该包含二级标题格式")
        
        // 6. 验证格式状态互斥性
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading3), "不应该包含三级标题格式")
        
        // 7. 验证段落样式字符串
        let paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "subheading", "段落样式应该是 subheading")
        
        print("[Test] ✓ 二级标题格式状态检测测试通过")
    }
    
    // MARK: - 测试：三级标题格式状态检测
    // 验证需求: 1.4, 1.5, 3.2
    
    /// 测试三级标题格式时状态正确
    /// 
    /// **验证**: 当段落样式为三级标题时，格式状态应该正确反映为三级标题
    /// **需求**: 1.4, 1.5, 3.2
    func testHeading3FormatState() async throws {
        print("\n[Test] 测试三级标题格式状态检测")
        
        // 1. 设置三级标题文本
        let headingText = "这是三级标题"
        let attributedString = NSMutableAttributedString(string: headingText)
        let headingFont = NSFont.systemFont(ofSize: 16)  // 三级标题字体大小
        attributedString.addAttribute(.font, value: headingFont, range: NSRange(location: 0, length: headingText.count))
        
        // 添加 headingLevel 属性
        attributedString.addAttribute(
            NSAttributedString.Key("headingLevel"),
            value: 3,
            range: NSRange(location: 0, length: headingText.count)
        )
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        editorContext.forceUpdateFormats()
        
        // 3. 等待状态更新
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 4. 获取当前格式状态
        let currentFormats = editorContext.currentFormats
        
        // 5. 验证包含三级标题格式
        XCTAssertTrue(currentFormats.contains(.heading3), "应该包含三级标题格式")
        
        // 6. 验证格式状态互斥性
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        
        // 7. 验证段落样式字符串
        let paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "subtitle", "段落样式应该是 subtitle")
        
        print("[Test] ✓ 三级标题格式状态检测测试通过")
    }
    
    // MARK: - 测试：段落样式切换时状态更新
    // 验证需求: 3.1, 3.2, 3.3
    
    /// 测试段落样式切换时状态正确更新
    /// 
    /// **验证**: 当段落样式从一种切换到另一种时，格式状态应该正确更新，保持互斥性
    /// **需求**: 3.1, 3.2, 3.3
    func testParagraphStyleSwitchingFormatState() async throws {
        print("\n[Test] 测试段落样式切换时状态更新")
        
        // 1. 初始状态：正文
        let bodyText = "这是正文"
        var attributedString = NSMutableAttributedString(string: bodyText)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        attributedString.addAttribute(.font, value: bodyFont, range: NSRange(location: 0, length: bodyText.count))
        
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(0)
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        var currentFormats = editorContext.currentFormats
        var paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "body", "初始段落样式应该是 body")
        
        // 2. 切换到大标题
        print("[Test] 切换到大标题...")
        attributedString = NSMutableAttributedString(string: bodyText)
        let heading1Font = NSFont.systemFont(ofSize: 22)
        attributedString.addAttribute(.font, value: heading1Font, range: NSRange(location: 0, length: bodyText.count))
        attributedString.addAttribute(
            NSAttributedString.Key("headingLevel"),
            value: 1,
            range: NSRange(location: 0, length: bodyText.count)
        )
        
        editorContext.updateNSContent(attributedString)
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        currentFormats = editorContext.currentFormats
        paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "heading", "段落样式应该是 heading")
        XCTAssertTrue(currentFormats.contains(.heading1), "应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        
        // 3. 切换到二级标题
        print("[Test] 切换到二级标题...")
        attributedString = NSMutableAttributedString(string: bodyText)
        let heading2Font = NSFont.systemFont(ofSize: 18)
        attributedString.addAttribute(.font, value: heading2Font, range: NSRange(location: 0, length: bodyText.count))
        attributedString.addAttribute(
            NSAttributedString.Key("headingLevel"),
            value: 2,
            range: NSRange(location: 0, length: bodyText.count)
        )
        
        editorContext.updateNSContent(attributedString)
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        currentFormats = editorContext.currentFormats
        paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "subheading", "段落样式应该是 subheading")
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertTrue(currentFormats.contains(.heading2), "应该包含二级标题格式")
        
        // 4. 切换回正文
        print("[Test] 切换回正文...")
        attributedString = NSMutableAttributedString(string: bodyText)
        attributedString.addAttribute(.font, value: bodyFont, range: NSRange(location: 0, length: bodyText.count))
        
        editorContext.updateNSContent(attributedString)
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        currentFormats = editorContext.currentFormats
        paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "body", "段落样式应该是 body")
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        
        print("[Test] ✓ 段落样式切换状态更新测试通过")
    }
    
    // MARK: - 测试：格式状态互斥性
    // 验证需求: 1.4, 1.5, 3.2, 3.3
    
    /// 测试格式状态互斥性
    /// 
    /// **验证**: 在任何时候，只有一个段落样式格式应该被激活
    /// **需求**: 1.4, 1.5, 3.2, 3.3
    func testFormatStateExclusivity() async throws {
        print("\n[Test] 测试格式状态互斥性")
        
        // 测试所有段落样式
        let testCases: [(String, CGFloat, Int?)] = [
            ("body", 13, nil),
            ("heading", 22, 1),
            ("subheading", 18, 2),
            ("subtitle", 16, 3)
        ]
        
        for (expectedStyle, fontSize, headingLevel) in testCases {
            print("[Test] 测试 \(expectedStyle) 的格式状态互斥性...")
            
            // 1. 设置文本
            let text = "测试文本"
            let attributedString = NSMutableAttributedString(string: text)
            let font = NSFont.systemFont(ofSize: fontSize)
            attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.count))
            
            if let level = headingLevel {
                attributedString.addAttribute(
                    NSAttributedString.Key("headingLevel"),
                    value: level,
                    range: NSRange(location: 0, length: text.count)
                )
            }
            
            // 2. 更新编辑器内容
            editorContext.updateNSContent(attributedString)
            editorContext.updateCursorPosition(0)
            editorContext.forceUpdateFormats()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // 3. 获取格式状态
            let currentFormats = editorContext.currentFormats
            let paragraphStyle = editorContext.getCurrentParagraphStyleString()
            
            // 4. 验证段落样式正确
            XCTAssertEqual(paragraphStyle, expectedStyle, "段落样式应该是 \(expectedStyle)")
            
            // 5. 验证只有一个标题格式被激活
            let heading1Active = currentFormats.contains(.heading1)
            let heading2Active = currentFormats.contains(.heading2)
            let heading3Active = currentFormats.contains(.heading3)
            
            let activeCount = [heading1Active, heading2Active, heading3Active].filter { $0 }.count
            
            // 对于正文，应该没有标题格式被激活
            if expectedStyle == "body" {
                XCTAssertEqual(activeCount, 0, "正文格式时，不应该有标题格式被激活")
            } else {
                // 对于标题，应该只有一个标题格式被激活
                XCTAssertEqual(activeCount, 1, "应该只有一个标题格式被激活")
            }
        }
        
        print("[Test] ✓ 格式状态互斥性测试通过")
    }
}
