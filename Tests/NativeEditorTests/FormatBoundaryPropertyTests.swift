//
//  FormatBoundaryPropertyTests.swift
//  MiNoteMac
//
//  格式边界处理属性测试
//  Property 5: 格式边界处理正确性 
//

import XCTest
@testable import MiNoteLibrary

/// 格式边界处理属性测试
/// Feature: xml-attributedstring-converter, Property 5: 格式边界处理正确性
/// *For any* 格式化文本，在其末尾添加新内容后转换为 XML，
/// 不应产生多余的格式标签（如 `</b></i><i><b>`），
/// 新内容应该正确继承或不继承前面的格式。
final class FormatBoundaryPropertyTests: XCTestCase {
    
    var merger: FormatSpanMerger!
    var generator: XMLGenerator!
    
    override func setUp() {
        super.setUp()
        merger = FormatSpanMerger()
        generator = XMLGenerator()
    }
    
    override func tearDown() {
        merger = nil
        generator = nil
        super.tearDown()
    }
    
    // MARK: - Property 5: 格式边界处理正确性
    
    /// 属性测试：在格式化文本末尾添加相同格式内容不产生冗余标签
    /// *For any* 格式化文本，在末尾添加相同格式的内容后，
    /// 生成的 XML 不应包含冗余的闭合/开启标签序列（如 `</b><b>`）
    /// _Requirements: 5.3_
    func testProperty5_AppendSameFormatNoRedundantTags() {
        for _ in 0..<100 {
            // 生成随机格式
            let formats = generateRandomFormats()
            guard !formats.isEmpty else { continue }
            
            let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
            
            // 生成原始文本和追加文本
            let originalText = generateRandomText()
            let appendedText = generateRandomText()
            
            // 创建两个相同格式的跨度（模拟用户在格式化文本末尾添加内容）
            let spans = [
                FormatSpan(text: originalText, formats: formats, highlightColor: highlightColor),
                FormatSpan(text: appendedText, formats: formats, highlightColor: highlightColor)
            ]
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该合并为一个跨度
            XCTAssertEqual(mergedSpans.count, 1, 
                          "相同格式的相邻跨度应该合并为一个，避免产生冗余标签")
            
            // 验证：文本内容正确
            XCTAssertEqual(mergedSpans.first?.text, originalText + appendedText,
                          "合并后的文本应该是原始文本和追加文本的拼接")
            
            // 转换为节点并生成 XML
            let nodes = merger.spansToInlineNodes(mergedSpans)
            let document = DocumentNode(blocks: [
                TextBlockNode(indent: 1, content: nodes)
            ])
            let xml = generator.generate(document)
            
            // 验证：XML 不应包含冗余的闭合/开启标签序列
            assertNoRedundantTags(xml, formats: formats)
        }
    }
    
    /// 属性测试：在格式化文本末尾添加不同格式内容正确分离
    /// *For any* 格式化文本，在末尾添加不同格式的内容后，
    /// 应该正确分离为两个不同的格式节点
    /// _Requirements: 5.4_
    func testProperty5_AppendDifferentFormatCorrectSeparation() {
        for _ in 0..<100 {
            // 生成两个不同的格式集合
            let formats1 = generateRandomFormats()
            var formats2 = generateRandomFormats()
            
            // 确保两个格式集合不同
            while formats1 == formats2 {
                formats2 = generateRandomFormats()
            }
            
            let text1 = generateRandomText()
            let text2 = generateRandomText()
            
            // 创建两个不同格式的跨度
            let spans = [
                FormatSpan(text: text1, formats: formats1),
                FormatSpan(text: text2, formats: formats2)
            ]
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该保持两个跨度
            XCTAssertEqual(mergedSpans.count, 2, 
                          "不同格式的跨度不应该合并")
            
            // 验证：每个跨度的内容和格式正确
            XCTAssertEqual(mergedSpans[0].text, text1)
            XCTAssertEqual(mergedSpans[0].formats, formats1)
            XCTAssertEqual(mergedSpans[1].text, text2)
            XCTAssertEqual(mergedSpans[1].formats, formats2)
        }
    }
    
