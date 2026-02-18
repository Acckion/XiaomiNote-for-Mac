//
//  XMLParserPropertyTests.swift
//  MiNoteMac
//
//  XML 解析器属性测试
//  Property 7: 块级元素解析正确性
//

import XCTest
@testable import MiNoteLibrary

/// XML 解析器属性测试
/// Feature: xml-attributedstring-converter, Property 7: 块级元素解析正确性
final class XMLParserPropertyTests: XCTestCase {

    var parser: MiNoteXMLParser!

    override func setUp() {
        super.setUp()
        parser = MiNoteXMLParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Property 7: 块级元素解析正确性

    // *For any* 有效的块级元素 XML（text, bullet, order, checkbox, hr, img, sound, quote），
    // 解析后应该生成正确类型的 AST 节点，且所有属性（indent, inputNumber, checked, fileId 等）应该被正确保留。

    /// 属性测试：文本块解析正确性
    /// 对于任意有效的缩进值，解析后的 TextBlockNode 应该保留正确的缩进属性
    /// _Requirements: 1.1_
    func testProperty7_TextBlockParsing() throws {
        // 生成 100 个随机测试用例
        for _ in 0 ..< 100 {
            let indent = Int.random(in: 1 ... 10)
            let textContent = generateRandomText()
            let xml = "<text indent=\"\(indent)\">\(XMLEntityCodec.encode(textContent))</text>"

            let result = try parser.parse(xml)
            let document = result.value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let textBlock = document.blocks.first as? TextBlockNode else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }

            XCTAssertEqual(textBlock.indent, indent, "缩进值应该正确保留")
            XCTAssertEqual(extractPlainText(from: textBlock.content), textContent, "文本内容应该正确保留")
        }
    }

    /// 属性测试：无序列表解析正确性
    /// 对于任意有效的缩进值，解析后的 BulletListNode 应该保留正确的缩进属性
    /// _Requirements: 1.2_
    func testProperty7_BulletListParsing() throws {
        for _ in 0 ..< 100 {
            let indent = Int.random(in: 1 ... 10)
            let textContent = generateRandomText()
            let xml = "<bullet indent=\"\(indent)\" />\(XMLEntityCodec.encode(textContent))\n"

            let document = try parser.parse(xml).value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let bulletList = document.blocks.first as? BulletListNode else {
                XCTFail("应该是 BulletListNode 类型")
                continue
            }

            XCTAssertEqual(bulletList.indent, indent, "缩进值应该正确保留")
            XCTAssertEqual(extractPlainText(from: bulletList.content), textContent, "文本内容应该正确保留")
        }
    }

    /// 属性测试：有序列表解析正确性
    /// 对于任意有效的缩进值和 inputNumber，解析后的 OrderedListNode 应该保留所有属性
    /// _Requirements: 1.3_
    func testProperty7_OrderedListParsing() throws {
        for _ in 0 ..< 100 {
            let indent = Int.random(in: 1 ... 10)
            let inputNumber = Int.random(in: 0 ... 100)
            let textContent = generateRandomText()
            let xml = "<order indent=\"\(indent)\" inputNumber=\"\(inputNumber)\" />\(XMLEntityCodec.encode(textContent))\n"

            let document = try parser.parse(xml).value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let orderedList = document.blocks.first as? OrderedListNode else {
                XCTFail("应该是 OrderedListNode 类型")
                continue
            }

            XCTAssertEqual(orderedList.indent, indent, "缩进值应该正确保留")
            XCTAssertEqual(orderedList.inputNumber, inputNumber, "inputNumber 应该正确保留")
            XCTAssertEqual(extractPlainText(from: orderedList.content), textContent, "文本内容应该正确保留")
        }
    }

