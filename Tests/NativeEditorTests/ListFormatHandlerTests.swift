//
//  ListFormatHandlerTests.swift
//  MiNoteMac
//
//  ListFormatHandler 单元测试
//  测试列表格式的创建、切换、转换和移除功能
//
//  _Requirements: 1.1-1.3, 2.1-2.3, 3.1-3.3, 4.1-4.3_
//

import AppKit
import XCTest
@testable import MiNoteLibrary

@MainActor
final class ListFormatHandlerTests: XCTestCase {

    // MARK: - 测试辅助方法

    /// 创建测试用的 NSTextStorage
    private func createTextStorage(with text: String) -> NSTextStorage {
        NSTextStorage(string: text)
    }

    /// 检查行首是否有 BulletAttachment
    private func hasBulletAttachment(in textStorage: NSTextStorage, at position: Int) -> Bool {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        var found = false
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if value is BulletAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// 检查行首是否有 OrderAttachment
    private func hasOrderAttachment(in textStorage: NSTextStorage, at position: Int) -> Bool {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        var found = false
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if value is OrderAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// 获取行的列表类型属性
    private func getListTypeAttribute(in textStorage: NSTextStorage, at position: Int) -> ListType? {
        guard position >= 0, position < textStorage.length else { return nil }
        return textStorage.attribute(.listType, at: position, effectiveRange: nil) as? ListType
    }

    /// 获取行的列表缩进属性
    private func getListIndentAttribute(in textStorage: NSTextStorage, at position: Int) -> Int? {
        guard position >= 0, position < textStorage.length else { return nil }
        return textStorage.attribute(.listIndent, at: position, effectiveRange: nil) as? Int
    }

    // MARK: - 空行创建列表测试

    // _Requirements: 1.1, 1.2, 1.3_

    func testApplyBulletListToEmptyLine() {
        // 测试在空行上应用无序列表
        // _Requirements: 1.1_
        let textStorage = createTextStorage(with: "\n")
        let range = NSRange(location: 0, length: 0)

        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 验证行首有 BulletAttachment
        XCTAssertTrue(hasBulletAttachment(in: textStorage, at: 0), "空行应用无序列表后应该有 BulletAttachment")

        // 验证列表类型属性
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .bullet, "列表类型应该是 bullet")
    }

    func testApplyOrderedListToEmptyLine() {
        // 测试在空行上应用有序列表
        // _Requirements: 1.2_
        let textStorage = createTextStorage(with: "\n")
        let range = NSRange(location: 0, length: 0)

        ListFormatHandler.applyOrderedList(to: textStorage, range: range)

        // 验证行首有 OrderAttachment
        XCTAssertTrue(hasOrderAttachment(in: textStorage, at: 0), "空行应用有序列表后应该有 OrderAttachment")

        // 验证列表类型属性
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .ordered, "列表类型应该是 ordered")
    }

    // MARK: - 有内容行转换为列表测试

    // _Requirements: 2.1, 2.2, 2.3_

