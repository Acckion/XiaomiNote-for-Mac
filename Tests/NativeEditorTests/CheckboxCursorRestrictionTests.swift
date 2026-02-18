//
//  CheckboxCursorRestrictionTests.swift
//  MiNoteMac
//
//  测试复选框列表的光标限制功能
//  确保光标无法移动到复选框的左侧
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class CheckboxCursorRestrictionTests: XCTestCase {

    var textStorage: NSTextStorage!

    override func setUp() async throws {
        textStorage = NSTextStorage()
    }

    override func tearDown() async throws {
        textStorage = nil
    }

    // MARK: - 光标位置检测测试

    /// 测试检测复选框标记区域
    func testIsInCheckboxMarkerArea() {
        // 创建复选框列表项
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: 3, indent: 1)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)
        let textString = NSAttributedString(string: "测试内容\n")

        let content = NSMutableAttributedString()
        content.append(attachmentString)
        content.append(textString)

        textStorage.setAttributedString(content)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: textStorage.length))

        // 测试位置 0（复选框位置）应该在标记区域内
        XCTAssertTrue(
            ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 0),
            "位置 0（复选框位置）应该在标记区域内"
        )

        // 测试位置 1（复选框之后）不应该在标记区域内
        XCTAssertFalse(
            ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: 1),
            "位置 1（复选框之后）不应该在标记区域内"
        )
    }

    /// 测试获取复选框内容起始位置
    func testGetCheckboxContentStartPosition() {
        // 创建复选框列表项
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: 3, indent: 1)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)
        let textString = NSAttributedString(string: "测试内容\n")

        let content = NSMutableAttributedString()
        content.append(attachmentString)
        content.append(textString)

        textStorage.setAttributedString(content)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: textStorage.length))

        // 内容起始位置应该是 1（复选框占用 1 个字符）
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        XCTAssertEqual(contentStart, 1, "内容起始位置应该是 1")
    }

    /// 测试调整光标位置
    func testAdjustCursorPositionForCheckbox() {
        // 创建复选框列表项
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: 3, indent: 1)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)
        let textString = NSAttributedString(string: "测试内容\n")

        let content = NSMutableAttributedString()
        content.append(attachmentString)
        content.append(textString)

        textStorage.setAttributedString(content)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: textStorage.length))

        // 测试调整位置 0（复选框位置）
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 0)
        XCTAssertEqual(adjustedPosition, 1, "位置 0 应该被调整到位置 1")

        // 测试位置 1（内容起始位置）不应该被调整
        let notAdjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 1)
        XCTAssertEqual(notAdjustedPosition, 1, "位置 1 不应该被调整")
    }

    // MARK: - 列表项信息测试

    /// 测试获取复选框列表项信息
    func testGetCheckboxListItemInfo() {
        // 创建复选框列表项
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: true, level: 3, indent: 2)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)
        let textString = NSAttributedString(string: "测试内容\n")

        let content = NSMutableAttributedString()
        content.append(attachmentString)
        content.append(textString)

        textStorage.setAttributedString(content)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: textStorage.length))
        textStorage.addAttribute(.listIndent, value: 2, range: NSRange(location: 0, length: textStorage.length))
        textStorage.addAttribute(.checkboxLevel, value: 3, range: NSRange(location: 0, length: textStorage.length))
        textStorage.addAttribute(.checkboxChecked, value: true, range: NSRange(location: 0, length: textStorage.length))

        // 获取列表项信息
        guard let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 1) else {
            XCTFail("应该能获取到列表项信息")
            return
        }

        // 验证列表项信息
        XCTAssertEqual(listInfo.listType, .checkbox, "列表类型应该是 checkbox")
        XCTAssertEqual(listInfo.indent, 2, "缩进级别应该是 2")
        XCTAssertEqual(listInfo.isChecked, true, "勾选状态应该是 true")
        XCTAssertEqual(listInfo.contentStartPosition, 1, "内容起始位置应该是 1")
        XCTAssertEqual(listInfo.contentText, "测试内容", "内容文本应该是'测试内容'")
    }

    /// 测试检测空复选框列表项
    func testIsEmptyCheckboxListItem() {
        // 创建空复选框列表项
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: 3, indent: 1)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)
        let newlineString = NSAttributedString(string: "\n")

        let content = NSMutableAttributedString()
        content.append(attachmentString)
        content.append(newlineString)

        textStorage.setAttributedString(content)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: textStorage.length))

        // 应该检测为空列表项
        XCTAssertTrue(
            ListBehaviorHandler.isEmptyListItem(in: textStorage, at: 1),
            "应该检测为空复选框列表项"
        )
    }

    // MARK: - 多行复选框测试

    /// 测试多行复选框列表的光标限制
    func testMultipleCheckboxLines() {
        // 创建多行复选框列表
        let content = NSMutableAttributedString()

        for i in 1 ... 3 {
            let checkboxAttachment = InteractiveCheckboxAttachment(checked: i % 2 == 0, level: 3, indent: 1)
            let attachmentString = NSAttributedString(attachment: checkboxAttachment)
            let textString = NSAttributedString(string: "项目 \(i)\n")

            let lineContent = NSMutableAttributedString()
            lineContent.append(attachmentString)
            lineContent.append(textString)

            // 设置列表类型属性
            lineContent.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: lineContent.length))

            content.append(lineContent)
        }

        textStorage.setAttributedString(content)

        // 测试每一行的复选框位置都在标记区域内
        var currentPosition = 0
        for i in 1 ... 3 {
            XCTAssertTrue(
                ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: currentPosition),
                "第 \(i) 行的复选框位置应该在标记区域内"
            )

            // 移动到下一行
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: currentPosition, length: 0))
            currentPosition = lineRange.location + lineRange.length
        }
    }

    // MARK: - 混合列表类型测试

    /// 测试复选框与其他列表类型的区分
    func testCheckboxVsOtherListTypes() {
        // 创建混合列表
        let content = NSMutableAttributedString()

        // 1. 复选框列表
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: 3, indent: 1)
        let checkboxString = NSMutableAttributedString(attachment: checkboxAttachment)
        checkboxString.append(NSAttributedString(string: "复选框\n"))
        checkboxString.addAttribute(.listType, value: ListType.checkbox, range: NSRange(location: 0, length: checkboxString.length))
        content.append(checkboxString)

        // 2. 无序列表
        let bulletAttachment = BulletAttachment(indent: 1)
        let bulletString = NSMutableAttributedString(attachment: bulletAttachment)
        bulletString.append(NSAttributedString(string: "无序列表\n"))
        bulletString.addAttribute(.listType, value: ListType.bullet, range: NSRange(location: 0, length: bulletString.length))
        content.append(bulletString)

        // 3. 有序列表
        let orderAttachment = OrderAttachment(number: 1, inputNumber: 0, indent: 1)
        let orderString = NSMutableAttributedString(attachment: orderAttachment)
        orderString.append(NSAttributedString(string: "有序列表\n"))
        orderString.addAttribute(.listType, value: ListType.ordered, range: NSRange(location: 0, length: orderString.length))
        content.append(orderString)

        textStorage.setAttributedString(content)

        // 验证每种列表类型都被正确检测
        let checkboxLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
        let checkboxType = ListFormatHandler.detectListType(in: textStorage, at: checkboxLineRange.location)
        XCTAssertEqual(checkboxType, .checkbox, "应该检测为复选框列表")

        let bulletLineStart = checkboxLineRange.location + checkboxLineRange.length
        let bulletLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: bulletLineStart, length: 0))
        let bulletType = ListFormatHandler.detectListType(in: textStorage, at: bulletLineRange.location)
        XCTAssertEqual(bulletType, .bullet, "应该检测为无序列表")

        let orderLineStart = bulletLineRange.location + bulletLineRange.length
        let orderLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: orderLineStart, length: 0))
        let orderType = ListFormatHandler.detectListType(in: textStorage, at: orderLineRange.location)
        XCTAssertEqual(orderType, .ordered, "应该检测为有序列表")
    }
}