    /// 属性测试：复选框解析正确性
    /// 对于任意有效的属性组合，解析后的 CheckboxNode 应该保留所有属性
    /// _Requirements: 1.4_
    func testProperty7_CheckboxParsing() throws {
        for _ in 0 ..< 100 {
            let indent = Int.random(in: 1 ... 10)
            let level = Int.random(in: 1 ... 5)
            let isChecked = Bool.random()
            let textContent = generateRandomText()

            var xml = "<input type=\"checkbox\" indent=\"\(indent)\" level=\"\(level)\""
            if isChecked {
                xml += " checked=\"true\""
            }
            xml += " />\(XMLEntityCodec.encode(textContent))\n"

            let document = try parser.parse(xml).value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let checkbox = document.blocks.first as? CheckboxNode else {
                XCTFail("应该是 CheckboxNode 类型")
                continue
            }

            XCTAssertEqual(checkbox.indent, indent, "缩进值应该正确保留")
            XCTAssertEqual(checkbox.level, level, "level 应该正确保留")
            XCTAssertEqual(checkbox.isChecked, isChecked, "checked 状态应该正确保留")
            XCTAssertEqual(extractPlainText(from: checkbox.content), textContent, "文本内容应该正确保留")
        }
    }

    /// 属性测试：分割线解析正确性
    /// _Requirements: 1.5_
    func testProperty7_HorizontalRuleParsing() throws {
        let xml = "<hr />"

        let document = try parser.parse(xml).value

        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        XCTAssertTrue(document.blocks.first is HorizontalRuleNode, "应该是 HorizontalRuleNode 类型")
    }

    /// 属性测试：图片解析正确性
    /// 对于任意有效的图片属性，解析后的 ImageNode 应该保留所有属性
    /// _Requirements: 1.6_
    func testProperty7_ImageParsing() throws {
        for _ in 0 ..< 100 {
            let fileId = generateRandomFileId()
            let width = Int.random(in: 100 ... 1000)
            let height = Int.random(in: 100 ... 1000)

            let xml = "<img fileid=\"\(fileId)\" width=\"\(width)\" height=\"\(height)\" />"

            let document = try parser.parse(xml).value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let image = document.blocks.first as? ImageNode else {
                XCTFail("应该是 ImageNode 类型")
                continue
            }

            XCTAssertEqual(image.fileId, fileId, "fileId 应该正确保留")
            XCTAssertEqual(image.width, width, "width 应该正确保留")
            XCTAssertEqual(image.height, height, "height 应该正确保留")
        }
    }

    /// 属性测试：音频解析正确性
    /// 对于任意有效的音频属性，解析后的 AudioNode 应该保留所有属性
    /// _Requirements: 1.7_
    func testProperty7_AudioParsing() throws {
        for _ in 0 ..< 100 {
            let fileId = generateRandomFileId()
            let isTemporary = Bool.random()

            var xml = "<sound fileid=\"\(fileId)\""
            if isTemporary {
                xml += " temporary=\"true\""
            }
            xml += " />"

            let document = try parser.parse(xml).value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let audio = document.blocks.first as? AudioNode else {
                XCTFail("应该是 AudioNode 类型")
                continue
            }

            XCTAssertEqual(audio.fileId, fileId, "fileId 应该正确保留")
            XCTAssertEqual(audio.isTemporary, isTemporary, "isTemporary 应该正确保留")
        }
    }

    /// 属性测试：引用块解析正确性
    /// 对于任意数量的内部文本块，解析后的 QuoteNode 应该正确包含所有文本块
    /// _Requirements: 1.8_
    func testProperty7_QuoteParsing() throws {
        for _ in 0 ..< 100 {
            let blockCount = Int.random(in: 1 ... 5)
            var innerXML = ""
            var expectedTexts: [String] = []

            for _ in 0 ..< blockCount {
                let text = generateRandomText()
                expectedTexts.append(text)
                innerXML += "<text indent=\"1\">\(XMLEntityCodec.encode(text))</text>\n"
            }

            let xml = "<quote>\(innerXML)</quote>"

            let document = try parser.parse(xml).value

            XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

            guard let quote = document.blocks.first as? QuoteNode else {
                XCTFail("应该是 QuoteNode 类型")
                continue
            }

            XCTAssertEqual(quote.textBlocks.count, blockCount, "内部文本块数量应该正确")

            for (index, textBlock) in quote.textBlocks.enumerated() {
                XCTAssertEqual(extractPlainText(from: textBlock.content), expectedTexts[index], "文本内容应该正确保留")
            }
        }
    }

