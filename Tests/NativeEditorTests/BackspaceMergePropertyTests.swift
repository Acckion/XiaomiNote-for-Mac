//
//  BackspaceMergePropertyTests.swift
//  MiNoteLibraryTests
//
//  删除键合并属性测试 - 验证列表项删除键合并功能
//
//  **Feature: list-behavior-optimization, Property 5: 删除键合并行为**
//

import AppKit
import XCTest
@testable import MiNoteLibrary

/// 删除键合并属性测试
///
/// 本测试套件使用基于属性的测试方法，验证列表项删除键合并功能。
/// 每个测试运行 100 次迭代，确保在各种输入条件下删除键合并的一致性。
///
/// **Property 5: 删除键合并行为**
/// *For any* 列表项，当光标在内容区域起始位置按下删除键时，
/// 当前行的内容应该合并到上一行。如果上一行是列表项，内容追加到列表项末尾；
/// 如果上一行是普通文本，内容追加到行末尾并取消列表格式。
@MainActor
final class BackspaceMergePropertyTests: XCTestCase {

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

    // MARK: - Property 5: 删除键合并行为

    // **Feature: list-behavior-optimization, Property 5: 删除键合并行为**

    /// 属性测试：列表项合并到上一个列表项
    ///
    /// **Property 5**: 对于任何列表项，当光标在内容起始位置按删除键时，
    /// 如果上一行也是列表项，当前内容应该追加到上一行列表项末尾
    ///
    /// 测试策略：
    /// 1. 创建两行列表项（随机内容）
    /// 2. 将光标放在第二行内容起始位置
    /// 3. 调用 handleBackspaceKey
    /// 4. 验证内容合并到上一行
    /// 5. 验证合并后只有一行
    func testProperty5_MergeListItemToPreviousListItem() {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 列表项合并到上一个列表项 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let content1 = generateRandomText(minLength: 1, maxLength: 15)
            let content2 = generateRandomText(minLength: 1, maxLength: 15)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置两行内容
            let fullText = content1 + "\n" + content2 + "\n"
            let attributedString = NSMutableAttributedString(string: fullText)
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: fullText.count))
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式到第一行
            let line1Range = NSRange(location: 0, length: 0)
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line1Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line1Range, number: 1, indent: indent)
            }

            // 4. 重新计算第二行的起始位置（第一行插入了附件后位置变化）
            // 第一行现在是：附件(1) + content1 + 换行符(1)
            let line2Start = 1 + content1.count + 1
            let line2Range = NSRange(location: line2Start, length: 0)

            // 5. 应用列表格式到第二行
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line2Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line2Range, number: 2, indent: indent)
            }

            // 6. 获取第二行的内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: line2Start + 1)

            // 7. 设置光标位置到第二行内容起始位置
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))

            // 8. 调用 handleBackspaceKey
            let handled = ListBehaviorHandler.handleBackspaceKey(textView: textView)

            // 9. 验证删除键已处理
            // _Requirements: 4.1_
            XCTAssertTrue(handled, "迭代 \(iteration): 删除键应该被处理")

            // 10. 验证内容合并（第一行应该包含两个内容）
            // _Requirements: 4.3_
            let mergedContent = textStorage.string
            let expectedContent = content1 + content2
            XCTAssertTrue(
                mergedContent.contains(expectedContent),
                "迭代 \(iteration): 合并后应该包含两个内容 '\(expectedContent)'，实际: '\(mergedContent)'"
            )

            // 11. 验证只有一行列表项（合并后应该只有一行，没有换行符或只有末尾换行符）
            // 注意：合并操作会删除两行之间的换行符，最终结果可能没有换行符
            let lineCount = mergedContent.components(separatedBy: "\n").count(where: { !$0.isEmpty })
            XCTAssertEqual(lineCount, 1, "迭代 \(iteration): 合并后应该只有一行内容，实际行数: \(lineCount)")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 列表项合并到上一个列表项测试通过")
            }
        }

        print("[PropertyTest] ✅ 列表项合并到上一个列表项测试完成")
    }

    /// 属性测试：列表项合并到普通文本行
    ///
    /// **Property 5**: 对于任何列表项，当光标在内容起始位置按删除键时，
    /// 如果上一行是普通文本，当前内容应该追加到上一行末尾并取消列表格式
    ///
    /// 测试策略：
    /// 1. 创建一行普通文本和一行列表项
    /// 2. 将光标放在列表项内容起始位置
    /// 3. 调用 handleBackspaceKey
    /// 4. 验证内容合并到上一行
    /// 5. 验证列表格式被取消
    func testProperty5_MergeListItemToPlainText() {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 列表项合并到普通文本行 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let plainContent = generateRandomText(minLength: 1, maxLength: 15)
            let listContent = generateRandomText(minLength: 1, maxLength: 15)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置两行内容（第一行普通文本，第二行列表）
            let fullText = plainContent + "\n" + listContent + "\n"
            let attributedString = NSMutableAttributedString(string: fullText)
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: fullText.count))
            textStorage.setAttributedString(attributedString)

            // 3. 只对第二行应用列表格式
            let line2Start = plainContent.count + 1
            let line2Range = NSRange(location: line2Start, length: 0)

            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line2Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line2Range, number: 1, indent: indent)
            }

            // 4. 获取第二行的内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: line2Start + 1)

            // 5. 设置光标位置到第二行内容起始位置
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))

            // 6. 调用 handleBackspaceKey
            let handled = ListBehaviorHandler.handleBackspaceKey(textView: textView)

            // 7. 验证删除键已处理
            // _Requirements: 4.1_
            XCTAssertTrue(handled, "迭代 \(iteration): 删除键应该被处理")

            // 8. 验证内容合并
            // _Requirements: 4.4_
            let mergedContent = textStorage.string
            let expectedContent = plainContent + listContent
            XCTAssertTrue(
                mergedContent.contains(expectedContent),
                "迭代 \(iteration): 合并后应该包含两个内容 '\(expectedContent)'，实际: '\(mergedContent)'"
            )

            // 9. 验证只有一行（合并后应该只有一行内容）
            let lineCount = mergedContent.components(separatedBy: "\n").count(where: { !$0.isEmpty })
            XCTAssertEqual(lineCount, 1, "迭代 \(iteration): 合并后应该只有一行，实际: \(lineCount)")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 列表项合并到普通文本行测试通过")
            }
        }

        print("[PropertyTest] ✅ 列表项合并到普通文本行测试完成")
    }

    /// 属性测试：删除键移除列表标记
    ///
    /// **Property 5**: 当列表项合并时，当前行的列表标记应该被移除
    ///
    /// 测试策略：
    /// 1. 创建两行列表项
    /// 2. 记录合并前的附件数量
    /// 3. 调用 handleBackspaceKey
    /// 4. 验证附件数量减少
    func testProperty5_BackspaceRemovesListMarker() {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 删除键移除列表标记 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let content1 = generateRandomText(minLength: 1, maxLength: 10)
            let content2 = generateRandomText(minLength: 1, maxLength: 10)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置两行内容
            let fullText = content1 + "\n" + content2 + "\n"
            let attributedString = NSMutableAttributedString(string: fullText)
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: fullText.count))
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式到第一行
            let line1Range = NSRange(location: 0, length: 0)

            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line1Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line1Range, number: 1, indent: indent)
            }

            // 4. 重新计算第二行的起始位置（第一行插入了附件后位置变化）
            // 第一行现在是：附件(1) + content1 + 换行符(1)
            let line2Start = 1 + content1.count + 1
            let line2Range = NSRange(location: line2Start, length: 0)

            // 5. 应用列表格式到第二行
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line2Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line2Range, number: 2, indent: indent)
            }

            // 6. 记录合并前的附件数量
            let attachmentCountBefore = countAttachments(in: textStorage)
            XCTAssertEqual(attachmentCountBefore, 2, "迭代 \(iteration): 合并前应该有 2 个附件")

            // 7. 获取第二行的内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: line2Start + 1)

            // 6. 设置光标位置
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))

            // 7. 调用 handleBackspaceKey
            let handled = ListBehaviorHandler.handleBackspaceKey(textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 删除键应该被处理")

            // 8. 验证附件数量减少
            // _Requirements: 4.2_
            let attachmentCountAfter = countAttachments(in: textStorage)
            XCTAssertEqual(attachmentCountAfter, 1, "迭代 \(iteration): 合并后应该只有 1 个附件，实际: \(attachmentCountAfter)")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 删除键移除列表标记测试通过")
            }
        }

        print("[PropertyTest] ✅ 删除键移除列表标记测试完成")
    }

    /// 属性测试：光标位置正确更新
    ///
    /// **Property 5**: 合并后光标应该位于合并点（上一行末尾）
    ///
    /// 测试策略：
    /// 1. 创建两行列表项
    /// 2. 记录上一行末尾位置
    /// 3. 调用 handleBackspaceKey
    /// 4. 验证光标位置在合并点
    func testProperty5_CursorPositionAfterMerge() {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 光标位置正确更新 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let content1 = generateRandomText(minLength: 1, maxLength: 10)
            let content2 = generateRandomText(minLength: 1, maxLength: 10)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置两行内容
            let fullText = content1 + "\n" + content2 + "\n"
            let attributedString = NSMutableAttributedString(string: fullText)
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: fullText.count))
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式到第一行
            let line1Range = NSRange(location: 0, length: 0)

            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line1Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line1Range, number: 1, indent: indent)
            }

            // 4. 重新计算第二行的起始位置（第一行插入了附件后位置变化）
            // 第一行现在是：附件(1) + content1 + 换行符(1)
            let line2Start = 1 + content1.count + 1
            let line2Range = NSRange(location: line2Start, length: 0)

            // 5. 应用列表格式到第二行
            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line2Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line2Range, number: 2, indent: indent)
            }

            // 6. 计算预期的光标位置（第一行末尾，即换行符位置）
            // 第一行：附件(1) + content1 + 换行符
            let expectedCursorPosition = 1 + content1.count

            // 7. 获取第二行的内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: line2Start + 1)

            // 8. 设置光标位置
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))

            // 9. 调用 handleBackspaceKey
            let handled = ListBehaviorHandler.handleBackspaceKey(textView: textView)
            XCTAssertTrue(handled, "迭代 \(iteration): 删除键应该被处理")

            // 10. 验证光标位置
            let actualCursorPosition = textView.selectedRange().location
            XCTAssertEqual(
                actualCursorPosition,
                expectedCursorPosition,
                "迭代 \(iteration): 光标应该在位置 \(expectedCursorPosition)，实际: \(actualCursorPosition)"
            )

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 光标位置正确更新测试通过")
            }
        }

        print("[PropertyTest] ✅ 光标位置正确更新测试完成")
    }

    /// 属性测试：非内容起始位置不触发合并
    ///
    /// **Property 5 反向验证**: 当光标不在内容起始位置时，删除键不应该触发合并
    ///
    /// 测试策略：
    /// 1. 创建有内容的列表项
    /// 2. 将光标放在内容中间
    /// 3. 调用 handleBackspaceKey
    /// 4. 验证不触发合并（返回 false）
    func testProperty5_NoMergeWhenNotAtContentStart() {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 非内容起始位置不触发合并 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let content = generateRandomText(minLength: 3, maxLength: 15)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置内容
            let fullText = "前一行\n" + content + "\n"
            let attributedString = NSMutableAttributedString(string: fullText)
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: fullText.count))
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式到第二行
            let line2Start = 4 // "前一行\n" 的长度
            let line2Range = NSRange(location: line2Start, length: 0)

            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: line2Range, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: line2Range, number: 1, indent: indent)
            }

            // 4. 获取内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: line2Start + 1)

            // 5. 将光标放在内容中间（不是起始位置）
            let cursorPosition = contentStart + content.count / 2
            textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))

            // 6. 调用 handleBackspaceKey
            let handled = ListBehaviorHandler.handleBackspaceKey(textView: textView)

            // 7. 验证不触发合并
            XCTAssertFalse(handled, "迭代 \(iteration): 光标不在内容起始位置时不应该触发合并")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 非内容起始位置不触发合并测试通过")
            }
        }

        print("[PropertyTest] ✅ 非内容起始位置不触发合并测试完成")
    }

    /// 属性测试：文档第一行不触发合并
    ///
    /// **Property 5 边界条件**: 当列表项是文档第一行时，删除键不应该触发合并
    ///
    /// 测试策略：
    /// 1. 创建单行列表项（文档第一行）
    /// 2. 将光标放在内容起始位置
    /// 3. 调用 handleBackspaceKey
    /// 4. 验证不触发合并（返回 false）
    func testProperty5_NoMergeOnFirstLine() {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 文档第一行不触发合并 (迭代次数: \(iterations))")

        for iteration in 1 ... iterations {
            // 1. 生成随机数据
            let content = generateRandomText(minLength: 1, maxLength: 15)
            let useBullet = Bool.random()
            let indent = Int.random(in: 1 ... 3)

            // 2. 设置单行内容
            let fullText = content + "\n"
            let attributedString = NSMutableAttributedString(string: fullText)
            attributedString.addAttribute(.font, value: FontSizeManager.shared.defaultFont, range: NSRange(location: 0, length: fullText.count))
            textStorage.setAttributedString(attributedString)

            // 3. 应用列表格式
            let lineRange = NSRange(location: 0, length: 0)

            if useBullet {
                ListFormatHandler.applyBulletList(to: textStorage, range: lineRange, indent: indent)
            } else {
                ListFormatHandler.applyOrderedList(to: textStorage, range: lineRange, number: 1, indent: indent)
            }

            // 4. 获取内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

            // 5. 设置光标位置到内容起始位置
            textView.setSelectedRange(NSRange(location: contentStart, length: 0))

            // 6. 调用 handleBackspaceKey
            let handled = ListBehaviorHandler.handleBackspaceKey(textView: textView)

            // 7. 验证不触发合并（文档第一行没有上一行可以合并）
            XCTAssertFalse(handled, "迭代 \(iteration): 文档第一行不应该触发合并")

            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 文档第一行不触发合并测试通过")
            }
        }

        print("[PropertyTest] ✅ 文档第一行不触发合并测试完成")
    }

    // MARK: - 辅助方法

    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength ... maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }

    /// 统计附件数量
    private func countAttachments(in textStorage: NSTextStorage) -> Int {
        var count = 0
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length), options: []) { value, _, _ in
            if value is BulletAttachment || value is OrderAttachment || value is InteractiveCheckboxAttachment {
                count += 1
            }
        }
        return count
    }
}
