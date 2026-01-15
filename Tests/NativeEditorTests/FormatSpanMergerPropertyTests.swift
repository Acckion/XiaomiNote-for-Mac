//
//  FormatSpanMergerPropertyTests.swift
//  MiNoteMac
//
//  格式跨度合并属性测试
//  Property 4: 格式跨度合并正确性 
//

import XCTest
@testable import MiNoteLibrary

/// 格式跨度合并属性测试
/// Feature: xml-attributedstring-converter, Property 4: 格式跨度合并正确性
/// *For any* 包含相邻相同格式文本的 NSAttributedString，转换为 AST 后，
/// 相邻的相同格式文本应该被合并为单个格式节点，生成的 XML 不应包含冗余的闭合/开启标签序列。
final class FormatSpanMergerPropertyTests: XCTestCase {
    
    var merger: FormatSpanMerger!
    
    override func setUp() {
        super.setUp()
        merger = FormatSpanMerger()
    }
    
    override func tearDown() {
        merger = nil
        super.tearDown()
    }
    
    // MARK: - Property 4: 格式跨度合并正确性
    
    /// 属性测试：相邻相同格式跨度应该被合并
    /// *For any* 相邻的相同格式跨度，合并后应该只有一个跨度
    /// _Requirements: 5.1_
    func testProperty4_AdjacentSameFormatSpansMerge() {
        for _ in 0..<100 {
            // 生成随机格式集合
            let formats = generateRandomFormats()
            let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
            
            // 生成多个相同格式的跨度
            let spanCount = Int.random(in: 2...10)
            var spans: [FormatSpan] = []
            var expectedText = ""
            
            for _ in 0..<spanCount {
                let text = generateRandomText()
                expectedText += text
                spans.append(FormatSpan(text: text, formats: formats, highlightColor: highlightColor))
            }
            
            // 合并
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该只有一个跨度
            XCTAssertEqual(mergedSpans.count, 1, "相同格式的相邻跨度应该合并为一个")
            
            // 验证：文本内容应该是所有跨度的拼接
            XCTAssertEqual(mergedSpans.first?.text, expectedText, "合并后的文本应该是所有跨度的拼接")
            
            // 验证：格式应该保持不变
            XCTAssertEqual(mergedSpans.first?.formats, formats, "合并后的格式应该保持不变")
            
            // 验证：高亮颜色应该保持不变
            XCTAssertEqual(mergedSpans.first?.highlightColor, highlightColor, "合并后的高亮颜色应该保持不变")
        }
    }
    
