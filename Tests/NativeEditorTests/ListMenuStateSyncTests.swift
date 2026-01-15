//
//  ListMenuStateSyncTests.swift
//  MiNoteLibraryTests
//
//  列表格式菜单状态同步测试 - 验证列表格式能正确反映在菜单状态中
//  验证需求: 11.1, 11.2, 11.3
//
//  Feature: list-format-enhancement, Task 7: 实现菜单状态同步
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 列表格式菜单状态同步测试
/// 
/// 本测试套件验证列表格式能正确反映在菜单状态中，包括：
/// 1. 无序列表格式状态检测
/// 2. 有序列表格式状态检测
/// 3. 光标移动时菜单状态正确更新
@MainActor
final class ListMenuStateSyncTests: XCTestCase {
    
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
        
        print("[ListMenuStateSyncTests] 测试环境设置完成")
    }
    
    override func tearDown() async throws {
        // 清理
        editorContext = nil
        formatStateManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - 测试辅助方法
    
    /// 创建带有无序列表的 NSAttributedString
    private func createBulletListAttributedString(text: String) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString()
        
        // 创建 BulletAttachment
        let bulletAttachment = BulletAttachment(indent: 1)
        let attachmentString = NSAttributedString(attachment: bulletAttachment)
        attributedString.append(attachmentString)
        
        // 添加文本内容
        let textString = NSAttributedString(string: text)
        attributedString.append(textString)
        
        // 设置 listType 属性
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.addAttribute(.listType, value: ListType.bullet, range: fullRange)
        
        return attributedString
    }
    
    /// 创建带有有序列表的 NSAttributedString
    private func createOrderedListAttributedString(text: String, number: Int = 1) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString()
        
        // 创建 OrderAttachment
        let orderAttachment = OrderAttachment(number: number, inputNumber: 0, indent: 1)
        let attachmentString = NSAttributedString(attachment: orderAttachment)
        attributedString.append(attachmentString)
        
        // 添加文本内容
        let textString = NSAttributedString(string: text)
        attributedString.append(textString)
        
        // 设置 listType 属性
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.addAttribute(.listType, value: ListType.ordered, range: fullRange)
        
        return attributedString
    }
    
    // MARK: - 测试：无序列表格式状态检测
    // 验证需求: 11.1
    
    /// 测试无序列表格式时状态正确
    /// 
    /// **验证**: 当光标位于无序列表行时，格式状态应该正确反映为无序列表
    func testBulletListFormatState() async throws {
        print("\n[Test] 测试无序列表格式状态检测")
        
        // 1. 创建无序列表文本
        let attributedString = createBulletListAttributedString(text: "无序列表项\n")
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(1)  // 光标在附件后
        editorContext.forceUpdateFormats()
        
        // 3. 等待状态更新
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 4. 获取当前格式状态
        let currentFormats = editorContext.currentFormats
        
        // 5. 验证包含无序列表格式
        XCTAssertTrue(currentFormats.contains(.bulletList), "应该包含无序列表格式")
        
        // 6. 验证格式状态互斥性
        XCTAssertFalse(currentFormats.contains(.numberedList), "不应该包含有序列表格式")
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        XCTAssertFalse(currentFormats.contains(.heading3), "不应该包含三级标题格式")
        
        // 7. 验证段落样式字符串
        let paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "unorderedList", "段落样式应该是 unorderedList")
        
        print("[Test] ✓ 无序列表格式状态检测测试通过")
    }
    
    // MARK: - 测试：有序列表格式状态检测
    // 验证需求: 11.2
    
    /// 测试有序列表格式时状态正确
    /// 
    /// **验证**: 当光标位于有序列表行时，格式状态应该正确反映为有序列表
    func testOrderedListFormatState() async throws {
        print("\n[Test] 测试有序列表格式状态检测")
        
        // 1. 创建有序列表文本
        let attributedString = createOrderedListAttributedString(text: "有序列表项\n")
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(1)  // 光标在附件后
        editorContext.forceUpdateFormats()
        
        // 3. 等待状态更新
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 4. 获取当前格式状态
        let currentFormats = editorContext.currentFormats
        
        // 5. 验证包含有序列表格式
        XCTAssertTrue(currentFormats.contains(.numberedList), "应该包含有序列表格式")
        
        // 6. 验证格式状态互斥性
        XCTAssertFalse(currentFormats.contains(.bulletList), "不应该包含无序列表格式")
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        XCTAssertFalse(currentFormats.contains(.heading3), "不应该包含三级标题格式")
        
        // 7. 验证段落样式字符串
        let paragraphStyle = editorContext.getCurrentParagraphStyleString()
        XCTAssertEqual(paragraphStyle, "orderedList", "段落样式应该是 orderedList")
        
        print("[Test] ✓ 有序列表格式状态检测测试通过")
    }
    
    // MARK: - 测试：光标移动时菜单状态更新
    // 验证需求: 11.3
    
    /// 测试光标移动到不同格式行时状态正确更新
    /// 
    /// **验证**: 当光标从普通文本移动到列表行时，格式状态应该正确更新
    func testCursorMoveUpdatesListFormatState() async throws {
        print("\n[Test] 测试光标移动时菜单状态更新")
        
        // 1. 创建混合内容：普通文本 + 无序列表
        let attributedString = NSMutableAttributedString()
        
        // 添加普通文本行
        let bodyText = NSAttributedString(string: "普通文本\n")
        attributedString.append(bodyText)
        
        // 添加无序列表行
        let bulletList = createBulletListAttributedString(text: "无序列表项\n")
        attributedString.append(bulletList)
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        
        // 3. 光标在普通文本行
        editorContext.updateCursorPosition(2)  // 在"普通文本"中间
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        var currentFormats = editorContext.currentFormats
        var paragraphStyle = editorContext.getCurrentParagraphStyleString()
        
        XCTAssertFalse(currentFormats.contains(.bulletList), "普通文本行不应该包含无序列表格式")
        XCTAssertEqual(paragraphStyle, "body", "普通文本行的段落样式应该是 body")
        
        // 4. 移动光标到无序列表行
        let listLineStart = 5  // "普通文本\n" 后面
        editorContext.updateCursorPosition(listLineStart + 1)  // 在附件后
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        currentFormats = editorContext.currentFormats
        paragraphStyle = editorContext.getCurrentParagraphStyleString()
        
        XCTAssertTrue(currentFormats.contains(.bulletList), "无序列表行应该包含无序列表格式")
        XCTAssertEqual(paragraphStyle, "unorderedList", "无序列表行的段落样式应该是 unorderedList")
        
        print("[Test] ✓ 光标移动时菜单状态更新测试通过")
    }
    
    // MARK: - 测试：列表格式与标题格式互斥
    // 验证需求: 11.1, 11.2
    
    /// 测试列表格式与标题格式互斥
    /// 
    /// **验证**: 列表格式和标题格式不能同时存在
    func testListAndHeadingMutualExclusion() async throws {
        print("\n[Test] 测试列表格式与标题格式互斥")
        
        // 1. 创建无序列表文本
        let attributedString = createBulletListAttributedString(text: "列表项\n")
        
        // 2. 更新编辑器内容
        editorContext.updateNSContent(attributedString)
        editorContext.updateCursorPosition(1)
        editorContext.forceUpdateFormats()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // 3. 验证只有列表格式，没有标题格式
        let currentFormats = editorContext.currentFormats
        
        XCTAssertTrue(currentFormats.contains(.bulletList), "应该包含无序列表格式")
        XCTAssertFalse(currentFormats.contains(.heading1), "不应该包含大标题格式")
        XCTAssertFalse(currentFormats.contains(.heading2), "不应该包含二级标题格式")
        XCTAssertFalse(currentFormats.contains(.heading3), "不应该包含三级标题格式")
        
        print("[Test] ✓ 列表格式与标题格式互斥测试通过")
    }
    
    // MARK: - 测试：FormatState 正确处理列表格式
    
    /// 测试 FormatState.from(formats:) 正确处理列表格式
    func testFormatStateFromFormatsWithList() {
        print("\n[Test] 测试 FormatState.from(formats:) 正确处理列表格式")
        
        // 1. 测试无序列表
        var formats: Set<TextFormat> = [.bulletList]
        var state = FormatState.from(formats: formats)
        
        XCTAssertEqual(state.paragraphFormat, .bulletList, "段落格式应该是 bulletList")
        XCTAssertTrue(state.isFormatActive(.bulletList), "bulletList 应该是激活状态")
        XCTAssertFalse(state.isFormatActive(.numberedList), "numberedList 不应该是激活状态")
        
        // 2. 测试有序列表
        formats = [.numberedList]
        state = FormatState.from(formats: formats)
        
        XCTAssertEqual(state.paragraphFormat, .numberedList, "段落格式应该是 numberedList")
        XCTAssertTrue(state.isFormatActive(.numberedList), "numberedList 应该是激活状态")
        XCTAssertFalse(state.isFormatActive(.bulletList), "bulletList 不应该是激活状态")
        
        print("[Test] ✓ FormatState.from(formats:) 正确处理列表格式测试通过")
    }
    
    // MARK: - 测试：FormatState 列表格式与标题格式互斥
    
    /// 测试 FormatState 中列表格式与标题格式的互斥性
    /// 
    /// **验证**: 当格式集合同时包含列表和标题时，FormatState 应该正确处理
    func testFormatStateListHeadingMutualExclusion() {
        print("\n[Test] 测试 FormatState 列表格式与标题格式互斥")
        
        // 1. 测试无序列表（不应该包含标题格式）
        let bulletFormats: Set<TextFormat> = [.bulletList]
        let bulletState = FormatState.from(formats: bulletFormats)
        
        XCTAssertTrue(bulletState.isFormatActive(.bulletList), "bulletList 应该是激活状态")
        XCTAssertFalse(bulletState.isFormatActive(.heading1), "heading1 不应该是激活状态")
        XCTAssertFalse(bulletState.isFormatActive(.heading2), "heading2 不应该是激活状态")
        XCTAssertFalse(bulletState.isFormatActive(.heading3), "heading3 不应该是激活状态")
        
        // 2. 测试有序列表（不应该包含标题格式）
        let orderedFormats: Set<TextFormat> = [.numberedList]
        let orderedState = FormatState.from(formats: orderedFormats)
        
        XCTAssertTrue(orderedState.isFormatActive(.numberedList), "numberedList 应该是激活状态")
        XCTAssertFalse(orderedState.isFormatActive(.heading1), "heading1 不应该是激活状态")
        XCTAssertFalse(orderedState.isFormatActive(.heading2), "heading2 不应该是激活状态")
        XCTAssertFalse(orderedState.isFormatActive(.heading3), "heading3 不应该是激活状态")
        
        // 3. 测试标题格式（不应该包含列表格式）
        let headingFormats: Set<TextFormat> = [.heading1]
        let headingState = FormatState.from(formats: headingFormats)
        
        XCTAssertTrue(headingState.isFormatActive(.heading1), "heading1 应该是激活状态")
        XCTAssertFalse(headingState.isFormatActive(.bulletList), "bulletList 不应该是激活状态")
        XCTAssertFalse(headingState.isFormatActive(.numberedList), "numberedList 不应该是激活状态")
        
        print("[Test] ✓ FormatState 列表格式与标题格式互斥测试通过")
    }
}