    // MARK: - 辅助方法

    /// 生成随机文本（不包含 XML 特殊字符）
    private func generateRandomText() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789你好世界测试文本中文内容 "
        let length = Int.random(in: 1 ... 50)
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }

    /// 生成随机文件 ID
    private func generateRandomFileId() -> String {
        let prefix = String(Int.random(in: 1_000_000_000 ... 9_999_999_999))
        let suffix = String((0 ..< 22).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        return "\(prefix).\(suffix)"
    }
}

// MARK: - XML 实体编解码属性测试

/// XML 实体编解码属性测试
/// Feature: xml-attributedstring-converter, Property 6: 特殊字符编解码正确性
final class XMLEntityCodecPropertyTests: XCTestCase {

    /// 属性测试：特殊字符编解码往返一致性
    /// 对于任意包含 XML 特殊字符的文本，编码后再解码应该得到原始文本
    /// _Requirements: 2.12, 3.6_
    func testProperty6_EncodeDecodeRoundTrip() {
        let specialChars = "<>&\"'"

        for _ in 0 ..< 100 {
            // 生成包含特殊字符的随机文本
            let text = generateRandomTextWithSpecialChars(specialChars: specialChars)

            // 编码
            let encoded = XMLEntityCodec.encode(text)

            // 解码
            let decoded = XMLEntityCodec.decode(encoded)

            // 验证往返一致性
            XCTAssertEqual(decoded, text, "编码后再解码应该得到原始文本")
        }
    }

    /// 属性测试：编码后不包含原始特殊字符
    /// 对于任意包含 XML 特殊字符的文本，编码后不应该包含原始的特殊字符
    func testProperty6_EncodedTextNoSpecialChars() {
        for _ in 0 ..< 100 {
            let text = generateRandomTextWithSpecialChars(specialChars: "<>&\"'")
            let encoded = XMLEntityCodec.encode(text)

            // 检查编码后的文本不包含原始特殊字符（除非它们是实体的一部分）
            // 注意：& 会出现在实体中，所以我们只检查 < > " '
            XCTAssertFalse(encoded.contains("<"), "编码后不应该包含 <")
            XCTAssertFalse(encoded.contains(">"), "编码后不应该包含 >")

            // 检查 " 和 ' 是否被正确编码
            for char in text {
                if char == "\"" {
                    XCTAssertTrue(encoded.contains("&quot;"), "双引号应该被编码为 &quot;")
                }
                if char == "'" {
                    XCTAssertTrue(encoded.contains("&apos;"), "单引号应该被编码为 &apos;")
                }
            }
        }
    }

    /// 属性测试：解码已知实体
    func testProperty6_DecodeKnownEntities() {
        let testCases: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&lt;&gt;&amp;&quot;&apos;", "<>&\"'"),
            ("Hello &lt;World&gt;", "Hello <World>"),
            ("&amp;amp;", "&amp;"), // 双重编码的情况
        ]

        for (input, expected) in testCases {
            let decoded = XMLEntityCodec.decode(input)
            XCTAssertEqual(decoded, expected, "解码 '\(input)' 应该得到 '\(expected)'")
        }
    }

    /// 属性测试：解码数字实体
    func testProperty6_DecodeNumericEntities() {
        let testCases: [(String, String)] = [
            ("&#60;", "<"),
            ("&#62;", ">"),
            ("&#38;", "&"),
            ("&#x3C;", "<"),
            ("&#x3E;", ">"),
            ("&#x26;", "&"),
            ("&#20320;&#22909;", "你好"), // 中文字符
        ]

        for (input, expected) in testCases {
            let decoded = XMLEntityCodec.decode(input)
            XCTAssertEqual(decoded, expected, "解码 '\(input)' 应该得到 '\(expected)'")
        }
    }

    // MARK: - 辅助方法

    /// 生成包含特殊字符的随机文本
    private func generateRandomTextWithSpecialChars(specialChars: String) -> String {
        let normalChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789你好世界 "
        let allChars = normalChars + specialChars
        let length = Int.random(in: 1 ... 50)
        return String((0 ..< length).map { _ in allChars.randomElement()! })
    }
}

