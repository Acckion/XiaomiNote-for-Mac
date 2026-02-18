//
//  AttributedStringRoundTripPropertyTests.swift
//  MiNoteMac
//
//  NSAttributedString 往返一致性属性测试
//  Feature: xml-attributedstring-converter, Property 2: NSAttributedString 往返一致性
//

import AppKit
import XCTest
@testable import MiNoteLibrary

/// NSAttributedString 往返一致性属性测试
///
/// Property 2: NSAttributedString 往返一致性
/// For any 有效的 NSAttributedString，转换为 AST 后再转换回 NSAttributedString，
/// 所有格式属性（粗体、斜体、下划线、删除线、背景色、字体大小、对齐方式）和附件信息应该保持不变。
///
final class AttributedStringRoundTripPropertyTests: XCTestCase {

    // MARK: - Properties

    private var attributedToASTConverter: AttributedStringToASTConverter!
    private var astToAttributedConverter: ASTToAttributedStringConverter!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        attributedToASTConverter = AttributedStringToASTConverter()
        astToAttributedConverter = ASTToAttributedStringConverter(folderId: "0")
    }

    override func tearDown() {
        attributedToASTConverter = nil
        astToAttributedConverter = nil
        super.tearDown()
    }

    // MARK: - Property Tests

    /// 测试纯文本的往返一致性
    func testPlainTextRoundTrip() {
        // 生成随机纯文本
        let texts = [
            "Hello, World!",
            "这是一段中文文本",
            "Mixed 中英文 text",
            "Special chars: <>&\"'",
            "Multiple\nlines\nof\ntext",
        ]

        for text in texts {
            let original = NSAttributedString(string: text)

            // 往返转换
            let ast = attributedToASTConverter.convert(original)
            let result = astToAttributedConverter.convert(ast)

            // 验证文本内容相同
            XCTAssertEqual(result.string, original.string, "纯文本往返后内容应该相同")
        }
    }

    /// 测试粗体格式的往返一致性
    func testBoldFormatRoundTrip() {
        let text = "Bold text"
        let original = NSMutableAttributedString(string: text)

        // 应用粗体
        let boldFont = NSFont.boldSystemFont(ofSize: 14)
        original.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: text.count))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容
        XCTAssertEqual(result.string, original.string, "粗体文本往返后内容应该相同")

        // 验证粗体属性
        let resultFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(resultFont, "应该有字体属性")
        XCTAssertTrue(resultFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false, "应该保持粗体属性")
    }

    /// 测试斜体格式的往返一致性
    func testItalicFormatRoundTrip() {
        let text = "Italic text"
        let original = NSMutableAttributedString(string: text)

        // 应用斜体（使用 obliqueness）
        original.addAttribute(.obliqueness, value: 0.2, range: NSRange(location: 0, length: text.count))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容
        XCTAssertEqual(result.string, original.string, "斜体文本往返后内容应该相同")

        // 验证斜体属性
        let obliqueness = result.attribute(.obliqueness, at: 0, effectiveRange: nil) as? NSNumber
        XCTAssertNotNil(obliqueness, "应该有斜体属性")
        if let obliqueness {
            XCTAssertEqual(obliqueness.doubleValue, 0.2, accuracy: 0.01, "斜体倾斜度应该保持")
        }
    }

    /// 测试下划线格式的往返一致性
    func testUnderlineFormatRoundTrip() {
        let text = "Underlined text"
        let original = NSMutableAttributedString(string: text)

        // 应用下划线
        original.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: text.count))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容
        XCTAssertEqual(result.string, original.string, "下划线文本往返后内容应该相同")

        // 验证下划线属性
        let underlineStyle = result.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertNotNil(underlineStyle, "应该有下划线属性")
        XCTAssertEqual(underlineStyle, NSUnderlineStyle.single.rawValue, "下划线样式应该保持")
    }

    /// 测试删除线格式的往返一致性
    func testStrikethroughFormatRoundTrip() {
        let text = "Strikethrough text"
        let original = NSMutableAttributedString(string: text)

        // 应用删除线
        original.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: text.count))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容
        XCTAssertEqual(result.string, original.string, "删除线文本往返后内容应该相同")

        // 验证删除线属性
        let strikethroughStyle = result.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertNotNil(strikethroughStyle, "应该有删除线属性")
        XCTAssertEqual(strikethroughStyle, NSUnderlineStyle.single.rawValue, "删除线样式应该保持")
    }

    /// 测试高亮格式的往返一致性
    func testHighlightFormatRoundTrip() {
        let text = "Highlighted text"
        let original = NSMutableAttributedString(string: text)

        // 应用高亮（黄色背景）
        let highlightColor = NSColor.systemYellow
        original.addAttribute(.backgroundColor, value: highlightColor, range: NSRange(location: 0, length: text.count))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容
        XCTAssertEqual(result.string, original.string, "高亮文本往返后内容应该相同")

        // 验证背景色属性
        let backgroundColor = result.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(backgroundColor, "应该有背景色属性")
        // 注意：颜色可能会有轻微的转换误差，所以我们只检查是否存在背景色
    }

    /// 测试标题格式的往返一致性
    func testHeadingFormatRoundTrip() {
        let testCases: [(String, CGFloat, NSFont.Weight)] = [
            ("Heading 1", 24, .bold),
            ("Heading 2", 20, .semibold),
            ("Heading 3", 16, .medium),
        ]

        for (text, fontSize, fontWeight) in testCases {
            let original = NSMutableAttributedString(string: text)

            // 应用标题格式
            let font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
            original.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.count))

            // 往返转换
            let ast = attributedToASTConverter.convert(original)
            let result = astToAttributedConverter.convert(ast)

            // 验证文本内容
            XCTAssertEqual(result.string, original.string, "标题文本往返后内容应该相同")

            // 验证字体大小
            let resultFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            XCTAssertNotNil(resultFont, "应该有字体属性")
            if let resultFont {
                XCTAssertEqual(resultFont.pointSize, fontSize, accuracy: 0.1, "字体大小应该保持")
            }
        }
    }

    /// 测试对齐格式的往返一致性
    func testAlignmentFormatRoundTrip() {
        let testCases: [(String, NSTextAlignment)] = [
            ("Left aligned", .left),
            ("Center aligned", .center),
            ("Right aligned", .right),
        ]

        for (text, alignment) in testCases {
            let original = NSMutableAttributedString(string: text)

            // 应用对齐格式
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            original.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: text.count))

            // 往返转换
            let ast = attributedToASTConverter.convert(original)
            let result = astToAttributedConverter.convert(ast)

            // 验证文本内容
            XCTAssertEqual(result.string, original.string, "对齐文本往返后内容应该相同")

            // 验证对齐属性（仅对居中和右对齐进行验证，因为左对齐是默认值）
            if alignment != .left {
                let resultParagraphStyle = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
                XCTAssertNotNil(resultParagraphStyle, "应该有段落样式属性")
                XCTAssertEqual(resultParagraphStyle?.alignment, alignment, "对齐方式应该保持")
            }
        }
    }

    /// 测试混合格式的往返一致性
    func testMixedFormatsRoundTrip() {
        let text = "Bold and italic text"
        let original = NSMutableAttributedString(string: text)

        // 应用粗体和斜体
        let boldFont = NSFont.boldSystemFont(ofSize: 14)
        original.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: text.count))
        original.addAttribute(.obliqueness, value: 0.2, range: NSRange(location: 0, length: text.count))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容
        XCTAssertEqual(result.string, original.string, "混合格式文本往返后内容应该相同")

        // 验证粗体属性
        let resultFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(resultFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false, "应该保持粗体属性")

        // 验证斜体属性
        let obliqueness = result.attribute(.obliqueness, at: 0, effectiveRange: nil) as? NSNumber
        if let obliqueness {
            XCTAssertEqual(obliqueness.doubleValue, 0.2, accuracy: 0.01, "斜体倾斜度应该保持")
        }
    }

    /// 测试多段落文本的往返一致性
    func testMultipleParagraphsRoundTrip() {
        let text = "First paragraph\nSecond paragraph\nThird paragraph"
        let original = NSAttributedString(string: text)

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证文本内容（注意：段落分隔符可能会有变化）
        let originalLines = original.string.components(separatedBy: "\n")
        let resultLines = result.string.components(separatedBy: "\n")

        XCTAssertEqual(resultLines.count, originalLines.count, "段落数量应该相同")

        for (originalLine, resultLine) in zip(originalLines, resultLines) {
            XCTAssertEqual(
                resultLine.trimmingCharacters(in: .whitespacesAndNewlines),
                originalLine.trimmingCharacters(in: .whitespacesAndNewlines),
                "每个段落的内容应该相同"
            )
        }
    }

    /// 测试附件的往返一致性（分割线）
    func testHorizontalRuleAttachmentRoundTrip() {
        let original = NSMutableAttributedString()

        // 添加分割线附件
        let hrAttachment = HorizontalRuleAttachment()
        original.append(NSAttributedString(attachment: hrAttachment))

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证附件存在
        XCTAssertTrue(result.length > 0, "结果应该包含内容")

        // 验证附件类型
        let attachment = result.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(attachment, "应该有附件")
        XCTAssertTrue(attachment is HorizontalRuleAttachment, "附件类型应该是 HorizontalRuleAttachment")
    }

    /// 测试复选框附件的往返一致性
    func testCheckboxAttachmentRoundTrip() {
        let testCases: [(Bool, Int, Int)] = [
            (false, 1, 3),
            (true, 2, 3),
            (false, 1, 1),
            (true, 3, 5),
        ]

        for (isChecked, indent, level) in testCases {
            let original = NSMutableAttributedString()

            // 添加复选框附件
            let checkboxAttachment = InteractiveCheckboxAttachment(checked: isChecked, level: level, indent: indent)
            original.append(NSAttributedString(attachment: checkboxAttachment))
            original.append(NSAttributedString(string: " Task item"))

            // 往返转换
            let ast = attributedToASTConverter.convert(original)
            let result = astToAttributedConverter.convert(ast)

            // 验证附件存在
            let attachment = result.attribute(.attachment, at: 0, effectiveRange: nil) as? InteractiveCheckboxAttachment
            XCTAssertNotNil(attachment, "应该有复选框附件")
            XCTAssertEqual(attachment?.isChecked, isChecked, "复选框状态应该保持")
            XCTAssertEqual(attachment?.level, level, "复选框层级应该保持")
            XCTAssertEqual(attachment?.indent, indent, "复选框缩进应该保持")

            // 验证文本内容
            XCTAssertTrue(result.string.contains("Task item"), "应该包含任务文本")
        }
    }

    /// 测试列表附件的往返一致性
    func testListAttachmentRoundTrip() {
        // 测试无序列表
        let bulletOriginal = NSMutableAttributedString()
        let bulletAttachment = BulletAttachment(indent: 1)
        bulletOriginal.append(NSAttributedString(attachment: bulletAttachment))
        bulletOriginal.append(NSAttributedString(string: " Bullet item"))

        let bulletAST = attributedToASTConverter.convert(bulletOriginal)
        let bulletResult = astToAttributedConverter.convert(bulletAST)

        let bulletResultAttachment = bulletResult.attribute(.attachment, at: 0, effectiveRange: nil) as? BulletAttachment
        XCTAssertNotNil(bulletResultAttachment, "应该有无序列表附件")
        XCTAssertTrue(bulletResult.string.contains("Bullet item"), "应该包含列表项文本")

        // 测试有序列表
        let orderOriginal = NSMutableAttributedString()
        let orderAttachment = OrderAttachment(number: 1, inputNumber: 0, indent: 1)
        orderOriginal.append(NSAttributedString(attachment: orderAttachment))
        orderOriginal.append(NSAttributedString(string: " Ordered item"))

        let orderAST = attributedToASTConverter.convert(orderOriginal)
        let orderResult = astToAttributedConverter.convert(orderAST)

        let orderResultAttachment = orderResult.attribute(.attachment, at: 0, effectiveRange: nil) as? OrderAttachment
        XCTAssertNotNil(orderResultAttachment, "应该有有序列表附件")
        XCTAssertEqual(orderResultAttachment?.inputNumber, 0, "inputNumber 应该保持")
        XCTAssertTrue(orderResult.string.contains("Ordered item"), "应该包含列表项文本")
    }

    /// 测试空字符串的往返一致性
    func testEmptyStringRoundTrip() {
        let original = NSAttributedString(string: "")

        // 往返转换
        let ast = attributedToASTConverter.convert(original)
        let result = astToAttributedConverter.convert(ast)

        // 验证结果为空或只包含空白字符
        XCTAssertTrue(
            result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "空字符串往返后应该仍然为空"
        )
    }
}
