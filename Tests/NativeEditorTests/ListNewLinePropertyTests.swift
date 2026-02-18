//
//  ListNewLinePropertyTests.swift
//  MiNoteLibraryTests
//
//  列表换行属性测试 - 验证列表换行时的格式继承和取消功能
//  Property 6: 列表中回车正确继承格式
//  Property 7: 空列表回车正确取消格式
//
//  Feature: list-format-enhancement, Property 6: 列表中回车正确继承格式
//  Feature: list-format-enhancement, Property 7: 空列表回车正确取消格式
//
//

import AppKit
import XCTest
@testable import MiNoteLibrary

/// 列表换行属性测试
///
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证列表换行的通用正确性属性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下列表换行的一致性。
@MainActor
final class ListNewLinePropertyTests: XCTestCase {

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

    // MARK: - Property 6: 列表中回车正确继承格式

    /// 属性测试：无序列表换行继承格式
    ///
    /// **Property 6**: 对于任何有内容的无序列表行，当按下回车时，新行应该继承列表格式和缩进级别
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 应用无序列表格式
    /// 3. 模拟换行操作
    /// 4. 验证新行继承了无序列表格式
    /// 5. 验证新行继承了缩进级别
    func testProperty6_BulletListNewLineInheritsFormat() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 无序列表换行继承格式 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 30)
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText + "\n")
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: testText.count + 1))
            textStorage.setAttributedString(attributedString)

            // 3. 应用无序列表格式
            ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)

            // 验证列表格式已应用
            let listTypeBefore = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBefore, .bullet, "迭代 \(iteration): 应该是无序列表")

            // 4. 构建换行上下文
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let context = NewLineContext(
                currentLineRange: lineRange,
                currentBlockFormat: .bulletList,
                currentAlignment: .left,
                isListItemEmpty: false
            )

            // 5. 模拟换行操作 - 在行尾位置
            let cursorPosition = lineRange.location + lineRange.length - 1 // 换行符前
            textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))

            // 执行换行处理
            let handled = NewLineHandler.handleNewLine(context: context, textView: textView)

            // 6. 验证换行已处理
            XCTAssertTrue(handled, "迭代 \(iteration): 换行应该被处理")

            // 7. 验证新行继承了无序列表格式
            let newLineStart = cursorPosition + 1
            if newLineStart < textStorage.length {
                let newLineType = ListFormatHandler.detectListType(in: textStorage, at: newLineStart)
                XCTAssertEqual(newLineType, .bullet, "迭代 \(iteration): 新行应该继承无序列表格式")

                // 验证缩进级别
                let newIndent = ListFormatHandler.getListIndent(in: textStorage, at: newLineStart)
                XCTAssertEqual(newIndent, indent, "迭代 \(iteration): 新行应该继承缩进级别 \(indent)")
            }

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 无序列表换行继承测试通过")
            }
        }

        print("[PropertyTest] ✅ 无序列表换行继承格式测试完成")
    }

    /// 属性测试：有序列表换行继承格式并递增编号
    ///
    /// **Property 6**: 对于任何有内容的有序列表行，当按下回车时，新行应该继承列表格式并自动递增编号
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容和起始编号
    /// 2. 应用有序列表格式
    /// 3. 模拟换行操作
    /// 4. 验证新行继承了有序列表格式
    /// 5. 验证新行编号正确递增
    func testProperty6_OrderedListNewLineInheritsFormatAndIncrementsNumber() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 有序列表换行继承格式并递增编号 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 30)
            let startNumber = Int.random(in: 1 ... 10)
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText + "\n")
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: testText.count + 1))
            textStorage.setAttributedString(attributedString)

            // 3. 应用有序列表格式
            ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: startNumber, indent: indent)

            // 验证列表格式已应用
            let listTypeBefore = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBefore, .ordered, "迭代 \(iteration): 应该是有序列表")

            // 4. 构建换行上下文
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let context = NewLineContext(
                currentLineRange: lineRange,
                currentBlockFormat: .numberedList,
                currentAlignment: .left,
                isListItemEmpty: false
            )

            // 5. 模拟换行操作 - 在行尾位置
            let cursorPosition = lineRange.location + lineRange.length - 1 // 换行符前
            textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))

            // 执行换行处理
            let handled = NewLineHandler.handleNewLine(context: context, textView: textView)

            // 6. 验证换行已处理
            XCTAssertTrue(handled, "迭代 \(iteration): 换行应该被处理")

            // 7. 验证新行继承了有序列表格式
            let newLineStart = cursorPosition + 1
            if newLineStart < textStorage.length {
                let newLineType = ListFormatHandler.detectListType(in: textStorage, at: newLineStart)
                XCTAssertEqual(newLineType, .ordered, "迭代 \(iteration): 新行应该继承有序列表格式")

                // 验证编号递增
                let newNumber = ListFormatHandler.getListNumber(in: textStorage, at: newLineStart)
                XCTAssertEqual(newNumber, startNumber + 1, "迭代 \(iteration): 新行编号应该是 \(startNumber + 1)，实际是 \(newNumber)")

                // 验证缩进级别
                let newIndent = ListFormatHandler.getListIndent(in: textStorage, at: newLineStart)
                XCTAssertEqual(newIndent, indent, "迭代 \(iteration): 新行应该继承缩进级别 \(indent)")
            }

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 有序列表换行继承测试通过")
            }
        }

        print("[PropertyTest] ✅ 有序列表换行继承格式并递增编号测试完成")
    }

    /// 属性测试：列表换行清除内联格式
    ///
    /// **Property 6**: 对于任何列表行，当按下回车时，新行应该清除内联格式（加粗、斜体等）但保留列表格式
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 应用列表格式和内联格式
    /// 3. 模拟换行操作
    /// 4. 验证新行保留了列表格式
    /// 5. 验证新行清除了内联格式
    func testProperty6_ListNewLineClearsInlineFormats() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 列表换行清除内联格式 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 30)
            let useBullet = Bool.random()

            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText + "\n")
            let boldFont = NSFont.boldSystemFont(ofSize: 14)
            attributedString.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: testText.count))
            attributedString.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: NSRange(location: 0, length: testText.count)
            )
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))
            }

            // 4. 构建换行上下文
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let context = NewLineContext(
                currentLineRange: lineRange,
                currentBlockFormat: useBullet ? .bulletList : .numberedList,
                currentAlignment: .left,
                isListItemEmpty: false
            )

            // 5. 模拟换行操作
            let cursorPosition = lineRange.location + lineRange.length - 1
            textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))

            let handled = NewLineHandler.handleNewLine(context: context, textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 换行应该被处理")

            // 6. 验证新行的 typingAttributes
            let typingAttrs = textView.typingAttributes

            // 验证列表格式保留
            if let listType = typingAttrs[.listType] as? ListType {
                let expectedType: ListType = useBullet ? .bullet : .ordered
                XCTAssertEqual(listType, expectedType, "迭代 \(iteration): typingAttributes 应该保留列表类型")
            }

            // 验证内联格式清除 - 字体应该是普通字体，不是加粗
            if let font = typingAttrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                XCTAssertFalse(traits.contains(.bold), "迭代 \(iteration): typingAttributes 应该清除加粗格式")
            }

            // 验证下划线清除
            let underlineStyle = typingAttrs[.underlineStyle] as? Int ?? 0
            XCTAssertEqual(underlineStyle, 0, "迭代 \(iteration): typingAttributes 应该清除下划线格式")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 列表换行清除内联格式测试通过")
            }
        }

        print("[PropertyTest] ✅ 列表换行清除内联格式测试完成")
    }

    // MARK: - Property 7: 空列表回车正确取消格式

    /// 属性测试：空无序列表回车取消格式
    ///
    /// **Property 7**: 对于任何空的无序列表行，当按下回车时，列表格式应该被取消而非换行
    ///
    /// 测试策略：
    /// 1. 创建空的无序列表行
    /// 2. 模拟回车操作
    /// 3. 验证列表格式被取消
    /// 4. 验证当前行恢复为普通正文格式
    func testProperty7_EmptyBulletListEnterCancelsFormat() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空无序列表回车取消格式 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机缩进级别
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)

            // 3. 应用无序列表格式
            ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)

            // 验证列表格式已应用
            let listTypeBefore = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBefore, .bullet, "迭代 \(iteration): 应该是无序列表")

            // 验证是空列表项
            let isEmpty = ListFormatHandler.isEmptyListItem(in: textStorage, at: 0)
            XCTAssertTrue(isEmpty, "迭代 \(iteration): 应该是空列表项")

            // 4. 构建换行上下文
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let context = NewLineContext(
                currentLineRange: lineRange,
                currentBlockFormat: .bulletList,
                currentAlignment: .left,
                isListItemEmpty: true
            )

            // 5. 模拟回车操作
            textView.setSelectedRange(NSRange(location: 0, length: 0))

            let handled = NewLineHandler.handleNewLine(context: context, textView: textView)

            // 6. 验证回车已处理
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")

            // 7. 验证列表格式被取消
            let listTypeAfter = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeAfter, .none, "迭代 \(iteration): 列表格式应该被取消")

            // 8. 验证 typingAttributes 恢复为普通正文
            let typingAttrs = textView.typingAttributes
            let listType = typingAttrs[.listType] as? ListType
            XCTAssertTrue(listType == nil || listType == .none, "迭代 \(iteration): typingAttributes 不应该有列表类型")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空无序列表回车取消格式测试通过")
            }
        }

        print("[PropertyTest] ✅ 空无序列表回车取消格式测试完成")
    }

    /// 属性测试：空有序列表回车取消格式
    ///
    /// **Property 7**: 对于任何空的有序列表行，当按下回车时，列表格式应该被取消而非换行
    ///
    /// 测试策略：
    /// 1. 创建空的有序列表行
    /// 2. 模拟回车操作
    /// 3. 验证列表格式被取消
    /// 4. 验证当前行恢复为普通正文格式
    func testProperty7_EmptyOrderedListEnterCancelsFormat() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空有序列表回车取消格式 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let startNumber = Int.random(in: 1 ... 10)
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)

            // 3. 应用有序列表格式
            ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: startNumber, indent: indent)

            // 验证列表格式已应用
            let listTypeBefore = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeBefore, .ordered, "迭代 \(iteration): 应该是有序列表")

            // 验证是空列表项
            let isEmpty = ListFormatHandler.isEmptyListItem(in: textStorage, at: 0)
            XCTAssertTrue(isEmpty, "迭代 \(iteration): 应该是空列表项")

            // 4. 构建换行上下文
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let context = NewLineContext(
                currentLineRange: lineRange,
                currentBlockFormat: .numberedList,
                currentAlignment: .left,
                isListItemEmpty: true
            )

            // 5. 模拟回车操作
            textView.setSelectedRange(NSRange(location: 0, length: 0))

            let handled = NewLineHandler.handleNewLine(context: context, textView: textView)

            // 6. 验证回车已处理
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")

            // 7. 验证列表格式被取消
            let listTypeAfter = ListFormatHandler.detectListType(in: textStorage, at: 0)
            XCTAssertEqual(listTypeAfter, .none, "迭代 \(iteration): 列表格式应该被取消")

            // 8. 验证 typingAttributes 恢复为普通正文
            let typingAttrs = textView.typingAttributes
            let listType = typingAttrs[.listType] as? ListType
            XCTAssertTrue(listType == nil || listType == .none, "迭代 \(iteration): typingAttributes 不应该有列表类型")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空有序列表回车取消格式测试通过")
            }
        }

        print("[PropertyTest] ✅ 空有序列表回车取消格式测试完成")
    }

    /// 属性测试：空列表回车恢复正文格式
    ///
    /// **Property 7**: 对于任何空的列表行，当按下回车时，当前行应该恢复为普通正文格式
    ///
    /// 测试策略：
    /// 1. 创建空的列表行（随机选择有序或无序）
    /// 2. 模拟回车操作
    /// 3. 验证当前行恢复为普通正文格式
    /// 4. 验证字体大小为正文大小（14pt）
    func testProperty7_EmptyListEnterRestoresBodyFormat() {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空列表回车恢复正文格式 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 随机选择列表类型
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置空行
            let attributedString = NSMutableAttributedString(string: "\n")
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 1))
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), indent: indent)
            }

            // 4. 构建换行上下文
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let context = NewLineContext(
                currentLineRange: lineRange,
                currentBlockFormat: useBullet ? .bulletList : .numberedList,
                currentAlignment: .left,
                isListItemEmpty: true
            )

            // 5. 模拟回车操作
            textView.setSelectedRange(NSRange(location: 0, length: 0))

            let handled = NewLineHandler.handleNewLine(context: context, textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 回车应该被处理")

            // 6. 验证 typingAttributes 恢复为正文格式
            let typingAttrs = textView.typingAttributes

            // 验证字体大小
            if let font = typingAttrs[.font] as? NSFont {
                XCTAssertEqual(font.pointSize, 14, "迭代 \(iteration): 字体大小应该是 14pt")
            }

            // 验证没有列表属性
            let listType = typingAttrs[.listType] as? ListType
            XCTAssertTrue(listType == nil || listType == .none, "迭代 \(iteration): 不应该有列表类型")

            let listIndent = typingAttrs[.listIndent] as? Int
            XCTAssertNil(listIndent, "迭代 \(iteration): 不应该有列表缩进")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 空列表回车恢复正文格式测试通过")
            }
        }

        print("[PropertyTest] ✅ 空列表回车恢复正文格式测试完成")
    }

    // MARK: - 辅助方法：随机数据生成

    /// 生成随机文本
    /// - Parameters:
    ///   - minLength: 最小长度
    ///   - maxLength: 最大长度
    /// - Returns: 随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength ... maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 中文测试内容"
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }
}