// MARK: - 嵌套格式解析属性测试

/// 嵌套格式解析属性测试
/// Feature: xml-attributedstring-converter, Property 3: 嵌套格式解析正确性
final class NestedFormatParsingPropertyTests: XCTestCase {

    var parser: MiNoteXMLParser!

    override func setUp() {
        super.setUp()
        parser = MiNoteXMLParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Property 3: 嵌套格式解析正确性

    // *For any* 包含嵌套格式标签的 XML（如 `<b><i>文本</i></b>`），
    // 解析后的 AST 树结构应该正确反映嵌套关系，且内层节点的父节点类型应该与外层标签对应。

    /// 属性测试：双层嵌套格式解析正确性
    /// 对于任意两种不同的格式类型组合，嵌套后解析应该正确反映嵌套关系
    /// _Requirements: 2.11_
    func testProperty3_TwoLevelNestedFormatParsing() throws {
        let formatTypes: [(String, ASTNodeType)] = [
            ("b", .bold),
            ("i", .italic),
            ("u", .underline),
            ("delete", .strikethrough),
            ("size", .heading1),
            ("mid-size", .heading2),
            ("h3-size", .heading3),
            ("center", .centerAlign),
            ("right", .rightAlign),
        ]

        // 测试所有两两组合
        for (outerTag, outerType) in formatTypes {
            for (innerTag, innerType) in formatTypes {
                // 跳过相同类型的嵌套
                if outerTag == innerTag { continue }

                let textContent = "测试文本"
                let xml = "<text indent=\"1\"><\(outerTag)><\(innerTag)>\(textContent)</\(innerTag)></\(outerTag)></text>"

                let document = try parser.parse(xml).value

                XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")

                guard let textBlock = document.blocks.first as? TextBlockNode else {
                    XCTFail("应该是 TextBlockNode 类型")
                    continue
                }

                XCTAssertEqual(textBlock.content.count, 1, "应该有一个行内节点")

                // 验证外层格式节点
                guard let outerNode = textBlock.content.first as? FormattedNode else {
                    XCTFail("应该是 FormattedNode 类型")
                    continue
                }

                XCTAssertEqual(outerNode.nodeType, outerType, "外层节点类型应该是 \(outerType)")
                XCTAssertEqual(outerNode.content.count, 1, "外层节点应该有一个子节点")

                // 验证内层格式节点
                guard let innerNode = outerNode.content.first as? FormattedNode else {
                    XCTFail("内层应该是 FormattedNode 类型")
                    continue
                }

                XCTAssertEqual(innerNode.nodeType, innerType, "内层节点类型应该是 \(innerType)")
                XCTAssertEqual(innerNode.content.count, 1, "内层节点应该有一个子节点")

                // 验证文本节点
                guard let textNode = innerNode.content.first as? TextNode else {
                    XCTFail("最内层应该是 TextNode 类型")
                    continue
                }

                XCTAssertEqual(textNode.text, textContent, "文本内容应该正确")
            }
        }
    }

    /// 属性测试：三层嵌套格式解析正确性
    /// 对于任意三种不同的格式类型组合，嵌套后解析应该正确反映嵌套关系
    /// _Requirements: 2.11_
    func testProperty3_ThreeLevelNestedFormatParsing() throws {
        // 选择几种常用的格式类型进行三层嵌套测试
        let formatTypes: [(String, ASTNodeType)] = [
            ("b", .bold),
            ("i", .italic),
            ("u", .underline),
            ("size", .heading1),
        ]

        // 测试所有三三组合（不重复）
        for i in 0 ..< formatTypes.count {
            for j in 0 ..< formatTypes.count {
                for k in 0 ..< formatTypes.count {
                    // 跳过有重复的组合
                    if i == j || j == k || i == k { continue }

                    let (outerTag, outerType) = formatTypes[i]
                    let (middleTag, middleType) = formatTypes[j]
                    let (innerTag, innerType) = formatTypes[k]

                    let textContent = "嵌套文本"
                    let xml = "<text indent=\"1\"><\(outerTag)><\(middleTag)><\(innerTag)>\(textContent)</\(innerTag)></\(middleTag)></\(outerTag)></text>"

                    let document = try parser.parse(xml).value

                    guard let textBlock = document.blocks.first as? TextBlockNode,
                          let outerNode = textBlock.content.first as? FormattedNode,
                          let middleNode = outerNode.content.first as? FormattedNode,
                          let innerNode = middleNode.content.first as? FormattedNode,
                          let textNode = innerNode.content.first as? TextNode
                    else {
                        XCTFail("三层嵌套结构解析失败: \(outerTag) > \(middleTag) > \(innerTag)")
                        continue
                    }

                    XCTAssertEqual(outerNode.nodeType, outerType, "外层节点类型应该是 \(outerType)")
                    XCTAssertEqual(middleNode.nodeType, middleType, "中层节点类型应该是 \(middleType)")
                    XCTAssertEqual(innerNode.nodeType, innerType, "内层节点类型应该是 \(innerType)")
                    XCTAssertEqual(textNode.text, textContent, "文本内容应该正确")
                }
            }
        }
    }

    /// 属性测试：带高亮的嵌套格式解析正确性
    /// 高亮格式应该正确保留颜色属性
    /// _Requirements: 2.5, 2.11_
    func testProperty3_NestedFormatWithHighlight() throws {
        for _ in 0 ..< 100 {
            let color = generateRandomColor()
            let textContent = generateRandomText()

            // 测试 <b><background color="...">文本</background></b>
            let xml1 = "<text indent=\"1\"><b><background color=\"\(color)\">\(XMLEntityCodec.encode(textContent))</background></b></text>"
            let document1 = try parser.parse(xml1).value

            guard let textBlock1 = document1.blocks.first as? TextBlockNode,
                  let boldNode = textBlock1.content.first as? FormattedNode,
                  let highlightNode = boldNode.content.first as? FormattedNode
            else {
                XCTFail("嵌套结构解析失败")
                continue
            }

            XCTAssertEqual(boldNode.nodeType, .bold, "外层应该是粗体")
            XCTAssertEqual(highlightNode.nodeType, .highlight, "内层应该是高亮")
            XCTAssertEqual(highlightNode.color, color, "高亮颜色应该正确保留")

            // 测试 <background color="..."><i>文本</i></background>
            let xml2 = "<text indent=\"1\"><background color=\"\(color)\"><i>\(XMLEntityCodec.encode(textContent))</i></background></text>"
            let document2 = try parser.parse(xml2).value

            guard let textBlock2 = document2.blocks.first as? TextBlockNode,
                  let highlightNode2 = textBlock2.content.first as? FormattedNode,
                  let italicNode = highlightNode2.content.first as? FormattedNode
            else {
                XCTFail("嵌套结构解析失败")
                continue
            }

            XCTAssertEqual(highlightNode2.nodeType, .highlight, "外层应该是高亮")
            XCTAssertEqual(highlightNode2.color, color, "高亮颜色应该正确保留")
            XCTAssertEqual(italicNode.nodeType, .italic, "内层应该是斜体")
        }
    }

    /// 属性测试：混合嵌套和并列格式解析正确性
    /// 同一层级可以有多个格式节点
    /// _Requirements: 2.11_
    func testProperty3_MixedNestedAndSiblingFormats() throws {
        for _ in 0 ..< 50 {
            let text1 = generateRandomText()
            let text2 = generateRandomText()
            let text3 = generateRandomText()

            // 测试 <b>文本1</b>普通文本<i>文本2</i>
            let xml = "<text indent=\"1\"><b>\(XMLEntityCodec.encode(text1))</b>\(XMLEntityCodec.encode(text2))<i>\(XMLEntityCodec.encode(text3))</i></text>"

            let document = try parser.parse(xml).value

            guard let textBlock = document.blocks.first as? TextBlockNode else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }

            XCTAssertEqual(textBlock.content.count, 3, "应该有三个行内节点")

            // 验证第一个节点（粗体）
            guard let boldNode = textBlock.content[0] as? FormattedNode else {
                XCTFail("第一个节点应该是 FormattedNode")
                continue
            }
            XCTAssertEqual(boldNode.nodeType, .bold, "第一个节点应该是粗体")
            XCTAssertEqual(extractPlainText(from: boldNode.content), text1, "粗体文本内容应该正确")

            // 验证第二个节点（普通文本）
            guard let textNode = textBlock.content[1] as? TextNode else {
                XCTFail("第二个节点应该是 TextNode")
                continue
            }
            XCTAssertEqual(textNode.text, text2, "普通文本内容应该正确")

            // 验证第三个节点（斜体）
            guard let italicNode = textBlock.content[2] as? FormattedNode else {
                XCTFail("第三个节点应该是 FormattedNode")
                continue
            }
            XCTAssertEqual(italicNode.nodeType, .italic, "第三个节点应该是斜体")
            XCTAssertEqual(extractPlainText(from: italicNode.content), text3, "斜体文本内容应该正确")
        }
    }

