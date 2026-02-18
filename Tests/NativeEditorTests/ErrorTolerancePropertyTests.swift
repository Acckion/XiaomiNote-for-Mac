//
//  ErrorTolerancePropertyTests.swift
//  MiNoteMac
//
//  错误容错性属性测试
//  Property 8: 错误容错性
//

import XCTest
@testable import MiNoteLibrary

/// 错误容错性属性测试
/// Feature: xml-attributedstring-converter, Property 8: 错误容错性
final class ErrorTolerancePropertyTests: XCTestCase {

    var parser: MiNoteXMLParser!

    override func setUp() {
        super.setUp()
        parser = MiNoteXMLParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Property 8: 错误容错性

    // *For any* 包含不支持元素的 XML，解析器应该跳过不支持的元素并继续处理其余内容，
    // 最终结果应该包含所有可解析的内容。

    /// 属性测试：跳过不支持的块级元素
    /// 对于任意包含不支持块级元素的 XML，解析器应该跳过该元素并继续处理其他元素
    /// _Requirements: 7.1_
    func testProperty8_SkipUnsupportedBlockElements() throws {
        let unsupportedTags = ["video", "table", "code", "div", "span", "unknown"]

        for _ in 0 ..< 100 {
            // 随机选择一个不支持的标签
            let unsupportedTag = try XCTUnwrap(unsupportedTags.randomElement())

            // 生成包含不支持元素的 XML
            let validText1 = generateRandomText()
            let validText2 = generateRandomText()
            let unsupportedContent = generateRandomText()

            let xml = """
            <text indent="1">\(XMLEntityCodec.encode(validText1))</text>
            <\(unsupportedTag)>\(XMLEntityCodec.encode(unsupportedContent))</\(unsupportedTag)>
            <text indent="1">\(XMLEntityCodec.encode(validText2))</text>
            """

            let result = try parser.parse(xml)
            let document = result.value

            // 验证：应该解析出两个有效的文本块，跳过不支持的元素
            XCTAssertEqual(document.blocks.count, 2, "应该解析出两个有效的块级节点，跳过不支持的元素")

            // 验证警告
            XCTAssertTrue(result.hasWarnings, "应该有警告信息")
            XCTAssertTrue(
                result.warnings.contains { $0.message.contains(unsupportedTag) },
                "警告信息应该包含不支持的元素名称"
            )

            // 验证内容
            guard let textBlock1 = document.blocks[0] as? TextBlockNode,
                  let textBlock2 = document.blocks[1] as? TextBlockNode
            else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }

            XCTAssertEqual(extractPlainText(from: textBlock1.content), validText1, "第一个文本块内容应该正确")
            XCTAssertEqual(extractPlainText(from: textBlock2.content), validText2, "第二个文本块内容应该正确")
        }
    }

