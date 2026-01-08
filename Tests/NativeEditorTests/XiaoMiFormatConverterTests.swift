//
//  XiaoMiFormatConverterTests.swift
//  MiNoteMac
//
//  小米笔记格式转换器测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class XiaoMiFormatConverterTests: XCTestCase {
    
    var converter: XiaoMiFormatConverter!
    
    override func setUpWithError() throws {
        converter = XiaoMiFormatConverter.shared
    }
    
    override func tearDownWithError() throws {
        converter = nil
    }
    
    // MARK: - 基础转换测试
    
    func testEmptyXMLConversion() throws {
        let emptyXML = ""
        let result = try converter.xmlToAttributedString(emptyXML)
        XCTAssertTrue(result.characters.isEmpty, "空 XML 应该转换为空 AttributedString")
    }
    
    func testSimpleTextConversion() throws {
        let xml = "<text indent=\"1\">测试文本</text>"
        let result = try converter.xmlToAttributedString(xml)
        XCTAssertEqual(String(result.characters), "测试文本", "简单文本应该正确转换")
    }
    
    func testTextWithIndentConversion() throws {
        let xml = "<text indent=\"2\">缩进文本</text>"
        let result = try converter.xmlToAttributedString(xml)
        
        // 检查段落样式是否正确设置缩进
        let paragraphStyle = result.runs.first?.paragraphStyle
        XCTAssertNotNil(paragraphStyle, "应该有段落样式")
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 20.0, "缩进应该正确设置")
    }
    
    // MARK: - 往返转换测试
    
    func testRoundTripConversion() throws {
        let originalXML = "<text indent=\"1\">测试文本</text>"
        
        // XML -> AttributedString -> XML
        let attributedString = try converter.xmlToAttributedString(originalXML)
        let convertedXML = try converter.attributedStringToXML(attributedString)
        
        XCTAssertTrue(converter.validateConversion(originalXML), "往返转换应该保持一致性")
    }
    
    func testComplexRoundTripConversion() throws {
        let complexXML = """
        <text indent="1"><b>加粗文本</b></text>
        <text indent="1"><i>斜体文本</i></text>
        <text indent="2">缩进文本</text>
        """
        
        XCTAssertTrue(converter.validateConversion(complexXML), "复杂 XML 往返转换应该保持一致性")
    }
    
    // MARK: - 错误处理测试
    
    func testInvalidXMLHandling() {
        let invalidXML = "<invalid>无效的 XML</invalid>"
        
        XCTAssertThrowsError(try converter.xmlToAttributedString(invalidXML)) { error in
            XCTAssertTrue(error is ConversionError, "应该抛出 ConversionError")
        }
    }
    
    func testMalformedXMLHandling() {
        let malformedXML = "<text indent=\"1\">未闭合的标签"
        
        XCTAssertThrowsError(try converter.xmlToAttributedString(malformedXML)) { error in
            XCTAssertTrue(error is ConversionError, "应该抛出 ConversionError")
        }
    }
    
    // MARK: - 特殊标签处理测试
    
    /// 测试 <new-format/> 标签应该被忽略
    func testNewFormatTagIgnored() throws {
        // 测试只有 <new-format/> 标签的情况
        let xmlWithNewFormat = "<new-format/>"
        let result1 = try converter.xmlToAttributedString(xmlWithNewFormat)
        XCTAssertTrue(result1.characters.isEmpty, "<new-format/> 标签应该被忽略，结果为空")
        
        // 测试 <new-format/> 在内容前面的情况
        let xmlWithNewFormatAndContent = """
        <new-format/>
        <text indent="1"><size>测试标题一</size></text>
        """
        let result2 = try converter.xmlToAttributedString(xmlWithNewFormatAndContent)
        XCTAssertEqual(String(result2.characters), "测试标题一", "<new-format/> 标签应该被忽略，只保留实际内容")
        
        // 测试 <new-format/> 在内容中间的情况
        let xmlWithNewFormatInMiddle = """
        <text indent="1">第一行</text>
        <new-format/>
        <text indent="1">第二行</text>
        """
        let result3 = try converter.xmlToAttributedString(xmlWithNewFormatInMiddle)
        XCTAssertEqual(String(result3.characters), "第一行\n第二行", "<new-format/> 标签在中间应该被忽略")
    }
    
    // MARK: - 对齐方式测试
    
    /// 测试居中对齐标签
    func testCenterAlignmentConversion() throws {
        let xml = "<text indent=\"1\"><center>居中文本</center></text>"
        let result = try converter.xmlToAttributedString(xml)
        
        // 检查文本内容
        XCTAssertEqual(String(result.characters), "居中文本", "居中文本内容应该正确")
        
        // 检查段落样式的对齐方式
        let paragraphStyle = result.runs.first?.paragraphStyle
        XCTAssertNotNil(paragraphStyle, "应该有段落样式")
        XCTAssertEqual(paragraphStyle?.alignment, .center, "对齐方式应该是居中")
    }
    
    /// 测试右对齐标签
    func testRightAlignmentConversion() throws {
        let xml = "<text indent=\"1\"><right>右对齐文本</right></text>"
        let result = try converter.xmlToAttributedString(xml)
        
        // 检查文本内容
        XCTAssertEqual(String(result.characters), "右对齐文本", "右对齐文本内容应该正确")
        
        // 检查段落样式的对齐方式
        let paragraphStyle = result.runs.first?.paragraphStyle
        XCTAssertNotNil(paragraphStyle, "应该有段落样式")
        XCTAssertEqual(paragraphStyle?.alignment, .right, "对齐方式应该是右对齐")
    }
    
    /// 测试居中对齐与缩进同时存在
    func testCenterAlignmentWithIndent() throws {
        let xml = "<text indent=\"2\"><center>居中且缩进的文本</center></text>"
        let result = try converter.xmlToAttributedString(xml)
        
        // 检查段落样式
        let paragraphStyle = result.runs.first?.paragraphStyle
        XCTAssertNotNil(paragraphStyle, "应该有段落样式")
        XCTAssertEqual(paragraphStyle?.alignment, .center, "对齐方式应该是居中")
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 20.0, "缩进应该正确设置")
    }
    
    /// 测试右对齐与缩进同时存在
    func testRightAlignmentWithIndent() throws {
        let xml = "<text indent=\"3\"><right>右对齐且缩进的文本</right></text>"
        let result = try converter.xmlToAttributedString(xml)
        
        // 检查段落样式
        let paragraphStyle = result.runs.first?.paragraphStyle
        XCTAssertNotNil(paragraphStyle, "应该有段落样式")
        XCTAssertEqual(paragraphStyle?.alignment, .right, "对齐方式应该是右对齐")
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 40.0, "缩进应该正确设置（indent=3 对应 40px）")
    }
    
    /// 测试默认左对齐
    func testDefaultLeftAlignment() throws {
        let xml = "<text indent=\"1\">普通文本</text>"
        let result = try converter.xmlToAttributedString(xml)
        
        // 检查段落样式的对齐方式
        let paragraphStyle = result.runs.first?.paragraphStyle
        XCTAssertNotNil(paragraphStyle, "应该有段落样式")
        XCTAssertEqual(paragraphStyle?.alignment, .left, "默认对齐方式应该是左对齐")
    }
    
    // MARK: - 性能测试
    
    func testConversionPerformance() {
        let largeXML = String(repeating: "<text indent=\"1\">测试文本</text>\n", count: 1000)
        
        measure {
            do {
                let _ = try converter.xmlToAttributedString(largeXML)
            } catch {
                XCTFail("转换不应该失败: \(error)")
            }
        }
    }
    
    func testRoundTripPerformance() {
        let xml = "<text indent=\"1\">性能测试文本</text>"
        
        measure {
            XCTAssertTrue(converter.validateConversion(xml), "往返转换验证应该成功")
        }
    }
}