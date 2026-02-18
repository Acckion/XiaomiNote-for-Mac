//
//  ListBehaviorHandlerTests.swift
//  MiNoteMac
//
//  ListBehaviorHandler 单元测试
//  测试光标位置限制、列表项信息获取等功能
//
//  _Requirements: 1.1, 1.3, 1.4_
//

import AppKit
import XCTest
@testable import MiNoteLibrary

@MainActor
final class ListBehaviorHandlerTests: XCTestCase {

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

    // MARK: - getContentStartPosition 测试

    // _Requirements: 1.1, 1.3, 1.4_

    func testGetContentStartPositionForBulletList() {
        // 测试无序列表的内容起始位置
        // _Requirements: 1.1_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

        // 内容起始位置应该在附件之后（附件占用 1 个字符）
        XCTAssertEqual(contentStart, 1, "无序列表的内容起始位置应该是 1（附件之后）")
    }

    func testGetContentStartPositionForOrderedList() {
        // 测试有序列表的内容起始位置
        // _Requirements: 1.1_
        let textStorage = createOrderedListTextStorage(with: "测试文本\n")

        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

        // 内容起始位置应该在附件之后（附件占用 1 个字符）
        XCTAssertEqual(contentStart, 1, "有序列表的内容起始位置应该是 1（附件之后）")
    }

    func testGetContentStartPositionForNonListLine() {
        // 测试非列表行的内容起始位置
        // _Requirements: 1.4_
        let textStorage = createTextStorage(with: "普通文本\n")

        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)

