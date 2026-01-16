//
//  EmptyListEnterPropertyTests.swift
//  MiNoteLibraryTests
//
//  空列表回车属性测试 - 验证空列表项回车时取消格式的功能
//
//  **Feature: list-behavior-optimization, Property 4: 空列表回车取消格式** 
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 空列表回车属性测试
///
/// 本测试套件使用基于属性的测试方法，验证空列表项回车时的格式取消功能。
/// 每个测试运行 100 次迭代，确保在各种输入条件下空列表回车的一致性。
///
/// **Property 4: 空列表回车取消格式**
/// *For any* 空的列表项（只有列表标记没有内容），当按下回车键时，
/// 列表格式应该被取消，列表标记应该被移除，当前行应该恢复为普通正文格式。
@MainActor
final class EmptyListEnterPropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var textStorage: NSTextStorage!
    var textView: NSTextView!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500), textContainer: textContainer)
    }
    
    override func tearDown() async throws {
        textStorage = nil
        textView = nil
        try await super.tearDown()
    }
    
    // MARK: - Property 4: 空列表回车取消格式
    // **Feature: list-behavior-optimization, Property 4: 空列表回车取消格式** 
    
    /// 属性测试：空无序列表回车取消格式
    ///
    /// **Property 4**: 对于任何空的无序列表行，当按下回车时，列表格式应该被取消 
    ///
    /// 测试策略：
    /// 1. 创建空的无序列表行（随机缩进级别）
    /// 2. 验证是空列表项
    /// 3. 调用 handleEnterKey
    /// 4. 验证列表格式被取消
    /// 5. 验证列表标记被移除
    func testProperty4_EmptyBulletListEnterCancelsFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空无序列表回车取消格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机缩进级别
            let indent = Int.random(in: 1...3)
            
            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用无序列表格式
            ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            
            // 验证列表格式已应用
            let listTypeBefore = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBefore, .bullet, "迭代 \(iteration): 应该是无序列表")
            
            // 4. 验证是空列表项
            // _Requirements: 3.1_
            let isEmpty = ListBehaviorHandler.isEmptyListItem(in: textStorage, at: 0)
            XCTAssertTrue(isEmpty, "迭代 \(iteration): 应该是空列表项")
            
            // 5. 设置光标位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))
            
            // 6. 调用 handleEnterKey
            let handled = ListBehaviorHandler.handleEnterKey(textView: textView)
            
            // 7. 验证回车已处理
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")
            
            // 8. 验证列表格式被取消
            // _Requirements: 3.1_
            let listTypeAfter = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeAfter, .none, "迭代 \(iteration): 列表格式应该被取消")
            
            // 9. 验证列表标记被移除（没有附件）
            // _Requirements: 3.2_
            var hasAttachment = false
            if textStorage.length > 0 {
                let checkRange = NSRange(location: 0, length: min(1, textStorage.length))
                textStorage.enumerateAttribute(.attachment, in: checkRange, options: []) { value, _, stop in
                    if value is BulletAttachment {
                        hasAttachment = true
                        stop.pointee = true
                    }
                }
            }
            XCTAssertFalse(hasAttachment, "迭代 \(iteration): 列表标记应该被移除")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空无序列表回车取消格式测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 空无序列表回车取消格式测试完成")
    }
    
    /// 属性测试：空有序列表回车取消格式
    ///
    /// **Property 4**: 对于任何空的有序列表行，当按下回车时，列表格式应该被取消 
    ///
    /// 测试策略：
    /// 1. 创建空的有序列表行（随机编号和缩进级别）
    /// 2. 验证是空列表项
    /// 3. 调用 handleEnterKey
    /// 4. 验证列表格式被取消
    /// 5. 验证列表标记被移除
    func testProperty4_EmptyOrderedListEnterCancelsFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空有序列表回车取消格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机数据
            let startNumber = Int.random(in: 1...10)
            let indent = Int.random(in: 1...3)
            
            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用有序列表格式
            ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: startNumber, indent: indent)
            
            // 验证列表格式已应用
            let listTypeBefore = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBefore, .ordered, "迭代 \(iteration): 应该是有序列表")
            
            // 4. 验证是空列表项
            // _Requirements: 3.1_
            let isEmpty = ListBehaviorHandler.isEmptyListItem(in: textStorage, at: 0)
            XCTAssertTrue(isEmpty, "迭代 \(iteration): 应该是空列表项")
            
            // 5. 设置光标位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))
            
            // 6. 调用 handleEnterKey
            let handled = ListBehaviorHandler.handleEnterKey(textView: textView)
            
            // 7. 验证回车已处理
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")
            
            // 8. 验证列表格式被取消
            // _Requirements: 3.1_
            let listTypeAfter = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeAfter, .none, "迭代 \(iteration): 列表格式应该被取消")
            
            // 9. 验证列表标记被移除（没有附件）
            // _Requirements: 3.2_
            var hasAttachment = false
            if textStorage.length > 0 {
                let checkRange = NSRange(location: 0, length: min(1, textStorage.length))
                textStorage.enumerateAttribute(.attachment, in: checkRange, options: []) { value, _, stop in
                    if value is OrderAttachment {
                        hasAttachment = true
                        stop.pointee = true
                    }
                }
            }
            XCTAssertFalse(hasAttachment, "迭代 \(iteration): 列表标记应该被移除")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空有序列表回车取消格式测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 空有序列表回车取消格式测试完成")
    }
    
    /// 属性测试：空列表回车恢复普通正文格式
    ///
    /// **Property 4**: 对于任何空的列表行，当按下回车时，当前行应该恢复为普通正文格式 
    ///
    /// 测试策略：
    /// 1. 创建空的列表行（随机选择有序或无序）
    /// 2. 调用 handleEnterKey
    /// 3. 验证当前行恢复为普通正文格式
    /// 4. 验证 typingAttributes 为正文格式
    func testProperty4_EmptyListEnterRestoresBodyFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空列表回车恢复普通正文格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 随机选择列表类型
            let useBullet = Bool.random()
            let indent = Int.random(in: 1...3)
            
            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用列表格式
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            }
            
            // 4. 设置光标位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))
            
            // 5. 调用 handleEnterKey
            let handled = ListBehaviorHandler.handleEnterKey(textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")
            
            // 6. 验证 typingAttributes 恢复为正文格式
            // _Requirements: 3.3_
            let typingAttrs = textView.typingAttributes
            
            // 验证没有列表类型属性
            let listType = typingAttrs[.listType] as? MiNoteLibrary.ListType
            XCTAssertTrue(listType == nil || listType == MiNoteLibrary.ListType.none, "迭代 \(iteration): typingAttributes 不应该有列表类型")
            
            // 验证没有列表缩进属性
            let listIndent = typingAttrs[.listIndent] as? Int
            XCTAssertNil(listIndent, "迭代 \(iteration): typingAttributes 不应该有列表缩进")
            
            // 验证字体为正文字体
            if let font = typingAttrs[.font] as? NSFont {
                let expectedSize = FontSizeManager.shared.defaultFont.pointSize
                XCTAssertEqual(font.pointSize, expectedSize, "迭代 \(iteration): 字体大小应该是 \(expectedSize)pt")
            }
            
            // 验证段落样式无缩进
            if let paragraphStyle = typingAttrs[.paragraphStyle] as? NSParagraphStyle {
                XCTAssertEqual(paragraphStyle.firstLineHeadIndent, 0, "迭代 \(iteration): 首行缩进应该是 0")
                XCTAssertEqual(paragraphStyle.headIndent, 0, "迭代 \(iteration): 悬挂缩进应该是 0")
            }
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空列表回车恢复普通正文格式测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 空列表回车恢复普通正文格式测试完成")
    }
    
    /// 属性测试：空列表回车光标保持在当前行
    ///
    /// **Property 4**: 对于任何空的列表行，当按下回车时，光标应该保持在当前行 
    ///
    /// 测试策略：
    /// 1. 创建空的列表行
    /// 2. 记录行首位置
    /// 3. 调用 handleEnterKey
    /// 4. 验证光标位置在行首
    func testProperty4_EmptyListEnterCursorStaysOnCurrentLine() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空列表回车光标保持在当前行 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 随机选择列表类型
            let useBullet = Bool.random()
            let indent = Int.random(in: 1...3)
            
            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用列表格式
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            }
            
            // 4. 记录行首位置
            let lineStart = 0
            
            // 5. 设置光标位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))
            
            // 6. 调用 handleEnterKey
            let handled = ListBehaviorHandler.handleEnterKey(textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")
            
            // 7. 验证光标位置在行首
            // _Requirements: 3.4_
            let cursorPosition = textView.selectedRange().location
            XCTAssertEqual(cursorPosition, lineStart, "迭代 \(iteration): 光标应该在行首位置 \(lineStart)，实际位置 \(cursorPosition)")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空列表回车光标保持在当前行测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 空列表回车光标保持在当前行测试完成")
    }
    
    /// 属性测试：只有空白字符的列表项也被视为空列表项
    ///
    /// **Property 4**: 对于只有空白字符（空格、制表符）的列表项，也应该被视为空列表项 
    ///
    /// 测试策略：
    /// 1. 创建只有空白字符的列表行
    /// 2. 验证被检测为空列表项
    /// 3. 调用 handleEnterKey
    /// 4. 验证列表格式被取消
    func testProperty4_WhitespaceOnlyListItemTreatedAsEmpty() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 只有空白字符的列表项被视为空 (迭代次数: \(iterations))")
        
        // 空白字符组合
        let whitespaceOptions = [" ", "  ", "\t", " \t", "   ", "\t\t"]
        
        for iteration in 1...iterations {
            // 1. 随机选择空白字符
            let whitespace = whitespaceOptions.randomElement()!
            let useBullet = Bool.random()
            let indent = Int.random(in: 1...3)
            
            // 2. 设置带空白字符的行
            let attributedString = NSMutableAttributedString(string: whitespace + "\n")
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: whitespace.count + 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用列表格式
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            }
            
            // 4. 验证被检测为空列表项
            // _Requirements: 3.1_
            let isEmpty = ListBehaviorHandler.isEmptyListItem(in: textStorage, at: 0)
            XCTAssertTrue(isEmpty, "迭代 \(iteration): 只有空白字符的列表项应该被视为空")
            
            // 5. 设置光标位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))
            
            // 6. 调用 handleEnterKey
            let handled = ListBehaviorHandler.handleEnterKey(textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")
            
            // 7. 验证列表格式被取消
            let listTypeAfter = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeAfter, .none, "迭代 \(iteration): 列表格式应该被取消")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 只有空白字符的列表项被视为空测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 只有空白字符的列表项被视为空测试完成")
    }
    
    /// 属性测试：有内容的列表项不会被取消格式
    ///
    /// **Property 4 反向验证**: 对于有内容的列表项，回车不应该取消格式 
    ///
    /// 测试策略：
    /// 1. 创建有内容的列表行
    /// 2. 验证不是空列表项
    /// 3. 调用 handleEnterKey
    /// 4. 验证原行保留列表格式
    func testProperty4_NonEmptyListItemDoesNotCancelFormat() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 有内容的列表项不会被取消格式 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机内容
            let content = generateRandomText(minLength: 1, maxLength: 20)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1...3)
            
            // 2. 设置有内容的行
            let attributedString = NSMutableAttributedString(string: content + "\n")
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: content.count + 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用列表格式
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            }
            
            // 4. 验证不是空列表项
            let isEmpty = ListBehaviorHandler.isEmptyListItem(in: textStorage, at: 0)
            XCTAssertFalse(isEmpty, "迭代 \(iteration): 有内容的列表项不应该被视为空")
            
            // 5. 设置光标位置（在内容中间）
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            let cursorPosition = contentStart + content.count / 2
            textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))
            
            // 6. 调用 handleEnterKey
            let handled = ListBehaviorHandler.handleEnterKey(textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")
            
            // 7. 验证原行保留列表格式
            let listTypeAfter = ListFormatHandler.detectListType(in: textStorage, at: 0)
            let expectedType: MiNoteLibrary.ListType = useBullet ? .bullet : .ordered
            XCTAssertEqual(listTypeAfter, expectedType, "迭代 \(iteration): 原行应该保留列表格式")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 有内容的列表项不会被取消格式测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 有内容的列表项不会被取消格式测试完成")
    }
    
    // MARK: - 辅助方法
    
    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789中文测试"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