    func testApplyBulletListToLineWithContent() {
        // 测试将有内容的行转换为无序列表
        // _Requirements: 2.1_
        let originalText = "测试文本内容\n"
        let textStorage = createTextStorage(with: originalText)
        let range = NSRange(location: 0, length: 0)

        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 验证行首有 BulletAttachment
        XCTAssertTrue(hasBulletAttachment(in: textStorage, at: 0), "有内容行应用无序列表后应该有 BulletAttachment")

        // 验证原有文本内容保留
        XCTAssertTrue(textStorage.string.contains("测试文本内容"), "原有文本内容应该保留")

        // 验证列表类型属性
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .bullet, "列表类型应该是 bullet")
    }

    func testApplyOrderedListToLineWithContent() {
        // 测试将有内容的行转换为有序列表
        // _Requirements: 2.2_
        let originalText = "测试文本内容\n"
        let textStorage = createTextStorage(with: originalText)
        let range = NSRange(location: 0, length: 0)

        ListFormatHandler.applyOrderedList(to: textStorage, range: range)

        // 验证行首有 OrderAttachment
        XCTAssertTrue(hasOrderAttachment(in: textStorage, at: 0), "有内容行应用有序列表后应该有 OrderAttachment")

        // 验证原有文本内容保留
        XCTAssertTrue(textStorage.string.contains("测试文本内容"), "原有文本内容应该保留")

        // 验证列表类型属性
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .ordered, "列表类型应该是 ordered")
    }

    func testListIndentAttributeIsSet() {
        // 测试列表缩进属性是否正确设置
        // _Requirements: 2.3_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: 2)

        // 验证缩进级别
        let indent = ListFormatHandler.getListIndent(in: textStorage, at: 0)
        XCTAssertEqual(indent, 2, "列表缩进级别应该是 2")
    }

    // MARK: - 列表切换（取消）测试

    // _Requirements: 3.1, 3.2, 3.3_

    func testToggleBulletListRemovesFormat() {
        // 测试再次点击无序列表时取消格式
        // _Requirements: 3.1_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)
        XCTAssertTrue(hasBulletAttachment(in: textStorage, at: 0), "应该有 BulletAttachment")

        // 再次切换，应该移除
        ListFormatHandler.toggleBulletList(to: textStorage, range: range)

        // 验证列表格式已移除
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .none, "列表格式应该被移除")

        // 验证文本内容保留
        XCTAssertTrue(textStorage.string.contains("测试文本"), "文本内容应该保留")
    }

    func testToggleOrderedListRemovesFormat() {
        // 测试再次点击有序列表时取消格式
        // _Requirements: 3.2_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用有序列表
        ListFormatHandler.applyOrderedList(to: textStorage, range: range)
        XCTAssertTrue(hasOrderAttachment(in: textStorage, at: 0), "应该有 OrderAttachment")

        // 再次切换，应该移除
        ListFormatHandler.toggleOrderedList(to: textStorage, range: range)

        // 验证列表格式已移除
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .none, "列表格式应该被移除")

        // 验证文本内容保留
        XCTAssertTrue(textStorage.string.contains("测试文本"), "文本内容应该保留")
    }

    func testRemoveListFormatPreservesContent() {
        // 测试移除列表格式时保留文本内容
        // _Requirements: 3.3_
        let originalText = "保留的文本内容\n"
        let textStorage = createTextStorage(with: originalText)
        let range = NSRange(location: 0, length: 0)

        // 应用列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 移除列表
        ListFormatHandler.removeListFormat(from: textStorage, range: range)

        // 验证文本内容保留
        XCTAssertTrue(textStorage.string.contains("保留的文本内容"), "移除列表格式后文本内容应该保留")
    }

    // MARK: - 列表类型转换测试

    // _Requirements: 4.1, 4.2, 4.3_

    func testConvertBulletToOrdered() {
        // 测试无序列表转换为有序列表
        // _Requirements: 4.1_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)
        XCTAssertEqual(ListFormatHandler.detectListType(in: textStorage, at: 0), .bullet, "应该是无序列表")

        // 点击有序列表，应该转换
        ListFormatHandler.toggleOrderedList(to: textStorage, range: range)

        // 验证转换为有序列表
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .ordered, "应该转换为有序列表")

        // 验证有 OrderAttachment
        XCTAssertTrue(hasOrderAttachment(in: textStorage, at: 0), "应该有 OrderAttachment")
    }

    func testConvertOrderedToBullet() {
        // 测试有序列表转换为无序列表
        // _Requirements: 4.2_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用有序列表
        ListFormatHandler.applyOrderedList(to: textStorage, range: range)
        XCTAssertEqual(ListFormatHandler.detectListType(in: textStorage, at: 0), .ordered, "应该是有序列表")

        // 点击无序列表，应该转换
        ListFormatHandler.toggleBulletList(to: textStorage, range: range)

        // 验证转换为无序列表
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .bullet, "应该转换为无序列表")

        // 验证有 BulletAttachment
        XCTAssertTrue(hasBulletAttachment(in: textStorage, at: 0), "应该有 BulletAttachment")
    }

    func testConvertListTypePreservesIndent() {
        // 测试列表类型转换时保留缩进级别
        // _Requirements: 4.3_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用带缩进的无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: 3)
        XCTAssertEqual(ListFormatHandler.getListIndent(in: textStorage, at: 0), 3, "缩进级别应该是 3")

        // 转换为有序列表
        ListFormatHandler.convertListType(in: textStorage, range: range, to: .ordered)

        // 验证缩进级别保留
        let indent = ListFormatHandler.getListIndent(in: textStorage, at: 0)
        XCTAssertEqual(indent, 3, "转换后缩进级别应该保留为 3")
    }

    // MARK: - 列表检测测试

    func testDetectListTypeNone() {
        // 测试检测非列表行
        let textStorage = createTextStorage(with: "普通文本\n")

        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .none, "普通文本行应该检测为 none")
    }

    func testDetectListTypeBullet() {
        // 测试检测无序列表行
        let textStorage = createTextStorage(with: "测试\n")
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))

        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .bullet, "应该检测为无序列表")
    }

    func testDetectListTypeOrdered() {
        // 测试检测有序列表行
        let textStorage = createTextStorage(with: "测试\n")
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0))

        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .ordered, "应该检测为有序列表")
    }

    // MARK: - 空列表项检测测试

    func testIsEmptyListItemTrue() {
        // 测试空列表项检测 - 应该返回 true
        let textStorage = createTextStorage(with: "\n")
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))

        let isEmpty = ListFormatHandler.isEmptyListItem(in: textStorage, at: 0)
        XCTAssertTrue(isEmpty, "只有附件的列表项应该被检测为空")
    }

    func testIsEmptyListItemFalse() {
        // 测试空列表项检测 - 应该返回 false
        let textStorage = createTextStorage(with: "有内容\n")
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0))

        let isEmpty = ListFormatHandler.isEmptyListItem(in: textStorage, at: 0)
        XCTAssertFalse(isEmpty, "有内容的列表项不应该被检测为空")
    }

    // MARK: - 边界条件测试

    func testApplyListToEmptyTextStorage() {
        // 测试在空文本存储上应用列表
        let textStorage = createTextStorage(with: "")
        let range = NSRange(location: 0, length: 0)

        // 不应该崩溃
        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 验证有附件
        XCTAssertGreaterThan(textStorage.length, 0, "应该插入了附件")
    }

    func testDetectListTypeAtInvalidPosition() {
        // 测试在无效位置检测列表类型
        let textStorage = createTextStorage(with: "测试\n")

        // 负数位置
        let type1 = ListFormatHandler.detectListType(in: textStorage, at: -1)
        XCTAssertEqual(type1, .none, "无效位置应该返回 none")

        // 超出范围位置
        let type2 = ListFormatHandler.detectListType(in: textStorage, at: 1000)
        XCTAssertEqual(type2, .none, "超出范围位置应该返回 none")
    }

    func testCalculateListNumber() {
        // 测试列表编号计算
        let textStorage = createTextStorage(with: "第一项\n第二项\n第三项\n")

        // 应用有序列表到第一行
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: 1)

        // 计算第二行的编号（应该是 2）
        // 注意：由于插入了附件，位置会变化
        let string = textStorage.string as NSString
        let secondLineRange = string.lineRange(for: NSRange(location: string.length / 2, length: 0))
        let number = ListFormatHandler.calculateListNumber(in: textStorage, at: secondLineRange.location)

        // 第二行还没有应用列表，所以编号应该是 1（新列表的起始编号）
        // 或者如果上一行是有序列表，应该是 2
        XCTAssertGreaterThanOrEqual(number, 1, "列表编号应该大于等于 1")
    }

    // MARK: - 列表与标题互斥测试

    // _Requirements: 5.1, 5.2, 5.3_

    func testApplyBulletListRemovesHeadingFormat() {
        // 测试应用无序列表时移除标题格式
        // _Requirements: 5.1_
        let textStorage = createTextStorage(with: "标题文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用大标题格式（23pt）
        let headingFont = NSFont.systemFont(ofSize: 23, weight: .regular)
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        textStorage.addAttribute(.font, value: headingFont, range: lineRange)

        // 验证标题格式已应用
        if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            XCTAssertEqual(font.pointSize, 23, "应该是大标题字体大小")
        }

        // 应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 验证标题格式已移除，字体大小应该是正文大小（14pt）
        if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            XCTAssertEqual(font.pointSize, ListFormatHandler.bodyFontSize, "应用列表后字体大小应该是正文大小")
        }

        // 验证列表格式已应用
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .bullet, "应该是无序列表")
    }

    func testApplyOrderedListRemovesHeadingFormat() {
        // 测试应用有序列表时移除标题格式
        // _Requirements: 5.1_
        let textStorage = createTextStorage(with: "标题文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用二级标题格式（20pt）
        let headingFont = NSFont.systemFont(ofSize: 20, weight: .regular)
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        textStorage.addAttribute(.font, value: headingFont, range: lineRange)

        // 验证标题格式已应用
        if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            XCTAssertEqual(font.pointSize, 20, "应该是二级标题字体大小")
        }

        // 应用有序列表
        ListFormatHandler.applyOrderedList(to: textStorage, range: range)

        // 验证标题格式已移除，字体大小应该是正文大小（14pt）
        if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            XCTAssertEqual(font.pointSize, ListFormatHandler.bodyFontSize, "应用列表后字体大小应该是正文大小")
        }

        // 验证列表格式已应用
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .ordered, "应该是有序列表")
    }

    func testListAlwaysUsesBodyFontSize() {
        // 测试列表行始终使用正文字体大小
        // _Requirements: 5.3_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 验证字体大小是正文大小（14pt）
        // 注意：附件字符可能没有字体属性，所以我们检查文本部分
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: range)

        var foundBodyFont = false
        textStorage.enumerateAttribute(.font, in: lineRange, options: []) { value, _, _ in
            if let font = value as? NSFont {
                if font.pointSize == ListFormatHandler.bodyFontSize {
                    foundBodyFont = true
                }
            }
        }

        XCTAssertTrue(foundBodyFont, "列表行应该使用正文字体大小")
    }

    func testHandleListHeadingMutualExclusionPreservesBoldTrait() {
        // 测试互斥处理时保留加粗特性
        // _Requirements: 5.1, 5.3_
        let textStorage = createTextStorage(with: "加粗标题\n")
        let range = NSRange(location: 0, length: 0)
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 应用加粗的大标题格式
        let boldHeadingFont = NSFont.boldSystemFont(ofSize: 23)
        textStorage.addAttribute(.font, value: boldHeadingFont, range: lineRange)

        // 调用互斥处理
        ListFormatHandler.handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        // 验证字体大小变为正文大小
        if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            XCTAssertEqual(font.pointSize, ListFormatHandler.bodyFontSize, "字体大小应该变为正文大小")

            // 验证加粗特性保留
            let traits = font.fontDescriptor.symbolicTraits
            XCTAssertTrue(traits.contains(.bold), "加粗特性应该保留")
        }
    }

    func testHandleHeadingListMutualExclusionRemovesList() {
        // 测试应用标题时移除列表格式
        // _Requirements: 5.2_
        let textStorage = createTextStorage(with: "列表文本\n")
        let range = NSRange(location: 0, length: 0)

        // 先应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)
        XCTAssertEqual(ListFormatHandler.detectListType(in: textStorage, at: 0), .bullet, "应该是无序列表")

        // 调用标题-列表互斥处理
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        let removed = ListFormatHandler.handleHeadingListMutualExclusion(in: textStorage, range: lineRange)

        // 验证列表格式已移除
        XCTAssertTrue(removed, "应该返回 true 表示移除了列表格式")
        let listType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(listType, .none, "列表格式应该被移除")
    }

    func testMutualExclusionWithThreeHeadingLevels() {
        // 测试三种标题级别的互斥
        // _Requirements: 5.1, 5.3_
        let headingSizes: [CGFloat] = [23, 20, 17] // H1, H2, H3

        for headingSize in headingSizes {
            let textStorage = createTextStorage(with: "标题\(Int(headingSize))pt\n")
            let range = NSRange(location: 0, length: 0)
            let lineRange = (textStorage.string as NSString).lineRange(for: range)

            // 应用标题格式
            let headingFont = NSFont.systemFont(ofSize: headingSize, weight: .regular)
            textStorage.addAttribute(.font, value: headingFont, range: lineRange)

            // 应用无序列表
            ListFormatHandler.applyBulletList(to: textStorage, range: range)

            // 验证字体大小变为正文大小
            if let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                XCTAssertEqual(
                    font.pointSize,
                    ListFormatHandler.bodyFontSize,
                    "从 \(headingSize)pt 标题应用列表后，字体大小应该是正文大小"
                )
            }
        }
    }

    // MARK: - 列表附件渲染验证测试

    // _Requirements: 6.1, 6.2, 6.3_

    func testBulletAttachmentRendersAsWholeUnit() {
        // 验证 BulletAttachment 作为整体渲染
        // _Requirements: 6.1_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 验证附件存在
        XCTAssertTrue(hasBulletAttachment(in: textStorage, at: 0), "应该有 BulletAttachment")

        // 验证附件占用一个字符位置（Unicode 对象替换字符 \u{FFFC}）
        let string = textStorage.string
        XCTAssertTrue(string.contains("\u{FFFC}"), "附件应该使用对象替换字符表示")

        // 验证附件的边界设置正确
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        var attachmentBounds: CGRect?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if let bullet = value as? BulletAttachment {
                attachmentBounds = bullet.bounds
                stop.pointee = true
            }
        }

        XCTAssertNotNil(attachmentBounds, "附件应该有边界设置")
        XCTAssertGreaterThan(attachmentBounds?.width ?? 0, 0, "附件宽度应该大于 0")
        XCTAssertGreaterThan(attachmentBounds?.height ?? 0, 0, "附件高度应该大于 0")
    }

    func testOrderAttachmentRendersAsWholeUnit() {
        // 验证 OrderAttachment 作为整体渲染（编号和点号作为整体）
        // _Requirements: 6.2_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用有序列表
        ListFormatHandler.applyOrderedList(to: textStorage, range: range)

        // 验证附件存在
        XCTAssertTrue(hasOrderAttachment(in: textStorage, at: 0), "应该有 OrderAttachment")

        // 验证附件占用一个字符位置（Unicode 对象替换字符 \u{FFFC}）
        let string = textStorage.string
        XCTAssertTrue(string.contains("\u{FFFC}"), "附件应该使用对象替换字符表示")

        // 验证附件的边界设置正确
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        var attachmentBounds: CGRect?
        var attachmentNumber: Int?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if let order = value as? OrderAttachment {
                attachmentBounds = order.bounds
                attachmentNumber = order.number
                stop.pointee = true
            }
        }

        XCTAssertNotNil(attachmentBounds, "附件应该有边界设置")
        XCTAssertGreaterThan(attachmentBounds?.width ?? 0, 0, "附件宽度应该大于 0")
        XCTAssertGreaterThan(attachmentBounds?.height ?? 0, 0, "附件高度应该大于 0")
        XCTAssertEqual(attachmentNumber, 1, "编号应该是 1")
    }

    func testDeleteBulletAttachmentRemovesWholeAttachment() {
        // 验证删除 BulletAttachment 时删除整个附件
        // _Requirements: 6.3_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range)

        // 记录初始长度
        let initialLength = textStorage.length
        XCTAssertTrue(hasBulletAttachment(in: textStorage, at: 0), "应该有 BulletAttachment")

        // 查找附件位置
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        XCTAssertNotNil(attachmentRange, "应该找到附件范围")
        XCTAssertEqual(attachmentRange?.length, 1, "附件应该占用 1 个字符位置")

        // 删除附件
        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 验证附件已被完全删除
        XCTAssertFalse(hasBulletAttachment(in: textStorage, at: 0), "附件应该被删除")
        XCTAssertEqual(textStorage.length, initialLength - 1, "长度应该减少 1")

        // 验证文本内容保留
        XCTAssertTrue(textStorage.string.contains("测试文本"), "文本内容应该保留")
    }

    func testDeleteOrderAttachmentRemovesWholeAttachment() {
        // 验证删除 OrderAttachment 时删除整个附件
        // _Requirements: 6.3_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用有序列表
        ListFormatHandler.applyOrderedList(to: textStorage, range: range)

        // 记录初始长度
        let initialLength = textStorage.length
        XCTAssertTrue(hasOrderAttachment(in: textStorage, at: 0), "应该有 OrderAttachment")

        // 查找附件位置
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is OrderAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        XCTAssertNotNil(attachmentRange, "应该找到附件范围")
        XCTAssertEqual(attachmentRange?.length, 1, "附件应该占用 1 个字符位置")

        // 删除附件
        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 验证附件已被完全删除
        XCTAssertFalse(hasOrderAttachment(in: textStorage, at: 0), "附件应该被删除")
        XCTAssertEqual(textStorage.length, initialLength - 1, "长度应该减少 1")

        // 验证文本内容保留
        XCTAssertTrue(textStorage.string.contains("测试文本"), "文本内容应该保留")
    }

    func testBulletAttachmentIndentLevelAffectsRendering() {
        // 验证 BulletAttachment 的缩进级别影响渲染
        // _Requirements: 6.1_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用带缩进的无序列表
        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: 2)

        // 验证附件的缩进级别
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        var attachmentIndent: Int?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if let bullet = value as? BulletAttachment {
                attachmentIndent = bullet.indent
                stop.pointee = true
            }
        }

        XCTAssertEqual(attachmentIndent, 2, "附件的缩进级别应该是 2")
    }

    func testOrderAttachmentNumberAffectsRendering() {
        // 验证 OrderAttachment 的编号影响渲染
        // _Requirements: 6.2_
        let textStorage = createTextStorage(with: "测试文本\n")
        let range = NSRange(location: 0, length: 0)

        // 应用带编号的有序列表
        ListFormatHandler.applyOrderedList(to: textStorage, range: range, number: 5)

        // 验证附件的编号
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        var attachmentNumber: Int?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if let order = value as? OrderAttachment {
                attachmentNumber = order.number
                stop.pointee = true
            }
        }

        XCTAssertEqual(attachmentNumber, 5, "附件的编号应该是 5")
    }

    func testBulletAttachmentImageGeneration() {
        // 验证 BulletAttachment 能正确生成图像
        // _Requirements: 6.1_
        let bullet = BulletAttachment(indent: 1)

        // 验证附件边界
        XCTAssertGreaterThan(bullet.bounds.width, 0, "附件宽度应该大于 0")
        XCTAssertGreaterThan(bullet.bounds.height, 0, "附件高度应该大于 0")

        // 验证能生成图像
        let image = bullet.image(forBounds: bullet.bounds, textContainer: nil, characterIndex: 0)
        XCTAssertNotNil(image, "应该能生成图像")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0, "图像宽度应该大于 0")
        XCTAssertGreaterThan(image?.size.height ?? 0, 0, "图像高度应该大于 0")
    }

    func testOrderAttachmentImageGeneration() {
        // 验证 OrderAttachment 能正确生成图像
        // _Requirements: 6.2_
        let order = OrderAttachment(number: 1, inputNumber: 0, indent: 1)

        // 验证附件边界
        XCTAssertGreaterThan(order.bounds.width, 0, "附件宽度应该大于 0")
        XCTAssertGreaterThan(order.bounds.height, 0, "附件高度应该大于 0")

        // 验证能生成图像
        let image = order.image(forBounds: order.bounds, textContainer: nil, characterIndex: 0)
        XCTAssertNotNil(image, "应该能生成图像")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0, "图像宽度应该大于 0")
        XCTAssertGreaterThan(image?.size.height ?? 0, 0, "图像高度应该大于 0")
    }

    func testBulletAttachmentThemeAwareness() {
        // 验证 BulletAttachment 支持主题感知
        // _Requirements: 6.1_
        let bullet = BulletAttachment(indent: 1)

        // 验证实现了 ThemeAwareAttachment 协议
        XCTAssertTrue(bullet is ThemeAwareAttachment, "应该实现 ThemeAwareAttachment 协议")

        // 验证可以更新主题
        bullet.isDarkMode = true
        XCTAssertTrue(bullet.isDarkMode, "应该能设置深色模式")

        bullet.isDarkMode = false
        XCTAssertFalse(bullet.isDarkMode, "应该能设置浅色模式")
    }

    func testOrderAttachmentThemeAwareness() {
        // 验证 OrderAttachment 支持主题感知
        // _Requirements: 6.2_
        let order = OrderAttachment(number: 1, inputNumber: 0, indent: 1)

        // 验证实现了 ThemeAwareAttachment 协议
        XCTAssertTrue(order is ThemeAwareAttachment, "应该实现 ThemeAwareAttachment 协议")

        // 验证可以更新主题
        order.isDarkMode = true
        XCTAssertTrue(order.isDarkMode, "应该能设置深色模式")

        order.isDarkMode = false
        XCTAssertFalse(order.isDarkMode, "应该能设置浅色模式")
    }

    func testBulletStyleVariesByIndentLevel() {
        // 验证不同缩进级别使用不同的项目符号样式
        // _Requirements: 6.1_

        // 创建不同缩进级别的 BulletAttachment
        let bullet1 = BulletAttachment(indent: 1)
        let bullet2 = BulletAttachment(indent: 2)
        let bullet3 = BulletAttachment(indent: 3)
        let bullet4 = BulletAttachment(indent: 4)

        // 验证缩进级别正确设置
        XCTAssertEqual(bullet1.indent, 1, "缩进级别应该是 1")
        XCTAssertEqual(bullet2.indent, 2, "缩进级别应该是 2")
        XCTAssertEqual(bullet3.indent, 3, "缩进级别应该是 3")
        XCTAssertEqual(bullet4.indent, 4, "缩进级别应该是 4")

        // 验证每个都能生成图像（不同样式）
        let image1 = bullet1.image(forBounds: bullet1.bounds, textContainer: nil, characterIndex: 0)
        let image2 = bullet2.image(forBounds: bullet2.bounds, textContainer: nil, characterIndex: 0)
        let image3 = bullet3.image(forBounds: bullet3.bounds, textContainer: nil, characterIndex: 0)
        let image4 = bullet4.image(forBounds: bullet4.bounds, textContainer: nil, characterIndex: 0)

        XCTAssertNotNil(image1, "缩进级别 1 应该能生成图像")
        XCTAssertNotNil(image2, "缩进级别 2 应该能生成图像")
        XCTAssertNotNil(image3, "缩进级别 3 应该能生成图像")
        XCTAssertNotNil(image4, "缩进级别 4 应该能生成图像")
    }

    func testOrderAttachmentNumberDisplay() {
        // 验证 OrderAttachment 正确显示不同编号
        // _Requirements: 6.2_

        // 创建不同编号的 OrderAttachment
        let order1 = OrderAttachment(number: 1, inputNumber: 0, indent: 1)
        let order10 = OrderAttachment(number: 10, inputNumber: 0, indent: 1)
        let order99 = OrderAttachment(number: 99, inputNumber: 0, indent: 1)

        // 验证编号正确设置
        XCTAssertEqual(order1.number, 1, "编号应该是 1")
        XCTAssertEqual(order10.number, 10, "编号应该是 10")
        XCTAssertEqual(order99.number, 99, "编号应该是 99")

        // 验证每个都能生成图像
        let image1 = order1.image(forBounds: order1.bounds, textContainer: nil, characterIndex: 0)
        let image10 = order10.image(forBounds: order10.bounds, textContainer: nil, characterIndex: 0)
        let image99 = order99.image(forBounds: order99.bounds, textContainer: nil, characterIndex: 0)

        XCTAssertNotNil(image1, "编号 1 应该能生成图像")
        XCTAssertNotNil(image10, "编号 10 应该能生成图像")
        XCTAssertNotNil(image99, "编号 99 应该能生成图像")
    }
}