    /// 属性测试：深度嵌套格式解析正确性
    /// 测试多层深度嵌套
    /// _Requirements: 2.11_
    func testProperty3_DeepNestedFormatParsing() throws {
        let formatTags = ["b", "i", "u", "delete"]

        for depth in 2 ... 4 {
            let textContent = "深度嵌套文本"

            // 构建嵌套 XML
            var openTags = ""
            var closeTags = ""
            var expectedTypes: [ASTNodeType] = []

            for i in 0 ..< depth {
                let tag = formatTags[i % formatTags.count]
                openTags += "<\(tag)>"
                closeTags = "</\(tag)>" + closeTags

                switch tag {
                case "b": expectedTypes.append(.bold)
                case "i": expectedTypes.append(.italic)
                case "u": expectedTypes.append(.underline)
                case "delete": expectedTypes.append(.strikethrough)
                default: break
                }
            }

            let xml = "<text indent=\"1\">\(openTags)\(textContent)\(closeTags)</text>"

            let document = try parser.parse(xml).value

            guard let textBlock = document.blocks.first as? TextBlockNode else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }

            // 遍历嵌套结构验证
            var currentNode: any InlineNode = try XCTUnwrap(textBlock.content.first)

            for (index, expectedType) in expectedTypes.enumerated() {
                guard let formattedNode = currentNode as? FormattedNode else {
                    XCTFail("第 \(index + 1) 层应该是 FormattedNode")
                    break
                }

                XCTAssertEqual(formattedNode.nodeType, expectedType, "第 \(index + 1) 层节点类型应该是 \(expectedType)")

                if index < expectedTypes.count - 1 {
                    currentNode = try XCTUnwrap(formattedNode.content.first)
                } else {
                    // 最内层应该是文本节点
                    guard let textNode = formattedNode.content.first as? TextNode else {
                        XCTFail("最内层应该是 TextNode")
                        break
                    }
                    XCTAssertEqual(textNode.text, textContent, "文本内容应该正确")
                }
            }
        }
    }

    // MARK: - 辅助方法

    /// 生成随机文本
    private func generateRandomText() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789你好世界测试 "
        let length = Int.random(in: 1 ... 20)
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }

    /// 生成随机颜色值
    private func generateRandomColor() -> String {
        let r = String(format: "%02x", Int.random(in: 0 ... 255))
        let g = String(format: "%02x", Int.random(in: 0 ... 255))
        let b = String(format: "%02x", Int.random(in: 0 ... 255))
        let a = String(format: "%02x", Int.random(in: 0 ... 255))
        return "#\(r)\(g)\(b)\(a)"
    }
}