    /// 属性测试：不同格式跨度不应该被合并
    /// *For any* 相邻的不同格式跨度，合并后应该保持分离
    /// _Requirements: 5.1_
    func testProperty4_DifferentFormatSpansNotMerge() {
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
            
            let spans = [
                FormatSpan(text: text1, formats: formats1),
                FormatSpan(text: text2, formats: formats2)
            ]
            
            // 合并
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该保持两个跨度
            XCTAssertEqual(mergedSpans.count, 2, "不同格式的跨度不应该合并")
            
            // 验证：每个跨度的内容和格式应该保持不变
            XCTAssertEqual(mergedSpans[0].text, text1, "第一个跨度的文本应该保持不变")
            XCTAssertEqual(mergedSpans[0].formats, formats1, "第一个跨度的格式应该保持不变")
            XCTAssertEqual(mergedSpans[1].text, text2, "第二个跨度的文本应该保持不变")
            XCTAssertEqual(mergedSpans[1].formats, formats2, "第二个跨度的格式应该保持不变")
        }
    }
    
    /// 属性测试：高亮颜色不同的跨度不应该合并
    /// *For any* 相邻的高亮跨度，如果颜色不同，不应该合并
    /// _Requirements: 5.1_
    func testProperty4_DifferentHighlightColorNotMerge() {
        for _ in 0..<100 {
            let formats: Set<ASTNodeType> = [.highlight]
            let color1 = generateRandomColor()
            var color2 = generateRandomColor()
            
            // 确保两个颜色不同
            while color1 == color2 {
                color2 = generateRandomColor()
            }
            
            let text1 = generateRandomText()
            let text2 = generateRandomText()
            
            let spans = [
                FormatSpan(text: text1, formats: formats, highlightColor: color1),
                FormatSpan(text: text2, formats: formats, highlightColor: color2)
            ]
            
            // 合并
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该保持两个跨度
            XCTAssertEqual(mergedSpans.count, 2, "不同颜色的高亮跨度不应该合并")
        }
    }
    
    /// 属性测试：合并后文本内容完整性
    /// *For any* 跨度数组，合并后的总文本应该等于原始总文本
    /// _Requirements: 5.1, 5.3_
    func testProperty4_MergePreservesTextContent() {
        for _ in 0..<100 {
            // 生成随机跨度数组
            let spanCount = Int.random(in: 1...20)
            var spans: [FormatSpan] = []
            var expectedTotalText = ""
            
            for _ in 0..<spanCount {
                let text = generateRandomText()
                let formats = generateRandomFormats()
                let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
                
                expectedTotalText += text
                spans.append(FormatSpan(text: text, formats: formats, highlightColor: highlightColor))
            }
            
            // 合并
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：总文本应该保持不变
            let actualTotalText = mergedSpans.map { $0.text }.joined()
            XCTAssertEqual(actualTotalText, expectedTotalText, "合并后的总文本应该等于原始总文本")
        }
    }
    
    /// 属性测试：合并后跨度数量不增加
    /// *For any* 跨度数组，合并后的跨度数量应该小于等于原始数量
    /// _Requirements: 5.1_
    func testProperty4_MergeReducesOrMaintainsSpanCount() {
        for _ in 0..<100 {
            // 生成随机跨度数组
            let spanCount = Int.random(in: 1...20)
            var spans: [FormatSpan] = []
            
            for _ in 0..<spanCount {
                let text = generateRandomText()
                let formats = generateRandomFormats()
                let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
                spans.append(FormatSpan(text: text, formats: formats, highlightColor: highlightColor))
            }
            
            // 合并
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：合并后数量应该小于等于原始数量
            XCTAssertLessThanOrEqual(mergedSpans.count, spans.count,
                                     "合并后的跨度数量应该小于等于原始数量")
        }
    }
    
    /// 属性测试：空跨度数组合并
    /// _Requirements: 5.1_
    func testProperty4_EmptySpansArrayMerge() {
        let spans: [FormatSpan] = []
        let mergedSpans = merger.mergeAdjacentSpans(spans)
        
        XCTAssertTrue(mergedSpans.isEmpty, "空数组合并后应该仍然为空")
    }
    
    /// 属性测试：单个跨度合并
    /// _Requirements: 5.1_
    func testProperty4_SingleSpanMerge() {
        for _ in 0..<100 {
            let text = generateRandomText()
            let formats = generateRandomFormats()
            let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
            
            let spans = [FormatSpan(text: text, formats: formats, highlightColor: highlightColor)]
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            XCTAssertEqual(mergedSpans.count, 1, "单个跨度合并后应该仍然是一个")
            XCTAssertEqual(mergedSpans.first?.text, text, "文本应该保持不变")
            XCTAssertEqual(mergedSpans.first?.formats, formats, "格式应该保持不变")
        }
    }
    
    /// 属性测试：交替格式跨度合并
    /// *For any* 交替格式的跨度序列（A-B-A-B），合并后应该保持交替
    /// _Requirements: 5.1_
    func testProperty4_AlternatingFormatsMerge() {
        for _ in 0..<100 {
            let formats1: Set<ASTNodeType> = [.bold]
            let formats2: Set<ASTNodeType> = [.italic]
            
            let pairCount = Int.random(in: 2...5)
            var spans: [FormatSpan] = []
            
            for i in 0..<(pairCount * 2) {
                let text = generateRandomText()
                let formats = (i % 2 == 0) ? formats1 : formats2
                spans.append(FormatSpan(text: text, formats: formats))
            }
            
            // 合并
            let mergedSpans = merger.mergeAdjacentSpans(spans)
            
            // 验证：应该保持交替，数量不变
            XCTAssertEqual(mergedSpans.count, pairCount * 2, "交替格式的跨度不应该合并")
            
            // 验证：格式应该交替
            for (index, span) in mergedSpans.enumerated() {
                let expectedFormats = (index % 2 == 0) ? formats1 : formats2
                XCTAssertEqual(span.formats, expectedFormats, "格式应该保持交替")
            }
        }
    }
    
    // MARK: - 跨度与节点转换测试
    
    /// 属性测试：跨度转节点再转回跨度应该等价
    /// *For any* 跨度数组，转换为节点再转回跨度后，合并结果应该等价
    /// _Requirements: 5.1, 5.3_
    func testProperty4_SpanToNodeRoundTrip() {
        for _ in 0..<100 {
            // 生成随机跨度数组
            let spanCount = Int.random(in: 1...10)
            var spans: [FormatSpan] = []
            
            for _ in 0..<spanCount {
                let text = generateRandomText()
                let formats = generateRandomFormats()
                let highlightColor = formats.contains(.highlight) ? generateRandomColor() : nil
                spans.append(FormatSpan(text: text, formats: formats, highlightColor: highlightColor))
            }
            
            // 先合并原始跨度
            let mergedOriginal = merger.mergeAdjacentSpans(spans)
            
            // 转换为节点
            let nodes = merger.spansToInlineNodes(spans)
            
            // 转回跨度
            let convertedSpans = merger.inlineNodesToSpans(nodes)
            
            // 合并转换后的跨度
            let mergedConverted = merger.mergeAdjacentSpans(convertedSpans)
            
            // 验证：合并后应该等价
            XCTAssertEqual(mergedOriginal.count, mergedConverted.count, "往返后跨度数量应该相同")
            
            for (original, converted) in zip(mergedOriginal, mergedConverted) {
                XCTAssertEqual(original.text, converted.text, "文本应该相同")
                XCTAssertEqual(original.formats, converted.formats, "格式应该相同")
                XCTAssertEqual(original.highlightColor, converted.highlightColor, "高亮颜色应该相同")
            }
        }
    }
    
    /// 属性测试：节点优化保持文本内容
    /// *For any* 行内节点数组，优化后的文本内容应该保持不变
    /// _Requirements: 5.1, 5.3_
    func testProperty4_OptimizePreservesTextContent() {
        for _ in 0..<100 {
            // 生成随机节点
            let nodes = generateRandomInlineNodes()
            
            // 提取原始文本
            let originalText = merger.extractPlainText(nodes)
            
            // 优化
            let optimizedNodes = merger.optimizeInlineNodes(nodes)
            
            // 提取优化后的文本
            let optimizedText = merger.extractPlainText(optimizedNodes)
            
            // 验证：文本应该保持不变
            XCTAssertEqual(originalText, optimizedText, "优化后的文本内容应该保持不变")
        }
    }
    
    /// 属性测试：节点优化减少或保持节点数量
    /// *For any* 行内节点数组，优化后的节点数量应该小于等于原始数量
    /// _Requirements: 5.1_
    func testProperty4_OptimizeReducesOrMaintainsNodeCount() {
        for _ in 0..<100 {
            // 生成随机节点
            let nodes = generateRandomInlineNodes()
            
            // 优化
            let optimizedNodes = merger.optimizeInlineNodes(nodes)
            
            // 验证：优化后数量应该小于等于原始数量
            XCTAssertLessThanOrEqual(optimizedNodes.count, nodes.count,
                                     "优化后的节点数量应该小于等于原始数量")
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
    
    /// 生成随机颜色值
    private func generateRandomColor() -> String {
        let r = String(format: "%02x", Int.random(in: 0...255))
        let g = String(format: "%02x", Int.random(in: 0...255))
        let b = String(format: "%02x", Int.random(in: 0...255))
        let a = String(format: "%02x", Int.random(in: 0...255))
        return "#\(r)\(g)\(b)\(a)"
    }
    
    /// 生成随机行内节点数组
    private func generateRandomInlineNodes() -> [any InlineNode] {
        let nodeCount = Int.random(in: 1...10)
        var nodes: [any InlineNode] = []
        
        for _ in 0..<nodeCount {
            let text = generateRandomText()
            let formats = generateRandomFormats()
            
            if formats.isEmpty {
                nodes.append(TextNode(text: text))
            } else {
                var node: any InlineNode = TextNode(text: text)
                
                for format in formats {
                    let color = (format == .highlight) ? generateRandomColor() : nil
                    node = FormattedNode(type: format, content: [node], color: color)
                }
                
                nodes.append(node)
            }
        }
        
        return nodes
    }
}
