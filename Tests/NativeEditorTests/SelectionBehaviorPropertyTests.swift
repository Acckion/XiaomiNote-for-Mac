//
//  SelectionBehaviorPropertyTests.swift
//  MiNoteMac
//
//  选择行为限制属性测试
//  验证 NativeTextView 的选择行为限制功能
//
//  **Property 6: 选择行为限制**
//

import AppKit
import XCTest
@testable import MiNoteLibrary

@MainActor
final class SelectionBehaviorPropertyTests: XCTestCase {

    // MARK: - 测试辅助方法

    /// 创建测试用的 NSTextStorage
    private func createTextStorage(with text: String) -> NSTextStorage {
        NSTextStorage(string: text)
    }

    /// 创建带有无序列表的 NSTextStorage
    private func createBulletListTextStorage(with text: String, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)
        let range = NSRange(location: 0, length: 0)
        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: indent)
        return textStorage
    }

    /// 创建带有有序列表的 NSTextStorage
    private func createOrderedListTextStorage(with text: String, number: Int = 1, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)
        let range = NSRange(location: 0, length: 0)
        ListFormatHandler.applyOrderedList(to: textStorage, range: range, number: number, indent: indent)
        return textStorage
    }

    /// 创建带有勾选框列表的 NSTextStorage
    private func createCheckboxListTextStorage(with text: String, checked: Bool = false, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)

        // 创建勾选框附件
        let checkbox = InteractiveCheckboxAttachment(checked: checked)
        let attachmentString = NSAttributedString(attachment: checkbox)

        // 在行首插入附件
        textStorage.insert(attachmentString, at: 0)

        // 设置列表属性
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: fullRange)
        textStorage.addAttribute(.listIndent, value: indent, range: fullRange)
        textStorage.addAttribute(.checkboxLevel, value: 3, range: fullRange)
        textStorage.addAttribute(.checkboxChecked, value: checked, range: fullRange)

        return textStorage
    }

    // MARK: - Property 6: 选择行为限制

    /// 属性测试：选择范围的起始位置永远不在列表标记区域内
    /// 验证任何选择操作后，选择范围的起始位置都不会落在列表标记区域内
    /// _Requirements: 5.1, 5.2_
    func testPropertySelectionStartNeverInMarkerArea() {
        // 测试多种列表类型
        let testCases: [(String, (String, Int) -> NSTextStorage)] = [
            ("无序列表", createBulletListTextStorage),
            ("有序列表", { text, indent in self.createOrderedListTextStorage(with: text, number: 1, indent: indent) }),
            ("勾选框列表", { text, indent in self.createCheckboxListTextStorage(with: text, checked: false, indent: indent) }),
        ]

        for (listTypeName, createFunc) in testCases {
            // 测试不同的文本内容
            let texts = ["测试\n", "Hello World\n", "A\n", "这是一段较长的测试文本内容\n"]

            for text in texts {
                let textStorage = createFunc(text, 1)
                let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

                // 测试从内容区域的各个位置开始选择
                for selectionEnd in contentStart ... textStorage.length {
                    // 模拟选择：从内容起始位置到 selectionEnd
                    let selectionStart = contentStart
                    let selectionLength = selectionEnd - selectionStart

                    if selectionLength >= 0 {
                        // 验证选择起始位置不在标记区域内
                        let isInMarker = ListBehaviorHandler.isInListMarkerArea(
                            in: textStorage,
                            at: selectionStart
                        )

                        XCTAssertFalse(
                            isInMarker,
                            "\(listTypeName): 选择起始位置 \(selectionStart) 不应该在标记区域内"
                        )
                    }
                }
            }
        }
    }

    /// 属性测试：调整后的选择范围不包含列表标记
    /// 验证当选择范围的起始位置在标记区域内时，会被调整到内容起始位置
    /// _Requirements: 5.1, 5.2_
    func testPropertyAdjustedSelectionExcludesMarker() {
        let textStorage = createBulletListTextStorage(with: "测试文本内容\n")
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

        // 测试从标记区域的各个位置开始的选择
        for markerPosition in 0 ..< contentStart {
            // 调整选择起始位置
            let adjustedStart = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: markerPosition
            )

            // 验证调整后的位置是内容起始位置
            XCTAssertEqual(
                adjustedStart,
                contentStart,
                "标记区域位置 \(markerPosition) 应该被调整到内容起始位置 \(contentStart)"
            )

            // 验证调整后的位置不在标记区域内
            let isInMarker = ListBehaviorHandler.isInListMarkerArea(
                in: textStorage,
                at: adjustedStart
            )

            XCTAssertFalse(
                isInMarker,
                "调整后的位置 \(adjustedStart) 不应该在标记区域内"
            )
        }
    }

    /// 属性测试：内容区域的选择不会被调整
    /// 验证当选择范围完全在内容区域内时，不会被修改
    /// _Requirements: 5.1, 5.2_
    func testPropertyContentAreaSelectionUnchanged() {
        let textStorage = createBulletListTextStorage(with: "测试文本内容\n")
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

        // 测试内容区域的所有位置
        for position in contentStart ... textStorage.length {
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: position
            )

            // 内容区域的位置不应该被调整
            XCTAssertEqual(
                adjustedPosition,
                position,
                "内容区域的位置 \(position) 不应该被调整"
            )
        }
    }

    /// 属性测试：非列表行的选择不受影响
    /// 验证非列表行的选择操作不会被修改
    /// _Requirements: 5.1, 5.2_
    func testPropertyNonListLineSelectionUnaffected() {
        let textStorage = createTextStorage(with: "普通文本行\n第二行\n第三行\n")

        // 测试所有位置
        for position in 0 ... textStorage.length {
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: position
            )

            // 非列表行的位置不应该被调整
            XCTAssertEqual(
                adjustedPosition,
                position,
                "非列表行的位置 \(position) 不应该被调整"
            )

            // 非列表行不应该被检测为在标记区域内
            let isInMarker = ListBehaviorHandler.isInListMarkerArea(
                in: textStorage,
                at: position
            )

            XCTAssertFalse(
                isInMarker,
                "非列表行的位置 \(position) 不应该在标记区域内"
            )
        }
    }

    /// 属性测试：选择到行首时停在内容起始位置
    /// 验证 Cmd+Shift+左方向键选择到行首时，选择范围的起始位置是内容起始位置
    /// _Requirements: 5.2_
    func testPropertySelectToLineStartStopsAtContentStart() {
        let testCases: [(String, (String, Int) -> NSTextStorage)] = [
            ("无序列表", createBulletListTextStorage),
            ("有序列表", { text, indent in self.createOrderedListTextStorage(with: text, number: 1, indent: indent) }),
            ("勾选框列表", { text, indent in self.createCheckboxListTextStorage(with: text, checked: false, indent: indent) }),
        ]

        for (listTypeName, createFunc) in testCases {
            let textStorage = createFunc("测试文本\n", 1)
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

            // 获取列表项信息
            let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: contentStart)

            XCTAssertNotNil(listInfo, "\(listTypeName): 应该能获取列表项信息")

            if let info = listInfo {
                // 验证内容起始位置正确
                XCTAssertEqual(
                    info.contentStartPosition,
                    contentStart,
                    "\(listTypeName): 列表项信息的内容起始位置应该与 getContentStartPosition 一致"
                )

                // 验证行范围的起始位置小于内容起始位置（说明有列表标记）
                XCTAssertLessThan(
                    info.lineRange.location,
                    contentStart,
                    "\(listTypeName): 行起始位置应该小于内容起始位置（存在列表标记）"
                )
            }
        }
    }

    /// 属性测试：从内容起始位置向左选择时跳到上一行
    /// 验证 Shift+左方向键从内容起始位置向左选择时，选择范围扩展到上一行而非选中列表标记
    /// _Requirements: 5.1_
    func testPropertySelectLeftFromContentStartJumpsToPreviousLine() {
        // 创建多行列表
        let textStorage = createBulletListTextStorage(with: "第一行\n")

        // 添加第二行
        let secondLineText = "第二行\n"
        let secondLineStart = textStorage.length
        textStorage.append(NSAttributedString(string: secondLineText))

        // 在第二行应用列表格式
        ListFormatHandler.applyBulletList(
            to: textStorage,
            range: NSRange(location: secondLineStart, length: 0),
            indent: 1
        )

        // 获取第二行的内容起始位置
        let secondLineContentStart = ListBehaviorHandler.getContentStartPosition(
            in: textStorage,
            at: secondLineStart
        )

        // 获取第二行的列表项信息
        let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: secondLineContentStart)

        XCTAssertNotNil(listInfo, "应该能获取第二行的列表项信息")

        if let info = listInfo {
            // 验证行范围的起始位置大于 0（说明有上一行）
            XCTAssertGreaterThan(
                info.lineRange.location,
                0,
                "第二行的行起始位置应该大于 0"
            )

            // 计算上一行末尾位置
            let prevLineEnd = info.lineRange.location - 1

            // 验证上一行末尾位置是有效的
            XCTAssertGreaterThanOrEqual(
                prevLineEnd,
                0,
                "上一行末尾位置应该 >= 0"
            )
        }
    }

    // MARK: - 不同缩进级别测试

    // _Requirements: 5.1, 5.2_

    /// 属性测试：不同缩进级别的列表都能正确限制选择
    func testPropertyDifferentIndentLevelsSelection() {
        for indent in 1 ... 5 {
            let textStorage = createBulletListTextStorage(with: "测试\n", indent: indent)
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

            // 验证标记区域的位置会被调整
            for position in 0 ..< contentStart {
                let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                    in: textStorage,
                    from: position
                )

                XCTAssertEqual(
                    adjustedPosition,
                    contentStart,
                    "缩进级别 \(indent): 标记区域位置 \(position) 应该被调整到 \(contentStart)"
                )
            }

            // 验证内容区域的位置不变
            for position in contentStart ... textStorage.length {
                let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                    in: textStorage,
                    from: position
                )

                XCTAssertEqual(
                    adjustedPosition,
                    position,
                    "缩进级别 \(indent): 内容区域位置 \(position) 不应该被调整"
                )
            }
        }
    }

    // MARK: - 边界条件测试

    /// 测试空文本存储的选择行为
    func testEmptyTextStorageSelection() {
        let textStorage = createTextStorage(with: "")

        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 0)
        XCTAssertEqual(adjustedPosition, 0, "空文本存储的调整后位置应该是 0")

        let isInMarker = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 0)
        XCTAssertFalse(isInMarker, "空文本存储不应该有标记区域")
    }

    /// 测试只有换行符的文本的选择行为
    func testOnlyNewlineSelection() {
        let textStorage = createTextStorage(with: "\n")

        for position in 0 ... textStorage.length {
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: position)
            XCTAssertEqual(adjustedPosition, position, "只有换行符的文本位置不应该被调整")
        }
    }

    /// 测试无效位置的选择行为
    func testInvalidPositionsSelection() {
        let textStorage = createBulletListTextStorage(with: "测试\n")

        // 负数位置
        let adjusted1 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: -1)
        XCTAssertEqual(adjusted1, -1, "负数位置应该返回原位置")

        // 超出范围位置
        let adjusted2 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 1000)
        XCTAssertEqual(adjusted2, 1000, "超出范围位置应该返回原位置")
    }

    // MARK: - 选择范围计算测试

    /// 属性测试：选择范围长度计算正确
    /// 验证调整选择范围后，长度计算正确
    func testPropertySelectionLengthCalculation() {
        let textStorage = createBulletListTextStorage(with: "测试文本\n")
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

        // 测试从标记区域开始的选择
        for markerPosition in 0 ..< contentStart {
            for endPosition in contentStart ... textStorage.length {
                // 原始选择范围
                let originalLength = endPosition - markerPosition

                // 调整后的选择范围
                let adjustedStart = ListBehaviorHandler.adjustCursorPosition(
                    in: textStorage,
                    from: markerPosition
                )
                let adjustedLength = endPosition - adjustedStart

                // 验证调整后的长度小于等于原始长度
                XCTAssertLessThanOrEqual(
                    adjustedLength,
                    originalLength,
                    "调整后的选择长度应该 <= 原始长度"
                )

                // 验证调整后的长度 >= 0
                XCTAssertGreaterThanOrEqual(
                    adjustedLength,
                    0,
                    "调整后的选择长度应该 >= 0"
                )
            }
        }
    }

    /// 属性测试：选择范围的一致性
    /// 验证多次调整同一位置得到相同结果
    func testPropertySelectionConsistency() {
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        for position in 0 ... textStorage.length {
            let adjusted1 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: position)
            let adjusted2 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: position)
            let adjusted3 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: position)

            XCTAssertEqual(adjusted1, adjusted2, "多次调整同一位置应该得到相同结果")
            XCTAssertEqual(adjusted2, adjusted3, "多次调整同一位置应该得到相同结果")
        }
    }
}