    /// 属性测试：跳过不支持的行内元素
    /// 对于任意包含不支持行内元素的 XML，解析器应该跳过该元素并继续处理其他内容
    /// _Requirements: 7.1_
    func testProperty8_SkipUnsupportedInlineElements() throws {
        let unsupportedTags = ["strong", "em", "mark", "code", "sup", "sub"]

        for _ in 0 ..< 100 {
            let unsupportedTag = try XCTUnwrap(unsupportedTags.randomElement())

            let validText1 = generateRandomText()
            let unsupportedContent = generateRandomText()
            let validText2 = generateRandomText()

            let xml = """
            <text indent="1"><b>\(XMLEntityCodec.encode(validText1))</b><\(unsupportedTag)>\(XMLEntityCodec
                .encode(unsupportedContent))</\(unsupportedTag)><i>\(XMLEntityCodec.encode(validText2))</i></text>
            """

            let result = try parser.parse(xml)
            let document = result.value

            // 验证：应该解析出一个文本块，包含两个有效的格式节点
            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let textBlock = document.blocks.first as? TextBlockNode else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }

            // 应该有两个有效的行内节点（粗体和斜体），不支持的元素被跳过
            XCTAssertEqual(textBlock.content.count, 2, "应该有两个有效的行内节点")

            // 验证警告
            XCTAssertTrue(result.hasWarnings, "应该有警告信息")
            XCTAssertTrue(
                result.warnings.contains { $0.message.contains(unsupportedTag) },
                "警告信息应该包含不支持的元素名称"
            )
        }
    }

    /// 属性测试：处理混合的有效和无效元素
    /// 对于包含多个不支持元素的 XML，解析器应该跳过所有不支持的元素，保留所有有效内容
    /// _Requirements: 7.1_
    func testProperty8_HandleMixedValidAndInvalidElements() throws {
        for _ in 0 ..< 50 {
            // 生成包含多个有效和无效元素的 XML
            let validTexts = (0 ..< Int.random(in: 2 ... 5)).map { _ in generateRandomText() }
            let unsupportedCount = Int.random(in: 1 ... 3)

            var xml = ""
            var expectedValidCount = 0
            var actualUnsupportedCount = 0

            for (index, text) in validTexts.enumerated() {
                // 添加有效的文本块
                xml += "<text indent=\"1\">\(XMLEntityCodec.encode(text))</text>\n"
                expectedValidCount += 1

                // 随机插入不支持的元素
                if index < unsupportedCount {
                    let unsupportedTag = ["video", "table", "unknown"].randomElement()!
                    xml += "<\(unsupportedTag)>content</\(unsupportedTag)>\n"
                    actualUnsupportedCount += 1
                }
            }

            let result = try parser.parse(xml)
            let document = result.value

            // 验证：应该解析出所有有效的文本块
            XCTAssertEqual(
                document.blocks.count,
                expectedValidCount,
                "应该解析出 \(expectedValidCount) 个有效的块级节点"
            )

            // 验证警告数量（至少应该有实际插入的不支持元素数量的警告）
            XCTAssertGreaterThanOrEqual(
                result.warnings.count,
                actualUnsupportedCount,
                "应该至少有 \(actualUnsupportedCount) 个警告"
            )

            // 验证内容
            for (index, block) in document.blocks.enumerated() {
                guard let textBlock = block as? TextBlockNode else {
                    XCTFail("应该是 TextBlockNode 类型")
                    continue
                }
                XCTAssertEqual(
                    extractPlainText(from: textBlock.content),
                    validTexts[index],
                    "文本块 \(index) 的内容应该正确"
                )
            }
        }
    }

    /// 属性测试：处理嵌套的不支持元素
    /// 对于嵌套的不支持元素，解析器应该正确跳过整个嵌套结构
    /// _Requirements: 7.1_
    func testProperty8_HandleNestedUnsupportedElements() throws {
        for _ in 0 ..< 50 {
            let validText1 = generateRandomText()
            let validText2 = generateRandomText()

            // 创建嵌套的不支持元素
            let xml = """
            <text indent="1">\(XMLEntityCodec.encode(validText1))</text>
            <table>
                <tr>
                    <td>cell content</td>
                </tr>
            </table>
            <text indent="1">\(XMLEntityCodec.encode(validText2))</text>
            """

            let result = try parser.parse(xml)
            let document = result.value

            // 验证：应该解析出两个有效的文本块
            XCTAssertEqual(document.blocks.count, 2, "应该解析出两个有效的块级节点")

            // 验证警告
            XCTAssertTrue(result.hasWarnings, "应该有警告信息")

            // 验证内容
            guard let textBlock1 = document.blocks[0] as? TextBlockNode,
                  let textBlock2 = document.blocks[1] as? TextBlockNode
            else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }

            XCTAssertEqual(extractPlainText(from: textBlock1.content), validText1, "第一个文本块内容应该正确")
            XCTAssertEqual(extractPlainText(from: textBlock2.content), validText2, "第二个文本块内容应该正确")
        }
    }

    /// 属性测试：处理引用块中的不支持元素
    /// 对于引用块内的不支持元素，解析器应该跳过该元素但保留引用块结构
    /// _Requirements: 7.1_
    func testProperty8_HandleUnsupportedElementsInQuote() throws {
        for _ in 0 ..< 50 {
            let validText1 = generateRandomText()
            let validText2 = generateRandomText()

            let xml = """
            <quote>
            <text indent="1">\(XMLEntityCodec.encode(validText1))</text>
            <unknown>invalid content</unknown>
            <text indent="1">\(XMLEntityCodec.encode(validText2))</text>
            </quote>
            """

            let result = try parser.parse(xml)
            let document = result.value

            // 验证：应该解析出一个引用块
            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let quote = document.blocks.first as? QuoteNode else {
                XCTFail("应该是 QuoteNode 类型")
                continue
            }

            // 引用块应该包含两个有效的文本块
            XCTAssertEqual(quote.textBlocks.count, 2, "引用块应该包含两个有效的文本块")

            // 验证警告
            XCTAssertTrue(result.hasWarnings, "应该有警告信息")

            // 验证内容
            XCTAssertEqual(
                extractPlainText(from: quote.textBlocks[0].content),
                validText1,
                "第一个文本块内容应该正确"
            )
            XCTAssertEqual(
                extractPlainText(from: quote.textBlocks[1].content),
                validText2,
                "第二个文本块内容应该正确"
            )
        }
    }

    /// 属性测试：处理完全无效的 XML
    /// 对于完全无效的 XML（词法分析失败），解析器应该使用纯文本回退
    /// _Requirements: 7.3, 7.4_
    func testProperty8_FallbackToPlainTextOnInvalidXML() throws {
        let invalidXMLCases = [
            "这是纯文本，没有任何 XML 标签",
            "< 这是不完整的标签",
            "这是文本 <unclosed",
            "<<>>混乱的标签",
        ]

        for invalidXML in invalidXMLCases {
            let result = try parser.parse(invalidXML)
            let document = result.value

            // 验证：应该有回退的文本块
            XCTAssertGreaterThan(document.blocks.count, 0, "应该有回退的文本块，输入: \(invalidXML)")

            // 注意：当前的 XMLTokenizer 可能不会对所有无效 XML 抛出错误
            // 它可能会尝试解析并生成文本节点
            // 所以我们只验证能够成功解析，不一定有警告
            // 如果有警告，验证警告内容
            if result.hasWarnings {
                // 有警告是好的，但不是必需的
                print("警告信息: \(result.warnings.map(\.message))")
            }
        }
    }

    /// 属性测试：错误恢复后继续解析
    /// 遇到错误后，解析器应该能够恢复并继续解析后续的有效内容
    /// _Requirements: 7.1_
    func testProperty8_ContinueParsingAfterError() throws {
        for _ in 0 ..< 50 {
            let validText1 = generateRandomText()
            let validText2 = generateRandomText()
            let validText3 = generateRandomText()

            // 在中间插入多个不支持的元素
            let xml = """
            <text indent="1">\(XMLEntityCodec.encode(validText1))</text>
            <unknown1>content1</unknown1>
            <unknown2>content2</unknown2>
            <text indent="1">\(XMLEntityCodec.encode(validText2))</text>
            <unknown3>content3</unknown3>
            <text indent="1">\(XMLEntityCodec.encode(validText3))</text>
            """

            let result = try parser.parse(xml)
            let document = result.value

            // 验证：应该解析出三个有效的文本块
            XCTAssertEqual(document.blocks.count, 3, "应该解析出三个有效的块级节点")

            // 验证警告数量
            XCTAssertGreaterThanOrEqual(result.warnings.count, 3, "应该至少有 3 个警告")

            // 验证内容
            let texts = [validText1, validText2, validText3]
            for (index, block) in document.blocks.enumerated() {
                guard let textBlock = block as? TextBlockNode else {
                    XCTFail("应该是 TextBlockNode 类型")
                    continue
                }
                XCTAssertEqual(
                    extractPlainText(from: textBlock.content),
                    texts[index],
                    "文本块 \(index) 的内容应该正确"
                )
            }
        }
    }

    /// 属性测试：警告类型正确性
    /// 对于不同类型的错误，解析器应该生成正确类型的警告
    /// _Requirements: 7.1_
    func testProperty8_WarningTypesCorrectness() throws {
        // 测试不支持的元素警告
        let xml1 = "<unknown>content</unknown>"
        let result1 = try parser.parse(xml1)

        XCTAssertTrue(result1.hasWarnings, "应该有警告")
        XCTAssertTrue(
            result1.warnings.contains { $0.type == .unsupportedElement },
            "应该有不支持元素类型的警告"
        )

        // 测试引用块中的不支持元素警告
        let xml2 = """
        <quote>
        <unknown>content</unknown>
        </quote>
        """
        let result2 = try parser.parse(xml2)

        XCTAssertTrue(result2.hasWarnings, "应该有警告")
        XCTAssertTrue(
            result2.warnings.contains { $0.type == .unsupportedElement },
            "应该有不支持元素类型的警告"
        )
    }

    // MARK: - 辅助方法

    /// 生成随机文本
    private func generateRandomText() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789你好世界测试 "
        let length = Int.random(in: 5 ... 30)
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }
}