    /// 属性测试：在格式化文本中间插入不同格式内容正确拆分
    /// *For any* 格式化文本，在中间插入不同格式的内容后，
    /// 应该正确拆分为三个部分：前半部分、插入内容、后半部分
    /// _Requirements: 5.4_
    func testProperty5_InsertDifferentFormatCorrectSplit() {
        for _ in 0..<100 {
            // 生成原始格式和插入格式
            let originalFormats = generateRandomFormats()
            var insertFormats = generateRandomFormats()
            
            // 确保两个格式集合不同
            while originalFormats == insertFormats {
                insertFormats = generateRandomFormats()
            }
            
            let beforeText = generateRandomText()
            let insertText = generateRandomText()
            let afterText = generateRandomText()
            
            // 创建三个跨度（模拟在中间插入不同格式内容）
            let spans = [
                FormatSpan(text: beforeText, formats: originalFormats),
                FormatSpan(text: insertText, formats: insertFormats),
                FormatSpan(text: afterText, formats: originalFormats)
            ]
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该保持三个跨度（因为中间格式不同）
            XCTAssertEqual(mergedSpans.count, 3, 
                          "在中间插入不同格式内容应该保持三个跨度")
            
            // 验证：每个跨度的内容和格式正确
            XCTAssertEqual(mergedSpans[0].text, beforeText)
            XCTAssertEqual(mergedSpans[0].formats, originalFormats)
            XCTAssertEqual(mergedSpans[1].text, insertText)
            XCTAssertEqual(mergedSpans[1].formats, insertFormats)
            XCTAssertEqual(mergedSpans[2].text, afterText)
            XCTAssertEqual(mergedSpans[2].formats, originalFormats)
        }
    }
    
    /// 属性测试：格式边界处理后文本内容完整性
    /// *For any* 格式化文本操作，处理后的总文本应该保持不变
    /// _Requirements: 5.3, 5.4_
    func testProperty5_BoundaryHandlingPreservesTextContent() {
        for _ in 0..<100 {
            // 生成随机跨度数组（模拟各种编辑操作后的状态）
            let spanCount = Int.random(in: 1...10)
            var spans: [FormatSpan] = []
            var expectedTotalText = ""
            
            for _ in 0..<spanCount {
                let text = generateRandomText()
                let formats = generateRandomFormats()
                let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
                
                expectedTotalText += text
                spans.append(FormatSpan(text: text, formats: formats, highlightColor: highlightColor))
            }
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：总文本应该保持不变
            let actualTotalText = mergedSpans.map { $0.text }.joined()
            XCTAssertEqual(actualTotalText, expectedTotalText, 
                          "格式边界处理后的总文本应该保持不变")
            
            // 转换为节点
            let nodes = merger.spansToInlineNodes(mergedSpans)
            
            // 验证：节点的总文本也应该保持不变
            let nodeText = merger.extractPlainText(nodes)
            XCTAssertEqual(nodeText, expectedTotalText,
                          "转换为节点后的总文本应该保持不变")
        }
    }
    
    /// 属性测试：嵌套格式边界处理正确性
    /// *For any* 嵌套格式文本，在边界处添加内容后，
    /// 应该正确处理嵌套关系
    /// _Requirements: 5.3, 5.4_
    func testProperty5_NestedFormatBoundaryHandling() {
        for _ in 0..<100 {
            // 生成嵌套格式（多个格式组合）
            let nestedFormats = generateNestedFormats()
            guard nestedFormats.count >= 2 else { continue }
            
            let text1 = generateRandomText()
            let text2 = generateRandomText()
            
            // 创建两个相同嵌套格式的跨度
            let spans = [
                FormatSpan(text: text1, formats: nestedFormats),
                FormatSpan(text: text2, formats: nestedFormats)
            ]
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该合并为一个跨度
            XCTAssertEqual(mergedSpans.count, 1,
                          "相同嵌套格式的相邻跨度应该合并为一个")
            
            // 转换为节点
            let nodes = merger.spansToInlineNodes(mergedSpans)
            
            // 验证：节点结构正确（应该有嵌套的格式节点）
            XCTAssertEqual(nodes.count, 1, "应该只有一个顶层节点")
            
            // 验证：文本内容正确
            let nodeText = merger.extractPlainText(nodes)
            XCTAssertEqual(nodeText, text1 + text2,
                          "嵌套格式节点的文本内容应该正确")
        }
    }
    
