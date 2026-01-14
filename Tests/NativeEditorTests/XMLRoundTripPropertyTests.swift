//
//  XMLRoundTripPropertyTests.swift
//  MiNoteMac
//
//  XML 往返测试
//  Property 1: XML 解析往返一致性
//  Validates: Requirements 6.1, 6.3, 6.4
//

import XCTest
@testable import MiNoteLibrary

/// XML 往返属性测试
/// Feature: xml-attributedstring-converter, Property 1: XML 解析往返一致性
/// *For any* 有效的小米笔记 XML 字符串，解析为 AST 后再生成 XML，
/// 生成的 XML 与原始 XML 应该语义等价（文本内容相同，格式属性相同，附件信息相同）。
final class XMLRoundTripPropertyTests: XCTestCase {
    
    var parser: MiNoteXMLParser!
    var generator: XMLGenerator!
    
    override func setUp() {
        super.setUp()
        parser = MiNoteXMLParser()
        generator = XMLGenerator()
    }
    
    override func tearDown() {
        parser = nil
        generator = nil
        super.tearDown()
    }
    
    // MARK: - Property 1: XML 解析往返一致性
    
    /// 属性测试：文本块往返一致性
    /// 对于任意有效的文本块 XML，解析后再生成应该语义等价
    /// _Requirements: 6.1, 6.3_
    func testProperty1_TextBlockRoundTrip() throws {
        for _ in 0..<100 {
            let indent = Int.random(in: 1...10)
            let textContent = generateRandomText()
            let originalXML = "<text indent=\"\(indent)\">\(XMLEntityCodec.encode(textContent))</text>"
            
            // 解析
            let document = try parser.parse(originalXML).value
            
            // 生成
            let generatedXML = generator.generate(document)
            
            // 再次解析生成的 XML
            let document2 = try parser.parse(generatedXML).value
            
            // 验证语义等价
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价\n原始: \(originalXML)\n生成: \(generatedXML)")
            
            // 验证文本内容
            guard let textBlock = document2.blocks.first as? TextBlockNode else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }
            XCTAssertEqual(textBlock.indent, indent, "缩进应该保持不变")
            XCTAssertEqual(extractPlainText(from: textBlock.content), textContent, "文本内容应该保持不变")
        }
    }
    
    /// 属性测试：无序列表往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_BulletListRoundTrip() throws {
        for _ in 0..<100 {
            let indent = Int.random(in: 1...10)
            let textContent = generateRandomText()
            let originalXML = "<bullet indent=\"\(indent)\" />\(XMLEntityCodec.encode(textContent))"
            
            let document = try parser.parse(originalXML + "\n").value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML + "\n").value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let bulletList = document2.blocks.first as? BulletListNode else {
                XCTFail("应该是 BulletListNode 类型")
                continue
            }
            XCTAssertEqual(bulletList.indent, indent, "缩进应该保持不变")
            XCTAssertEqual(extractPlainText(from: bulletList.content), textContent, "文本内容应该保持不变")
        }
    }
    
    /// 属性测试：有序列表往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_OrderedListRoundTrip() throws {
        for _ in 0..<100 {
            let indent = Int.random(in: 1...10)
            let inputNumber = Int.random(in: 0...100)
            let textContent = generateRandomText()
            let originalXML = "<order indent=\"\(indent)\" inputNumber=\"\(inputNumber)\" />\(XMLEntityCodec.encode(textContent))"
            
            let document = try parser.parse(originalXML + "\n").value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML + "\n").value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let orderedList = document2.blocks.first as? OrderedListNode else {
                XCTFail("应该是 OrderedListNode 类型")
                continue
            }
            XCTAssertEqual(orderedList.indent, indent, "缩进应该保持不变")
            XCTAssertEqual(orderedList.inputNumber, inputNumber, "inputNumber 应该保持不变")
            XCTAssertEqual(extractPlainText(from: orderedList.content), textContent, "文本内容应该保持不变")
        }
    }
    
    /// 属性测试：复选框往返一致性
    /// _Requirements: 6.1, 6.3, 6.4_
    func testProperty1_CheckboxRoundTrip() throws {
        for _ in 0..<100 {
            let indent = Int.random(in: 1...10)
            let level = Int.random(in: 1...5)
            let isChecked = Bool.random()
            let textContent = generateRandomText()
            
            var originalXML = "<input type=\"checkbox\" indent=\"\(indent)\" level=\"\(level)\""
            if isChecked {
                originalXML += " checked=\"true\""
            }
            originalXML += " />\(XMLEntityCodec.encode(textContent))"
            
            let document = try parser.parse(originalXML + "\n").value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML + "\n").value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let checkbox = document2.blocks.first as? CheckboxNode else {
                XCTFail("应该是 CheckboxNode 类型")
                continue
            }
            XCTAssertEqual(checkbox.indent, indent, "缩进应该保持不变")
            XCTAssertEqual(checkbox.level, level, "level 应该保持不变")
            XCTAssertEqual(checkbox.isChecked, isChecked, "checked 状态应该保持不变")
            XCTAssertEqual(extractPlainText(from: checkbox.content), textContent, "文本内容应该保持不变")
        }
    }
    
    /// 属性测试：分割线往返一致性
    /// _Requirements: 6.1_
    func testProperty1_HorizontalRuleRoundTrip() throws {
        let originalXML = "<hr />"
        
        let document = try parser.parse(originalXML).value
        let generatedXML = generator.generate(document)
        let document2 = try parser.parse(generatedXML).value
        
        XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                     "往返后文档应该语义等价")
        XCTAssertTrue(document2.blocks.first is HorizontalRuleNode, "应该是 HorizontalRuleNode 类型")
    }
    
    /// 属性测试：图片往返一致性
    /// _Requirements: 6.1, 6.4_
    func testProperty1_ImageRoundTrip() throws {
        for _ in 0..<100 {
            let fileId = generateRandomFileId()
            let width = Int.random(in: 100...1000)
            let height = Int.random(in: 100...1000)
            
            let originalXML = "<img fileid=\"\(fileId)\" width=\"\(width)\" height=\"\(height)\" />"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let image = document2.blocks.first as? ImageNode else {
                XCTFail("应该是 ImageNode 类型")
                continue
            }
            XCTAssertEqual(image.fileId, fileId, "fileId 应该保持不变")
            XCTAssertEqual(image.width, width, "width 应该保持不变")
            XCTAssertEqual(image.height, height, "height 应该保持不变")
        }
    }
    
    /// 属性测试：音频往返一致性
    /// _Requirements: 6.1, 6.4_
    func testProperty1_AudioRoundTrip() throws {
        for _ in 0..<100 {
            let fileId = generateRandomFileId()
            let isTemporary = Bool.random()
            
            var originalXML = "<sound fileid=\"\(fileId)\""
            if isTemporary {
                originalXML += " temporary=\"true\""
            }
            originalXML += " />"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let audio = document2.blocks.first as? AudioNode else {
                XCTFail("应该是 AudioNode 类型")
                continue
            }
            XCTAssertEqual(audio.fileId, fileId, "fileId 应该保持不变")
            XCTAssertEqual(audio.isTemporary, isTemporary, "isTemporary 应该保持不变")
        }
    }
    
    /// 属性测试：引用块往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_QuoteRoundTrip() throws {
        for _ in 0..<100 {
            let blockCount = Int.random(in: 1...5)
            var innerXML = ""
            var expectedTexts: [String] = []
            
            for _ in 0..<blockCount {
                let text = generateRandomText()
                expectedTexts.append(text)
                innerXML += "<text indent=\"1\">\(XMLEntityCodec.encode(text))</text>\n"
            }
            
            let originalXML = "<quote>\(innerXML)</quote>"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let quote = document2.blocks.first as? QuoteNode else {
                XCTFail("应该是 QuoteNode 类型")
                continue
            }
            
            XCTAssertEqual(quote.textBlocks.count, blockCount, "内部文本块数量应该保持不变")
            
            for (index, textBlock) in quote.textBlocks.enumerated() {
                XCTAssertEqual(extractPlainText(from: textBlock.content), expectedTexts[index],
                              "文本内容应该保持不变")
            }
        }
    }

    
    /// 属性测试：带格式的文本往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_FormattedTextRoundTrip() throws {
        let formatTags = ["b", "i", "u", "delete", "size", "mid-size", "h3-size", "center", "right"]
        
        for _ in 0..<100 {
            let tag = formatTags.randomElement()!
            let textContent = generateRandomText()
            let originalXML = "<text indent=\"1\"><\(tag)>\(XMLEntityCodec.encode(textContent))</\(tag)></text>"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价\n原始: \(originalXML)\n生成: \(generatedXML)")
            
            guard let textBlock = document2.blocks.first as? TextBlockNode,
                  let formattedNode = textBlock.content.first as? FormattedNode else {
                XCTFail("应该有格式化节点")
                continue
            }
            
            XCTAssertEqual(extractPlainText(from: formattedNode.content), textContent, "文本内容应该保持不变")
        }
    }
    
    /// 属性测试：带高亮的文本往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_HighlightTextRoundTrip() throws {
        for _ in 0..<100 {
            let color = generateRandomColor()
            let textContent = generateRandomText()
            let originalXML = "<text indent=\"1\"><background color=\"\(color)\">\(XMLEntityCodec.encode(textContent))</background></text>"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let textBlock = document2.blocks.first as? TextBlockNode,
                  let highlightNode = textBlock.content.first as? FormattedNode else {
                XCTFail("应该有高亮节点")
                continue
            }
            
            XCTAssertEqual(highlightNode.nodeType, .highlight, "应该是高亮类型")
            XCTAssertEqual(highlightNode.color, color, "颜色应该保持不变")
            XCTAssertEqual(extractPlainText(from: highlightNode.content), textContent, "文本内容应该保持不变")
        }
    }
    
    /// 属性测试：嵌套格式往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_NestedFormatRoundTrip() throws {
        let formatPairs = [
            ("b", "i"),
            ("i", "u"),
            ("u", "delete"),
            ("size", "b"),
            ("center", "i")
        ]
        
        for _ in 0..<100 {
            let (outerTag, innerTag) = formatPairs.randomElement()!
            let textContent = generateRandomText()
            let originalXML = "<text indent=\"1\"><\(outerTag)><\(innerTag)>\(XMLEntityCodec.encode(textContent))</\(innerTag)></\(outerTag)></text>"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价\n原始: \(originalXML)\n生成: \(generatedXML)")
        }
    }
    
    /// 属性测试：特殊字符往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_SpecialCharactersRoundTrip() throws {
        for _ in 0..<100 {
            let textContent = generateRandomTextWithSpecialChars()
            let originalXML = "<text indent=\"1\">\(XMLEntityCodec.encode(textContent))</text>"
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            guard let textBlock = document2.blocks.first as? TextBlockNode else {
                XCTFail("应该是 TextBlockNode 类型")
                continue
            }
            
            XCTAssertEqual(extractPlainText(from: textBlock.content), textContent, "特殊字符应该正确保留")
        }
    }
    
    /// 属性测试：多行文档往返一致性
    /// _Requirements: 6.1, 6.3_
    func testProperty1_MultiLineDocumentRoundTrip() throws {
        for _ in 0..<50 {
            let lineCount = Int.random(in: 2...10)
            var lines: [String] = []
            var expectedTexts: [String] = []
            
            for _ in 0..<lineCount {
                let text = generateRandomText()
                expectedTexts.append(text)
                lines.append("<text indent=\"1\">\(XMLEntityCodec.encode(text))</text>")
            }
            
            let originalXML = lines.joined(separator: "\n")
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            XCTAssertEqual(document2.blocks.count, lineCount, "行数应该保持不变")
            
            for (index, block) in document2.blocks.enumerated() {
                guard let textBlock = block as? TextBlockNode else {
                    XCTFail("应该是 TextBlockNode 类型")
                    continue
                }
                XCTAssertEqual(extractPlainText(from: textBlock.content), expectedTexts[index],
                              "第 \(index + 1) 行文本应该保持不变")
            }
        }
    }
    
    /// 属性测试：混合块级元素往返一致性
    /// _Requirements: 6.1, 6.3, 6.4_
    func testProperty1_MixedBlocksRoundTrip() throws {
        for _ in 0..<50 {
            var lines: [String] = []
            
            // 添加文本块
            let text1 = generateRandomText()
            lines.append("<text indent=\"1\">\(XMLEntityCodec.encode(text1))</text>")
            
            // 添加无序列表
            let text2 = generateRandomText()
            lines.append("<bullet indent=\"1\" />\(XMLEntityCodec.encode(text2))")
            
            // 添加有序列表
            let text3 = generateRandomText()
            lines.append("<order indent=\"1\" inputNumber=\"0\" />\(XMLEntityCodec.encode(text3))")
            
            // 添加分割线
            lines.append("<hr />")
            
            // 添加复选框
            let text4 = generateRandomText()
            lines.append("<input type=\"checkbox\" indent=\"1\" level=\"1\" />\(XMLEntityCodec.encode(text4))")
            
            let originalXML = lines.joined(separator: "\n")
            
            let document = try parser.parse(originalXML).value
            let generatedXML = generator.generate(document)
            let document2 = try parser.parse(generatedXML).value
            
            XCTAssertTrue(areDocumentsSemanticEqual(document, document2),
                         "往返后文档应该语义等价")
            
            XCTAssertEqual(document2.blocks.count, 5, "应该有 5 个块级元素")
            XCTAssertTrue(document2.blocks[0] is TextBlockNode, "第 1 个应该是文本块")
            XCTAssertTrue(document2.blocks[1] is BulletListNode, "第 2 个应该是无序列表")
            XCTAssertTrue(document2.blocks[2] is OrderedListNode, "第 3 个应该是有序列表")
            XCTAssertTrue(document2.blocks[3] is HorizontalRuleNode, "第 4 个应该是分割线")
            XCTAssertTrue(document2.blocks[4] is CheckboxNode, "第 5 个应该是复选框")
        }
    }
    
    // MARK: - 辅助方法
    
    /// 生成随机文本（不包含 XML 特殊字符）
    private func generateRandomText() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789你好世界测试文本中文内容 "
        let length = Int.random(in: 1...50)
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// 生成包含特殊字符的随机文本
    private func generateRandomTextWithSpecialChars() -> String {
        let normalChars = "abcdefghijklmnopqrstuvwxyz0123456789你好 "
        let specialChars = "<>&\"'"
        let allChars = normalChars + specialChars
        let length = Int.random(in: 1...30)
        return String((0..<length).map { _ in allChars.randomElement()! })
    }
    
    /// 生成随机文件 ID
    private func generateRandomFileId() -> String {
        let prefix = String(Int.random(in: 1000000000...9999999999))
        let suffix = String((0..<22).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        return "\(prefix).\(suffix)"
    }
    
    /// 生成随机颜色值
    private func generateRandomColor() -> String {
        let r = String(format: "%02x", Int.random(in: 0...255))
        let g = String(format: "%02x", Int.random(in: 0...255))
        let b = String(format: "%02x", Int.random(in: 0...255))
        let a = String(format: "%02x", Int.random(in: 0...255))
        return "#\(r)\(g)\(b)\(a)"
    }
    
    /// 比较两个文档是否语义等价
    private func areDocumentsSemanticEqual(_ doc1: DocumentNode, _ doc2: DocumentNode) -> Bool {
        guard doc1.blocks.count == doc2.blocks.count else { return false }
        
        for (block1, block2) in zip(doc1.blocks, doc2.blocks) {
            if !areBlocksSemanticEqual(block1, block2) {
                return false
            }
        }
        
        return true
    }
    
    /// 比较两个块级节点是否语义等价
    private func areBlocksSemanticEqual(_ block1: any BlockNode, _ block2: any BlockNode) -> Bool {
        guard block1.nodeType == block2.nodeType else { return false }
        guard block1.indent == block2.indent else { return false }
        
        switch (block1, block2) {
        case let (t1, t2) as (TextBlockNode, TextBlockNode):
            return areInlineContentsEqual(t1.content, t2.content)
            
        case let (b1, b2) as (BulletListNode, BulletListNode):
            return areInlineContentsEqual(b1.content, b2.content)
            
        case let (o1, o2) as (OrderedListNode, OrderedListNode):
            return o1.inputNumber == o2.inputNumber && areInlineContentsEqual(o1.content, o2.content)
            
        case let (c1, c2) as (CheckboxNode, CheckboxNode):
            return c1.level == c2.level && c1.isChecked == c2.isChecked && areInlineContentsEqual(c1.content, c2.content)
            
        case is (HorizontalRuleNode, HorizontalRuleNode):
            return true
            
        case let (i1, i2) as (ImageNode, ImageNode):
            return i1.fileId == i2.fileId && i1.src == i2.src && i1.width == i2.width && i1.height == i2.height
            
        case let (a1, a2) as (AudioNode, AudioNode):
            return a1.fileId == a2.fileId && a1.isTemporary == a2.isTemporary
            
        case let (q1, q2) as (QuoteNode, QuoteNode):
            guard q1.textBlocks.count == q2.textBlocks.count else { return false }
            for (tb1, tb2) in zip(q1.textBlocks, q2.textBlocks) {
                if !areInlineContentsEqual(tb1.content, tb2.content) {
                    return false
                }
            }
            return true
            
        default:
            return false
        }
    }
    
    /// 比较两个行内内容数组是否等价
    private func areInlineContentsEqual(_ content1: [any InlineNode], _ content2: [any InlineNode]) -> Bool {
        // 提取纯文本进行比较（忽略格式结构差异，只比较最终文本和格式效果）
        let text1 = extractPlainText(from: content1)
        let text2 = extractPlainText(from: content2)
        
        guard text1 == text2 else { return false }
        
        // 比较格式结构
        guard content1.count == content2.count else { return false }
        
        for (node1, node2) in zip(content1, content2) {
            if !areInlineNodesEqual(node1, node2) {
                return false
            }
        }
        
        return true
    }
    
    /// 比较两个行内节点是否等价
    private func areInlineNodesEqual(_ node1: any InlineNode, _ node2: any InlineNode) -> Bool {
        guard node1.nodeType == node2.nodeType else { return false }
        
        switch (node1, node2) {
        case let (t1, t2) as (TextNode, TextNode):
            return t1.text == t2.text
            
        case let (f1, f2) as (FormattedNode, FormattedNode):
            guard f1.color == f2.color else { return false }
            return areInlineContentsEqual(f1.content, f2.content)
            
        default:
            return false
        }
    }
}
