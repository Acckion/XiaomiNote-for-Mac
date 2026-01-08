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