    /// 属性测试：部分格式重叠边界处理
    /// *For any* 部分格式重叠的文本，应该正确处理边界
    /// _Requirements: 5.4_
    func testProperty5_PartialFormatOverlapBoundary() {
        for _ in 0..<100 {
            // 生成基础格式
            let baseFormat: Set<ASTNodeType> = [.bold]
            let extendedFormat: Set<ASTNodeType> = [.bold, .italic]
            
            let text1 = generateRandomText()
            let text2 = generateRandomText()
            let text3 = generateRandomText()
            
            // 创建部分格式重叠的跨度
            // 例如：粗体 → 粗斜体 → 粗体
            let spans = [
                FormatSpan(text: text1, formats: baseFormat),
                FormatSpan(text: text2, formats: extendedFormat),
                FormatSpan(text: text3, formats: baseFormat)
            ]
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该保持三个跨度（因为格式不完全相同）
            XCTAssertEqual(mergedSpans.count, 3,
                          "部分格式重叠的跨度不应该合并")
            
            // 验证：每个跨度的格式正确
            XCTAssertEqual(mergedSpans[0].formats, baseFormat)
            XCTAssertEqual(mergedSpans[1].formats, extendedFormat)
            XCTAssertEqual(mergedSpans[2].formats, baseFormat)
        }
    }
    
    /// 属性测试：空文本跨度边界处理
    /// *For any* 包含空文本跨度的序列，合并后应该正确处理
    /// _Requirements: 5.3_
    func testProperty5_EmptyTextSpanBoundary() {
        for _ in 0..<100 {
            let formats = generateRandomFormats()
            let text1 = generateRandomText()
            let text2 = generateRandomText()
            
            // 创建包含空文本跨度的序列
            let spans = [
                FormatSpan(text: text1, formats: formats),
                FormatSpan(text: "", formats: formats),  // 空文本跨度
                FormatSpan(text: text2, formats: formats)
            ]
            
            // 合并跨度
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：空跨度应该被过滤，相同格式应该合并
            // 合并后应该只有一个跨度（如果格式相同）
            XCTAssertEqual(mergedSpans.count, 1,
                          "相同格式的跨度应该合并，空跨度应该被过滤")
            
            // 验证：文本内容正确（不包含空文本）
            XCTAssertEqual(mergedSpans.first?.text, text1 + text2,
                          "合并后的文本应该是非空文本的拼接")
        }
    }
    
    /// 属性测试：生成的 XML 格式标签顺序正确
    /// *For any* 多格式文本，生成的 XML 标签应该按照正确的嵌套顺序
    /// _Requirements: 5.3_
    func testProperty5_XMLTagOrderCorrect() {
        for _ in 0..<100 {
            // 生成包含多个格式的跨度
            let formats = generateNestedFormats()
            guard formats.count >= 2 else { continue }
            
            let text = generateRandomText()
            let spans = [FormatSpan(text: text, formats: formats)]
            
            // 转换为节点
            let nodes = merger.spansToInlineNodes(spans)
            
            // 生成 XML
            let document = DocumentNode(blocks: [
                TextBlockNode(indent: 1, content: nodes)
            ])
            let xml = generator.generate(document)
            
            // 验证：标签顺序正确（外层标签应该先出现）
            assertTagOrderCorrect(xml, formats: formats)
        }
    }
    
    // MARK: - 辅助方法
    
    /// 生成随机文本
    private func generateRandomText() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789你好世界测试 "
        let length = Int.random(in: 1...20)
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// 生成随机格式集合
    private func generateRandomFormats() -> Set<ASTNodeType> {
        let allFormats: [ASTNodeType] = [
            .bold, .italic, .underline, .strikethrough, .highlight,
            .heading1, .heading2, .heading3, .centerAlign, .rightAlign
        ]
        
        // 随机选择 0-3 个格式
        let count = Int.random(in: 0...3)
        var formats: Set<ASTNodeType> = []
        
        for _ in 0..<count {
            if let format = allFormats.randomElement() {
                formats.insert(format)
            }
        }
        
        return formats
    }
    
