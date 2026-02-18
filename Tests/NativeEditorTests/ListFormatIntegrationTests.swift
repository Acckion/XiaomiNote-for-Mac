//
//  ListFormatIntegrationTests.swift
//  MiNoteMac
//
//  列表格式端到端集成测试
//  测试创建列表 → 编辑内容 → 保存 → 重新加载 → 验证内容
//  测试菜单状态同步
//
//  _Requirements: 9.1-9.4, 10.1-10.5, 11.1-11.3_
//

import XCTest
@testable import MiNoteLibrary

/// 列表格式端到端集成测试
@MainActor
final class ListFormatIntegrationTests: XCTestCase {

    // MARK: - Properties

    var textStorage: NSTextStorage!
    var converter: XiaoMiFormatConverter!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        textStorage = NSTextStorage()
        converter = XiaoMiFormatConverter.shared
    }

    override func tearDown() async throws {
        textStorage = nil
        converter = nil
        try await super.tearDown()
    }

    // MARK: - 无序列表端到端测试

    /// 测试无序列表的完整流程：创建 → 编辑 → 保存 → 重新加载 → 验证
    /// _Requirements: 9.1, 9.4, 10.1, 10.4_
    func testBulletListEndToEnd() throws {
        // 1. 创建无序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: 1)

        // 2. 编辑内容
        let insertPosition = textStorage.length
        textStorage.append(NSAttributedString(string: "第一项"))

        // 验证创建成功
        XCTAssertTrue(textStorage.string.contains("\u{FFFC}"), "应该包含附件字符")
        XCTAssertTrue(textStorage.string.contains("第一项"), "应该包含文本内容")

        // 验证附件类型
        var foundBullet = false
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if value is BulletAttachment {
                foundBullet = true
            }
        }
        XCTAssertTrue(foundBullet, "应该找到 BulletAttachment")

        // 3. 保存为 XML
        let xml = try converter.nsAttributedStringToXML(textStorage)

        // 验证 XML 格式
        XCTAssertTrue(xml.contains("<bullet indent=\"1\" />"), "XML 应该包含无序列表标签")
        XCTAssertTrue(xml.contains("第一项"), "XML 应该包含文本内容")
        XCTAssertFalse(xml.contains("<text>"), "XML 不应该使用 <text> 标签包裹列表内容")

        // 4. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(xml)

        // 5. 验证内容一致性
        XCTAssertTrue(reloadedTextStorage.string.contains("第一项"), "重新加载后应该包含文本内容")

        // 验证附件类型
        var reloadedFoundBullet = false
        reloadedTextStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedTextStorage.length)) { value, _, _ in
            if let bullet = value as? BulletAttachment {
                reloadedFoundBullet = true
                XCTAssertEqual(bullet.indent, 1, "缩进级别应该正确")
            }
        }
        XCTAssertTrue(reloadedFoundBullet, "重新加载后应该找到 BulletAttachment")
    }

    /// 测试多项无序列表的端到端流程
    /// _Requirements: 9.1, 9.4, 10.1, 10.4_
    func testMultipleBulletListItemsEndToEnd() throws {
        // 1. 创建第一项
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "第一项\n"))

        // 2. 创建第二项
        let secondItemStart = textStorage.length
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: secondItemStart, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "第二项\n"))

        // 3. 创建第三项
        let thirdItemStart = textStorage.length
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: thirdItemStart, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "第三项"))

        // 4. 保存为 XML
        let xml = try converter.nsAttributedStringToXML(textStorage)

        // 验证 XML 包含所有项
        let bulletCount = xml.components(separatedBy: "<bullet indent=\"1\" />").count - 1
        XCTAssertEqual(bulletCount, 3, "XML 应该包含 3 个无序列表项")
        XCTAssertTrue(xml.contains("第一项"), "XML 应该包含第一项")
        XCTAssertTrue(xml.contains("第二项"), "XML 应该包含第二项")
        XCTAssertTrue(xml.contains("第三项"), "XML 应该包含第三项")

        // 5. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(xml)

        // 6. 验证所有项都正确加载
        XCTAssertTrue(reloadedTextStorage.string.contains("第一项"), "应该包含第一项")
        XCTAssertTrue(reloadedTextStorage.string.contains("第二项"), "应该包含第二项")
        XCTAssertTrue(reloadedTextStorage.string.contains("第三项"), "应该包含第三项")

        // 验证附件数量
        var bulletCount2 = 0
        reloadedTextStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedTextStorage.length)) { value, _, _ in
            if value is BulletAttachment {
                bulletCount2 += 1
            }
        }
        XCTAssertEqual(bulletCount2, 3, "应该有 3 个 BulletAttachment")
    }

    // MARK: - 有序列表端到端测试

    /// 测试有序列表的完整流程：创建 → 编辑 → 保存 → 重新加载 → 验证
    /// _Requirements: 9.2, 9.3, 9.4, 10.2, 10.3, 10.4_
    func testOrderedListEndToEnd() throws {
        // 1. 创建有序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: 1, indent: 1)

        // 2. 编辑内容
        textStorage.append(NSAttributedString(string: "第一项"))

        // 验证创建成功
        XCTAssertTrue(textStorage.string.contains("\u{FFFC}"), "应该包含附件字符")
        XCTAssertTrue(textStorage.string.contains("第一项"), "应该包含文本内容")

        // 验证附件类型和编号
        var foundOrder = false
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if let order = value as? OrderAttachment {
                foundOrder = true
                XCTAssertEqual(order.number, 1, "编号应该是 1")
            }
        }
        XCTAssertTrue(foundOrder, "应该找到 OrderAttachment")

        // 3. 保存为 XML
        let xml = try converter.nsAttributedStringToXML(textStorage)

        // 验证 XML 格式
        XCTAssertTrue(xml.contains("<order indent=\"1\" inputNumber=\"0\" />"), "XML 应该包含有序列表标签")
        XCTAssertTrue(xml.contains("第一项"), "XML 应该包含文本内容")

        // 4. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(xml)

        // 5. 验证内容一致性
        XCTAssertTrue(reloadedTextStorage.string.contains("第一项"), "重新加载后应该包含文本内容")

        // 验证附件类型和编号
        var reloadedFoundOrder = false
        reloadedTextStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedTextStorage.length)) { value, _, _ in
            if let order = value as? OrderAttachment {
                reloadedFoundOrder = true
                XCTAssertEqual(order.number, 1, "编号应该是 1")
                XCTAssertEqual(order.indent, 1, "缩进级别应该正确")
            }
        }
        XCTAssertTrue(reloadedFoundOrder, "重新加载后应该找到 OrderAttachment")
    }

    /// 测试连续有序列表的端到端流程（验证 inputNumber 规则）
    /// _Requirements: 9.2, 9.3, 9.4, 10.2, 10.3, 10.4_
    func testConsecutiveOrderedListEndToEnd() throws {
        // 1. 创建第一项（编号 1）
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: 1, indent: 1)
        textStorage.append(NSAttributedString(string: "第一项\n"))

        // 2. 创建第二项（编号 2）
        let secondItemStart = textStorage.length
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: secondItemStart, length: 0), number: 2, indent: 1)
        textStorage.append(NSAttributedString(string: "第二项\n"))

        // 3. 创建第三项（编号 3）
        let thirdItemStart = textStorage.length
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: thirdItemStart, length: 0), number: 3, indent: 1)
        textStorage.append(NSAttributedString(string: "第三项"))

        // 4. 保存为 XML
        let xml = try converter.nsAttributedStringToXML(textStorage)

        // 验证 inputNumber 规则：第一项为 0（1-1），后续项为 0（连续）
        XCTAssertTrue(xml.contains("<order indent=\"1\" inputNumber=\"0\" />"), "第一项的 inputNumber 应该是 0")

        // 验证所有项都是 inputNumber="0"（连续编号）
        let inputNumberMatches = xml.components(separatedBy: "inputNumber=\"0\"").count - 1
        XCTAssertEqual(inputNumberMatches, 3, "所有连续有序列表项的 inputNumber 都应该是 0")

        // 5. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(xml)

        // 6. 验证编号正确递增
        var numbers: [Int] = []
        reloadedTextStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedTextStorage.length)) { value, _, _ in
            if let order = value as? OrderAttachment {
                numbers.append(order.number)
            }
        }
        XCTAssertEqual(numbers, [1, 2, 3], "编号应该正确递增")
    }

    // MARK: - 列表类型转换端到端测试

    /// 测试列表类型转换的端到端流程
    /// _Requirements: 9.1, 9.2, 10.1, 10.2_
    func testListTypeConversionEndToEnd() throws {
        // 1. 创建无序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "原本是无序列表"))

        // 2. 保存为 XML
        let bulletXML = try converter.nsAttributedStringToXML(textStorage)
        XCTAssertTrue(bulletXML.contains("<bullet indent=\"1\" />"), "应该是无序列表")

        // 3. 转换为有序列表
        ListFormatHandler.convertListType(in: textStorage, range: NSRange(location: 0, length: textStorage.length), to: .ordered)

        // 4. 保存为 XML
        let orderedXML = try converter.nsAttributedStringToXML(textStorage)
        XCTAssertTrue(orderedXML.contains("<order indent=\"1\" inputNumber=\"0\" />"), "应该转换为有序列表")
        XCTAssertTrue(orderedXML.contains("原本是无序列表"), "文本内容应该保留")

        // 5. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(orderedXML)

        // 6. 验证转换成功
        var foundOrder = false
        reloadedTextStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedTextStorage.length)) { value, _, _ in
            if value is OrderAttachment {
                foundOrder = true
            }
        }
        XCTAssertTrue(foundOrder, "重新加载后应该是有序列表")
        XCTAssertTrue(reloadedTextStorage.string.contains("原本是无序列表"), "文本内容应该保留")
    }

    // MARK: - 列表内联格式端到端测试

    /// 测试列表中的内联格式（加粗、斜体等）的端到端流程
    /// _Requirements: 10.5_
    func testListWithInlineFormatsEndToEnd() throws {
        // 1. 创建无序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: 1)

        // 2. 添加带格式的文本
        let boldText = NSMutableAttributedString(string: "加粗文本")
        let boldFont = NSFont.boldSystemFont(ofSize: 14)
        boldText.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: boldText.length))
        textStorage.append(boldText)

        textStorage.append(NSAttributedString(string: " "))

        let italicText = NSMutableAttributedString(string: "斜体文本")
        italicText.addAttribute(.obliqueness, value: 0.2, range: NSRange(location: 0, length: italicText.length))
        textStorage.append(italicText)

        // 3. 保存为 XML
        let xml = try converter.nsAttributedStringToXML(textStorage)

        // 验证 XML 包含格式标签
        XCTAssertTrue(xml.contains("<bullet indent=\"1\" />"), "应该包含无序列表标签")
        XCTAssertTrue(xml.contains("<b>"), "应该包含加粗标签")
        XCTAssertTrue(xml.contains("<i>"), "应该包含斜体标签")

        // 4. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(xml)

        // 5. 验证格式保留
        var hasBold = false
        var hasItalic = false

        reloadedTextStorage.enumerateAttributes(in: NSRange(location: 0, length: reloadedTextStorage.length)) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    hasBold = true
                }
            }
            if let obliqueness = attrs[.obliqueness] as? Double, obliqueness > 0 {
                hasItalic = true
            }
        }

        XCTAssertTrue(hasBold, "重新加载后应该保留加粗格式")
        XCTAssertTrue(hasItalic, "重新加载后应该保留斜体格式")
    }

    // MARK: - 菜单状态同步测试

    /// 测试菜单状态同步：光标移动到列表行时，菜单状态应该更新
    /// _Requirements: 11.1, 11.2, 11.3_
    func testMenuStateSyncWithBulletList() {
        // 1. 创建无序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "无序列表项\n"))

        // 2. 添加普通文本
        textStorage.append(NSAttributedString(string: "普通文本"))

        // 3. 检测无序列表行的格式
        let bulletListType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(bulletListType, .bullet, "第一行应该检测为无序列表")

        // 4. 检测普通文本行的格式
        let normalLineType = ListFormatHandler.detectListType(in: textStorage, at: textStorage.length - 1)
        XCTAssertEqual(normalLineType, .none, "最后一行应该检测为非列表")
    }

    /// 测试菜单状态同步：光标移动到有序列表行时，菜单状态应该更新
    /// _Requirements: 11.1, 11.2, 11.3_
    func testMenuStateSyncWithOrderedList() {
        // 1. 创建有序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: 1, indent: 1)
        textStorage.append(NSAttributedString(string: "有序列表项\n"))

        // 2. 添加普通文本
        textStorage.append(NSAttributedString(string: "普通文本"))

        // 3. 检测有序列表行的格式
        let orderedListType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(orderedListType, .ordered, "第一行应该检测为有序列表")

        // 4. 检测普通文本行的格式
        let normalLineType = ListFormatHandler.detectListType(in: textStorage, at: textStorage.length - 1)
        XCTAssertEqual(normalLineType, .none, "最后一行应该检测为非列表")
    }

    /// 测试菜单状态同步：在不同列表类型之间切换
    /// _Requirements: 11.1, 11.2, 11.3_
    func testMenuStateSyncBetweenListTypes() {
        // 1. 创建无序列表
        textStorage.append(NSAttributedString(string: ""))
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: 0, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "列表项\n"))

        // 2. 创建有序列表
        let secondItemStart = textStorage.length
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: secondItemStart, length: 0), number: 1, indent: 1)
        textStorage.append(NSAttributedString(string: "有序列表项"))

        // 3. 检测第一行（无序列表）
        let firstLineType = ListFormatHandler.detectListType(in: textStorage, at: 0)
        XCTAssertEqual(firstLineType, .bullet, "第一行应该是无序列表")

        // 4. 检测第二行（有序列表）
        let secondLineType = ListFormatHandler.detectListType(in: textStorage, at: secondItemStart + 1)
        XCTAssertEqual(secondLineType, .ordered, "第二行应该是有序列表")
    }

    // MARK: - 复杂场景端到端测试

    /// 测试混合列表和普通文本的端到端流程
    /// _Requirements: 9.1-9.4, 10.1-10.5_
    func testMixedListAndTextEndToEnd() throws {
        // 1. 创建混合内容
        // 普通文本
        textStorage.append(NSAttributedString(string: "标题文本\n"))

        // 无序列表
        let bulletStart = textStorage.length
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: bulletStart, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "无序项 1\n"))

        let bulletStart2 = textStorage.length
        ListFormatHandler.applyBulletList(to: textStorage, range: NSRange(location: bulletStart2, length: 0), indent: 1)
        textStorage.append(NSAttributedString(string: "无序项 2\n"))

        // 普通文本
        textStorage.append(NSAttributedString(string: "中间文本\n"))

        // 有序列表
        let orderStart = textStorage.length
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: orderStart, length: 0), number: 1, indent: 1)
        textStorage.append(NSAttributedString(string: "有序项 1\n"))

        let orderStart2 = textStorage.length
        ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: orderStart2, length: 0), number: 2, indent: 1)
        textStorage.append(NSAttributedString(string: "有序项 2"))

        // 2. 保存为 XML
        let xml = try converter.nsAttributedStringToXML(textStorage)

        // 验证 XML 结构
        XCTAssertTrue(xml.contains("标题文本"), "应该包含标题文本")
        XCTAssertTrue(xml.contains("<bullet indent=\"1\" />"), "应该包含无序列表")
        XCTAssertTrue(xml.contains("中间文本"), "应该包含中间文本")
        XCTAssertTrue(xml.contains("<order indent=\"1\" inputNumber=\"0\" />"), "应该包含有序列表")

        // 3. 重新加载
        let reloadedTextStorage = try converter.xmlToNSAttributedString(xml)

        // 4. 验证所有内容都正确加载
        XCTAssertTrue(reloadedTextStorage.string.contains("标题文本"), "应该包含标题文本")
        XCTAssertTrue(reloadedTextStorage.string.contains("无序项 1"), "应该包含无序项 1")
        XCTAssertTrue(reloadedTextStorage.string.contains("无序项 2"), "应该包含无序项 2")
        XCTAssertTrue(reloadedTextStorage.string.contains("中间文本"), "应该包含中间文本")
        XCTAssertTrue(reloadedTextStorage.string.contains("有序项 1"), "应该包含有序项 1")
        XCTAssertTrue(reloadedTextStorage.string.contains("有序项 2"), "应该包含有序项 2")

        // 验证列表附件数量
        var bulletCount = 0
        var orderCount = 0
        reloadedTextStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedTextStorage.length)) { value, _, _ in
            if value is BulletAttachment {
                bulletCount += 1
            } else if value is OrderAttachment {
                orderCount += 1
            }
        }
        XCTAssertEqual(bulletCount, 2, "应该有 2 个无序列表项")
        XCTAssertEqual(orderCount, 2, "应该有 2 个有序列表项")
    }
}
