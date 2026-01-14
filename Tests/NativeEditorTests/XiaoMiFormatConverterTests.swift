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
    
    // MARK: - 复选框状态保留测试
    
    /// 测试未选中复选框的解析和导出
    /// _Requirements: 1.4, 5.8_
    func testUncheckedCheckboxParsing() throws {
        let xml = "<input type=\"checkbox\" indent=\"1\" level=\"3\" />待办事项"
        
        // 解析 XML
        let nsAttributedString = try converter.xmlToNSAttributedString(xml)
        
        // 验证文本内容
        XCTAssertTrue(nsAttributedString.string.contains("待办事项"), "应该包含待办事项文本")
        
        // 验证复选框附件
        var foundCheckbox = false
        nsAttributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: nsAttributedString.length)) { value, _, _ in
            if let checkbox = value as? InteractiveCheckboxAttachment {
                foundCheckbox = true
                XCTAssertFalse(checkbox.isChecked, "复选框应该是未选中状态")
                XCTAssertEqual(checkbox.indent, 1, "缩进应该是 1")
                XCTAssertEqual(checkbox.level, 3, "级别应该是 3")
            }
        }
        XCTAssertTrue(foundCheckbox, "应该找到复选框附件")
    }
    
    /// 测试选中复选框的解析和导出
    /// _Requirements: 1.4, 5.8_
    func testCheckedCheckboxParsing() throws {
        let xml = "<input type=\"checkbox\" indent=\"2\" level=\"3\" checked=\"true\" />已完成事项"
        
        // 解析 XML
        let nsAttributedString = try converter.xmlToNSAttributedString(xml)
        
        // 验证文本内容
        XCTAssertTrue(nsAttributedString.string.contains("已完成事项"), "应该包含已完成事项文本")
        
        // 验证复选框附件
        var foundCheckbox = false
        nsAttributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: nsAttributedString.length)) { value, _, _ in
            if let checkbox = value as? InteractiveCheckboxAttachment {
                foundCheckbox = true
                XCTAssertTrue(checkbox.isChecked, "复选框应该是选中状态")
                XCTAssertEqual(checkbox.indent, 2, "缩进应该是 2")
                XCTAssertEqual(checkbox.level, 3, "级别应该是 3")
            }
        }
        XCTAssertTrue(foundCheckbox, "应该找到复选框附件")
    }
    
    /// 测试复选框状态往返一致性
    /// _Requirements: 1.4, 5.8_
    func testCheckboxStateRoundTrip() throws {
        // 测试选中状态
        let checkedXML = "<input type=\"checkbox\" indent=\"1\" level=\"3\" checked=\"true\" />选中的复选框"
        let checkedNS = try converter.xmlToNSAttributedString(checkedXML)
        let exportedCheckedXML = try converter.nsAttributedStringToXML(checkedNS)
        
        XCTAssertTrue(exportedCheckedXML.contains("checked=\"true\""), "导出的 XML 应该包含 checked=\"true\"")
        
        // 测试未选中状态
        let uncheckedXML = "<input type=\"checkbox\" indent=\"1\" level=\"3\" />未选中的复选框"
        let uncheckedNS = try converter.xmlToNSAttributedString(uncheckedXML)
        let exportedUncheckedXML = try converter.nsAttributedStringToXML(uncheckedNS)
        
        XCTAssertFalse(exportedUncheckedXML.contains("checked=\"true\""), "导出的 XML 不应该包含 checked=\"true\"")
        XCTAssertTrue(exportedUncheckedXML.contains("<input type=\"checkbox\""), "导出的 XML 应该包含复选框标签")
    }
    
    /// 测试复选框属性保留
    /// _Requirements: 5.8_
    func testCheckboxAttributesPreservation() throws {
        let xml = "<input type=\"checkbox\" indent=\"3\" level=\"5\" checked=\"true\" />带属性的复选框"
        
        // 解析 XML
        let nsAttributedString = try converter.xmlToNSAttributedString(xml)
        
        // 导出 XML
        let exportedXML = try converter.nsAttributedStringToXML(nsAttributedString)
        
        // 验证属性保留
        XCTAssertTrue(exportedXML.contains("indent=\"3\""), "应该保留 indent 属性")
        XCTAssertTrue(exportedXML.contains("level=\"5\""), "应该保留 level 属性")
        XCTAssertTrue(exportedXML.contains("checked=\"true\""), "应该保留 checked 属性")
    }
    
    // MARK: - 嵌套格式测试
    
    /// 测试粗体+斜体嵌套格式（斜体在外，粗体在内）
    /// 这是用户报告的 bug：设置粗体+斜体后，切换笔记再切回来，粗体丢失
    func testNestedBoldItalicFormat_ItalicOuterBoldInner() throws {
        // XML 格式：<i><b>你好</b></i>
        let xml = "<text indent=\"1\"><i><b>你好</b></i></text>"
        
        // 解析 XML 到 NSAttributedString
        let nsAttributedString = try converter.xmlToNSAttributedString(xml)
        
        // 验证文本内容
        XCTAssertEqual(nsAttributedString.string, "你好", "文本内容应该正确")
        
        // 验证粗体属性
        var hasBold = false
        var hasItalic = false
        
        nsAttributedString.enumerateAttributes(in: NSRange(location: 0, length: nsAttributedString.length), options: []) { attrs, _, _ in
            // 检查字体是否有粗体特性
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) {
                    hasBold = true
                }
            }
            
            // 检查是否有斜体（通过 obliqueness 属性）
            if let obliqueness = attrs[.obliqueness] as? Double, obliqueness > 0 {
                hasItalic = true
            }
        }
        
        XCTAssertTrue(hasBold, "应该检测到粗体格式")
        XCTAssertTrue(hasItalic, "应该检测到斜体格式")
    }
    
    /// 测试粗体+斜体嵌套格式（粗体在外，斜体在内）
    func testNestedBoldItalicFormat_BoldOuterItalicInner() throws {
        // XML 格式：<b><i>你好</i></b>
        let xml = "<text indent=\"1\"><b><i>你好</i></b></text>"
        
        // 解析 XML 到 NSAttributedString
        let nsAttributedString = try converter.xmlToNSAttributedString(xml)
        
        // 验证文本内容
        XCTAssertEqual(nsAttributedString.string, "你好", "文本内容应该正确")
        
        // 验证粗体和斜体属性
        var hasBold = false
        var hasItalic = false
        
        nsAttributedString.enumerateAttributes(in: NSRange(location: 0, length: nsAttributedString.length), options: []) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) {
                    hasBold = true
                }
            }
            
            if let obliqueness = attrs[.obliqueness] as? Double, obliqueness > 0 {
                hasItalic = true
            }
        }
        
        XCTAssertTrue(hasBold, "应该检测到粗体格式")
        XCTAssertTrue(hasItalic, "应该检测到斜体格式")
    }
    
    /// 测试粗体+斜体往返转换
    func testNestedBoldItalicRoundTrip() throws {
        let originalXML = "<text indent=\"1\"><i><b>你好</b></i></text>"
        
        // XML -> NSAttributedString
        let nsAttributedString = try converter.xmlToNSAttributedString(originalXML)
        
        // NSAttributedString -> XML
        let exportedXML = try converter.nsAttributedStringToXML(nsAttributedString)
        
        // 验证导出的 XML 包含粗体和斜体标签
        XCTAssertTrue(exportedXML.contains("<b>"), "导出的 XML 应该包含粗体标签")
        XCTAssertTrue(exportedXML.contains("<i>"), "导出的 XML 应该包含斜体标签")
        XCTAssertTrue(exportedXML.contains("你好"), "导出的 XML 应该包含文本内容")
    }
    
    /// 测试标题+粗体+斜体三层嵌套
    func testTripleNestedFormat() throws {
        // XML 格式：<size><b><i>标题粗斜体</i></b></size>
        let xml = "<text indent=\"1\"><size><b><i>标题粗斜体</i></b></size></text>"
        
        // 解析 XML 到 NSAttributedString
        let nsAttributedString = try converter.xmlToNSAttributedString(xml)
        
        // 验证文本内容
        XCTAssertEqual(nsAttributedString.string, "标题粗斜体", "文本内容应该正确")
        
        // 验证所有格式属性
        var hasBold = false
        var hasItalic = false
        var hasLargeFont = false
        
        nsAttributedString.enumerateAttributes(in: NSRange(location: 0, length: nsAttributedString.length), options: []) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) {
                    hasBold = true
                }
                // 一级标题字体大小应该是 24
                if font.pointSize >= 24 {
                    hasLargeFont = true
                }
            }
            
            if let obliqueness = attrs[.obliqueness] as? Double, obliqueness > 0 {
                hasItalic = true
            }
        }
        
        XCTAssertTrue(hasBold, "应该检测到粗体格式")
        XCTAssertTrue(hasItalic, "应该检测到斜体格式")
        XCTAssertTrue(hasLargeFont, "应该检测到大字体（一级标题）")
    }
}