    /// 生成嵌套格式（至少包含 2 个格式）
    private func generateNestedFormats() -> Set<ASTNodeType> {
        let allFormats: [ASTNodeType] = [
            .bold, .italic, .underline, .strikethrough
        ]
        
        // 随机选择 2-4 个格式
        let count = Int.random(in: 2...4)
        var formats: Set<ASTNodeType> = []
        
        var availableFormats = allFormats
        for _ in 0..<count {
            if let index = availableFormats.indices.randomElement() {
                formats.insert(availableFormats.remove(at: index))
            }
        }
        
        return formats
    }
    
    /// 生成随机颜色值
    private func generateRandomColor() -> String {
        let r = String(format: "%02x", Int.random(in: 0...255))
        let g = String(format: "%02x", Int.random(in: 0...255))
        let b = String(format: "%02x", Int.random(in: 0...255))
        let a = String(format: "%02x", Int.random(in: 0...255))
        return "#\(r)\(g)\(b)\(a)"
    }
    
    /// 验证 XML 不包含冗余的闭合/开启标签序列
    private func assertNoRedundantTags(_ xml: String, formats: Set<ASTNodeType>) {
        // 检查常见的冗余标签模式
        let redundantPatterns = [
            "</b><b>",
            "</i><i>",
            "</u><u>",
            "</delete><delete>",
            "</size><size>",
            "</mid-size><mid-size>",
            "</h3-size><h3-size>",
            "</center><center>",
            "</right><right>"
        ]
        
        for pattern in redundantPatterns {
            XCTAssertFalse(xml.contains(pattern),
                          "XML 不应包含冗余的标签序列: \(pattern)")
        }
        
        // 检查更复杂的冗余模式（如 </b></i><i><b>）
        let complexPatterns = [
            "</b></i><i><b>",
            "</i></b><b><i>",
            "</u></b><b></u>",
            "</delete></b><b><delete>"
        ]
        
        for pattern in complexPatterns {
            XCTAssertFalse(xml.contains(pattern),
                          "XML 不应包含复杂的冗余标签序列: \(pattern)")
        }
    }
    
    /// 验证 XML 标签顺序正确
    private func assertTagOrderCorrect(_ xml: String, formats: Set<ASTNodeType>) {
        // 格式标签的正确嵌套顺序（从外到内）
        let formatOrder: [ASTNodeType] = [
            .heading1, .heading2, .heading3,
            .centerAlign, .rightAlign,
            .highlight,
            .strikethrough,
            .underline,
            .italic,
            .bold
        ]
        
        // 获取格式对应的标签名
        let tagNames: [ASTNodeType: String] = [
            .bold: "b",
            .italic: "i",
            .underline: "u",
            .strikethrough: "delete",
            .highlight: "background",
            .heading1: "size",
            .heading2: "mid-size",
            .heading3: "h3-size",
            .centerAlign: "center",
            .rightAlign: "right"
        ]
        
        // 找出 XML 中各标签的位置
        var tagPositions: [(ASTNodeType, Int)] = []
        
        for format in formats {
            if let tagName = tagNames[format] {
                if let range = xml.range(of: "<\(tagName)") {
                    let position = xml.distance(from: xml.startIndex, to: range.lowerBound)
                    tagPositions.append((format, position))
                }
            }
        }
        
        // 按位置排序
        tagPositions.sort { $0.1 < $1.1 }
        
        // 验证顺序符合 formatOrder
        for i in 0..<tagPositions.count {
            for j in (i+1)..<tagPositions.count {
                let format1 = tagPositions[i].0
                let format2 = tagPositions[j].0
                
                if let index1 = formatOrder.firstIndex(of: format1),
                   let index2 = formatOrder.firstIndex(of: format2) {
                    // format1 应该在 format2 之前（外层）
                    XCTAssertLessThanOrEqual(index1, index2,
                                            "标签 \(format1) 应该在 \(format2) 外层")
                }
            }
        }
    }
}