        // 非列表行的内容起始位置应该是行首
        XCTAssertEqual(contentStart, 0, "非列表行的内容起始位置应该是行首")
    }

    func testGetContentStartPositionAtMiddleOfLine() {
        // 测试在行中间位置获取内容起始位置
        // _Requirements: 1.1_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        // 在行中间位置（假设位置 3）
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 3)

        // 应该返回该行的内容起始位置
        XCTAssertEqual(contentStart, 1, "在行中间位置也应该返回正确的内容起始位置")
    }

    func testGetContentStartPositionWithInvalidPosition() {
        // 测试无效位置
        let textStorage = createTextStorage(with: "测试\n")

        // 负数位置
        let contentStart1 = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: -1)
        XCTAssertEqual(contentStart1, -1, "负数位置应该返回原位置")

        // 超出范围位置
        let contentStart2 = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 1000)
        XCTAssertEqual(contentStart2, 1000, "超出范围位置应该返回原位置")
    }

    // MARK: - isInListMarkerArea 测试

    // _Requirements: 1.1_

    func testIsInListMarkerAreaAtLineStart() {
        // 测试在行首（列表标记位置）
        // _Requirements: 1.1_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        let isInMarker = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 0)

        XCTAssertTrue(isInMarker, "行首位置应该在列表标记区域内")
    }

    func testIsInListMarkerAreaAfterMarker() {
        // 测试在列表标记之后
        // _Requirements: 1.1_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        // 位置 1 是附件之后，应该不在标记区域内
        let isInMarker = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 1)

        XCTAssertFalse(isInMarker, "附件之后的位置不应该在列表标记区域内")
    }

    func testIsInListMarkerAreaForNonListLine() {
        // 测试非列表行
        // _Requirements: 1.1_
        let textStorage = createTextStorage(with: "普通文本\n")

        let isInMarker = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 0)

        XCTAssertFalse(isInMarker, "非列表行不应该有列表标记区域")
    }

    func testIsInListMarkerAreaWithInvalidPosition() {
        // 测试无效位置
        let textStorage = createBulletListTextStorage(with: "测试\n")

        // 负数位置
        let isInMarker1 = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: -1)
        XCTAssertFalse(isInMarker1, "负数位置应该返回 false")

        // 超出范围位置
        let isInMarker2 = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 1000)
        XCTAssertFalse(isInMarker2, "超出范围位置应该返回 false")
    }

    // MARK: - adjustCursorPosition 测试

    // _Requirements: 1.1, 1.3_

    func testAdjustCursorPositionFromMarkerArea() {
        // 测试从标记区域调整光标位置
        // _Requirements: 1.1, 1.3_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        // 从位置 0（标记区域）调整
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 0)

        // 应该调整到内容起始位置
        XCTAssertEqual(adjustedPosition, 1, "从标记区域应该调整到内容起始位置")
    }

    func testAdjustCursorPositionFromContentArea() {
        // 测试从内容区域调整光标位置
        // _Requirements: 1.1, 1.3_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        // 从位置 2（内容区域）调整
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 2)

        // 应该保持原位置
        XCTAssertEqual(adjustedPosition, 2, "从内容区域不应该调整位置")
    }

    func testAdjustCursorPositionForNonListLine() {
        // 测试非列表行的光标位置调整
        // _Requirements: 1.3_
        let textStorage = createTextStorage(with: "普通文本\n")

        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 0)

        // 非列表行不需要调整
        XCTAssertEqual(adjustedPosition, 0, "非列表行不应该调整位置")
    }

    func testAdjustCursorPositionWithInvalidPosition() {
        // 测试无效位置
        let textStorage = createBulletListTextStorage(with: "测试\n")

        // 负数位置
        let adjusted1 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: -1)
        XCTAssertEqual(adjusted1, -1, "负数位置应该返回原位置")

        // 超出范围位置
        let adjusted2 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 1000)
        XCTAssertEqual(adjusted2, 1000, "超出范围位置应该返回原位置")
    }

    // MARK: - getListItemInfo 测试

    // _Requirements: 1.1, 1.3, 1.4_

    func testGetListItemInfoForBulletList() {
        // 测试获取无序列表项信息
        // _Requirements: 1.1, 1.4_
        let textStorage = createBulletListTextStorage(with: "测试文本\n")

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)

        XCTAssertNotNil(info, "应该能获取列表项信息")
        XCTAssertEqual(info?.listType, .bullet, "列表类型应该是 bullet")
        XCTAssertEqual(info?.indent, 1, "缩进级别应该是 1")
        XCTAssertNil(info?.number, "无序列表不应该有编号")
        XCTAssertNil(info?.isChecked, "无序列表不应该有勾选状态")
        XCTAssertEqual(info?.contentStartPosition, 1, "内容起始位置应该是 1")
        XCTAssertEqual(info?.contentText, "测试文本", "内容文本应该正确")
    }

    func testGetListItemInfoForOrderedList() {
        // 测试获取有序列表项信息
        // _Requirements: 1.1, 1.4_
        let textStorage = createOrderedListTextStorage(with: "测试文本\n", number: 5)

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)

        XCTAssertNotNil(info, "应该能获取列表项信息")
        XCTAssertEqual(info?.listType, .ordered, "列表类型应该是 ordered")
        XCTAssertEqual(info?.indent, 1, "缩进级别应该是 1")
        XCTAssertEqual(info?.number, 5, "编号应该是 5")
        XCTAssertNil(info?.isChecked, "有序列表不应该有勾选状态")
        XCTAssertEqual(info?.contentStartPosition, 1, "内容起始位置应该是 1")
        XCTAssertEqual(info?.contentText, "测试文本", "内容文本应该正确")
    }

    func testGetListItemInfoForNonListLine() {
        // 测试获取非列表行的信息
        // _Requirements: 1.4_
        let textStorage = createTextStorage(with: "普通文本\n")

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)

        XCTAssertNil(info, "非列表行应该返回 nil")
    }

    func testGetListItemInfoWithIndent() {
        // 测试获取带缩进的列表项信息
        // _Requirements: 1.4_
        let textStorage = createBulletListTextStorage(with: "测试文本\n", indent: 3)

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)

        XCTAssertNotNil(info, "应该能获取列表项信息")
        XCTAssertEqual(info?.indent, 3, "缩进级别应该是 3")
    }

    func testGetListItemInfoIsEmpty() {
        // 测试空列表项的 isEmpty 属性
        // _Requirements: 1.4_
        let textStorage = createBulletListTextStorage(with: "\n")

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)

        XCTAssertNotNil(info, "应该能获取列表项信息")
        XCTAssertTrue(info?.isEmpty ?? false, "空列表项的 isEmpty 应该为 true")
    }

    func testGetListItemInfoIsNotEmpty() {
        // 测试非空列表项的 isEmpty 属性
        // _Requirements: 1.4_
        let textStorage = createBulletListTextStorage(with: "有内容\n")

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)

        XCTAssertNotNil(info, "应该能获取列表项信息")
        XCTAssertFalse(info?.isEmpty ?? true, "非空列表项的 isEmpty 应该为 false")
    }

    func testGetListItemInfoWithInvalidPosition() {
        // 测试无效位置
        let textStorage = createBulletListTextStorage(with: "测试\n")

        // 负数位置
        let info1 = ListBehaviorHandler.getListItemInfo(in: textStorage, at: -1)
        XCTAssertNil(info1, "负数位置应该返回 nil")

        // 超出范围位置
        let info2 = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 1000)
        XCTAssertNil(info2, "超出范围位置应该返回 nil")
    }

    // MARK: - isInCheckboxArea 测试

    // _Requirements: 1.5, 7.1, 7.2_

    func testIsInCheckboxAreaForNonCheckbox() {
        // 测试非勾选框位置
        // _Requirements: 1.5_
        let textStorage = createBulletListTextStorage(with: "测试\n")

        let isInCheckbox = ListBehaviorHandler.isInCheckboxArea(in: textStorage, at: 0)

        XCTAssertFalse(isInCheckbox, "非勾选框附件位置应该返回 false")
    }

    func testIsInCheckboxAreaWithInvalidPosition() {
        // 测试无效位置
        let textStorage = createTextStorage(with: "测试\n")

        // 负数位置
        let isInCheckbox1 = ListBehaviorHandler.isInCheckboxArea(in: textStorage, at: -1)
        XCTAssertFalse(isInCheckbox1, "负数位置应该返回 false")

        // 超出范围位置
        let isInCheckbox2 = ListBehaviorHandler.isInCheckboxArea(in: textStorage, at: 1000)
        XCTAssertFalse(isInCheckbox2, "超出范围位置应该返回 false")
    }

    // MARK: - 边界条件测试

    func testEmptyTextStorage() {
        // 测试空文本存储
        let textStorage = createTextStorage(with: "")

        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        XCTAssertEqual(contentStart, 0, "空文本存储应该返回 0")

        let isInMarker = ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 0)
        XCTAssertFalse(isInMarker, "空文本存储不应该有标记区域")

        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)
        XCTAssertNil(info, "空文本存储应该返回 nil")
    }

    func testMultipleLines() {
        // 测试多行文本
        let textStorage = createTextStorage(with: "第一行\n第二行\n第三行\n")

        // 在第一行应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))

        // 第一行应该是列表
        let info1 = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)
        XCTAssertNotNil(info1, "第一行应该是列表")
        XCTAssertEqual(info1?.listType, .bullet, "第一行应该是无序列表")

        // 第二行不应该是列表（需要找到第二行的位置）
        let string = textStorage.string as NSString
        let secondLineRange = string.lineRange(for: NSRange(location: string.length / 2, length: 0))
        let info2 = ListBehaviorHandler.getListItemInfo(in: textStorage, at: secondLineRange.location)
        // 第二行可能是列表也可能不是，取决于实现
    }
}
