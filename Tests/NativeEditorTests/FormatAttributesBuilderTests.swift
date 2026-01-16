//
//  FormatAttributesBuilderTests.swift
//  MiNoteMac
//
//  格式属性构建器单元测试
//  测试各种格式组合的属性构建和边界条件
//
//  _Requirements: 2.1-2.6_
//

import XCTest
import AppKit
@testable import MiNoteLibrary

@MainActor
final class FormatAttributesBuilderTests: XCTestCase {
    
    // MARK: - 默认属性测试
    
    func testBuildDefault() {
        // 测试默认格式状态的属性构建
        let attributes = FormatAttributesBuilder.buildDefault()
        
        // 验证字体存在
        XCTAssertNotNil(attributes[.font], "默认属性应该包含字体")
        
        // 验证文本颜色存在
        XCTAssertNotNil(attributes[.foregroundColor], "默认属性应该包含文本颜色")
        
        // 验证没有下划线
        XCTAssertNil(attributes[.underlineStyle], "默认属性不应该包含下划线")
        
        // 验证没有删除线
        XCTAssertNil(attributes[.strikethroughStyle], "默认属性不应该包含删除线")
        
        // 验证没有高亮
        XCTAssertNil(attributes[.backgroundColor], "默认属性不应该包含背景色")
    }
    
    // MARK: - 单一格式测试
    
    func testBuildBoldFormat() {
        // 测试加粗格式
        // _Requirements: 2.1_
        var state = FormatState()
        state.isBold = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证字体包含加粗特性
        guard let font = attributes[.font] as? NSFont else {
            XCTFail("属性应该包含字体")
            return
        }
        
        let traits = font.fontDescriptor.symbolicTraits
        XCTAssertTrue(traits.contains(.bold), "字体应该包含加粗特性")
    }
    
    func testBuildItalicFormat() {
        // 测试斜体格式
        // _Requirements: 2.2_
        var state = FormatState()
        state.isItalic = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证字体包含斜体特性或 obliqueness 属性
        guard let font = attributes[.font] as? NSFont else {
            XCTFail("属性应该包含字体")
            return
        }
        
        let traits = font.fontDescriptor.symbolicTraits
        let hasItalicTrait = traits.contains(.italic)
        let hasObliqueness = (attributes[.obliqueness] as? Double) ?? 0 > 0
        
        XCTAssertTrue(hasItalicTrait || hasObliqueness, "应该包含斜体特性或 obliqueness 属性")
    }
    
    func testBuildUnderlineFormat() {
        // 测试下划线格式
        // _Requirements: 2.3_
        var state = FormatState()
        state.isUnderline = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证下划线样式
        guard let underlineStyle = attributes[.underlineStyle] as? Int else {
            XCTFail("属性应该包含下划线样式")
            return
        }
        
        XCTAssertEqual(underlineStyle, NSUnderlineStyle.single.rawValue, "下划线样式应该是单线")
    }
    
    func testBuildStrikethroughFormat() {
        // 测试删除线格式
        // _Requirements: 2.4_
        var state = FormatState()
        state.isStrikethrough = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证删除线样式
        guard let strikethroughStyle = attributes[.strikethroughStyle] as? Int else {
            XCTFail("属性应该包含删除线样式")
            return
        }
        
        XCTAssertEqual(strikethroughStyle, NSUnderlineStyle.single.rawValue, "删除线样式应该是单线")
    }
    
    func testBuildHighlightFormat() {
        // 测试高亮格式
        // _Requirements: 2.5_
        var state = FormatState()
        state.isHighlight = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证背景色
        guard let backgroundColor = attributes[.backgroundColor] as? NSColor else {
            XCTFail("属性应该包含背景色")
            return
        }
        
        // 验证背景色是黄色（高亮色）
        XCTAssertEqual(backgroundColor, FormatAttributesBuilder.highlightColor, "背景色应该是高亮色")
    }
    
    // MARK: - 多格式组合测试
    
    func testBuildBoldItalicFormat() {
        // 测试加粗+斜体组合
        // _Requirements: 2.6_
        var state = FormatState()
        state.isBold = true
        state.isItalic = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        guard let font = attributes[.font] as? NSFont else {
            XCTFail("属性应该包含字体")
            return
        }
        
        let traits = font.fontDescriptor.symbolicTraits
        XCTAssertTrue(traits.contains(.bold), "字体应该包含加粗特性")
        
        // 斜体可能通过 trait 或 obliqueness 实现
        let hasItalicTrait = traits.contains(.italic)
        let hasObliqueness = (attributes[.obliqueness] as? Double) ?? 0 > 0
        XCTAssertTrue(hasItalicTrait || hasObliqueness, "应该包含斜体特性或 obliqueness 属性")
    }
    
    func testBuildAllCharacterFormats() {
        // 测试所有字符格式组合
        // _Requirements: 2.6_
        var state = FormatState()
        state.isBold = true
        state.isItalic = true
        state.isUnderline = true
        state.isStrikethrough = true
        state.isHighlight = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证字体
        XCTAssertNotNil(attributes[.font], "应该包含字体")
        
        // 验证下划线
        XCTAssertNotNil(attributes[.underlineStyle], "应该包含下划线")
        
        // 验证删除线
        XCTAssertNotNil(attributes[.strikethroughStyle], "应该包含删除线")
        
        // 验证高亮
        XCTAssertNotNil(attributes[.backgroundColor], "应该包含背景色")
    }
    
    func testBuildUnderlineAndStrikethrough() {
        // 测试下划线+删除线组合
        var state = FormatState()
        state.isUnderline = true
        state.isStrikethrough = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 验证两种装饰都存在
        XCTAssertNotNil(attributes[.underlineStyle], "应该包含下划线")
        XCTAssertNotNil(attributes[.strikethroughStyle], "应该包含删除线")
    }
    
    // MARK: - 段落格式测试
    
    func testBuildHeading1Format() {
        // 测试大标题格式
        var state = FormatState()
        state.paragraphFormat = .heading1
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        guard let font = attributes[.font] as? NSFont else {
            XCTFail("属性应该包含字体")
            return
        }
        
        // 大标题字体应该比正文大
        XCTAssertGreaterThan(font.pointSize, 15, "大标题字体应该大于正文字体")
    }
    
    func testBuildHeading2Format() {
        // 测试二级标题格式
        var state = FormatState()
        state.paragraphFormat = .heading2
        
        let attributes = FormatAttributesBuilder.build(from: state)
        
        guard let font = attributes[.font] as? NSFont else {
            XCTFail("属性应该包含字体")
            return
        }
        
        // 二级标题字体应该比正文大
        XCTAssertGreaterThan(font.pointSize, 15, "二级标题字体应该大于正文字体")
    }
    
    // MARK: - 格式状态提取测试
    
    func testExtractBoldFormatState() {
        // 测试从属性中提取加粗格式状态
        var state = FormatState()
        state.isBold = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        XCTAssertTrue(extractedState.isBold, "提取的格式状态应该包含加粗")
    }
    
    func testExtractUnderlineFormatState() {
        // 测试从属性中提取下划线格式状态
        var state = FormatState()
        state.isUnderline = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        XCTAssertTrue(extractedState.isUnderline, "提取的格式状态应该包含下划线")
    }
    
    func testExtractStrikethroughFormatState() {
        // 测试从属性中提取删除线格式状态
        var state = FormatState()
        state.isStrikethrough = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        XCTAssertTrue(extractedState.isStrikethrough, "提取的格式状态应该包含删除线")
    }
    
    func testExtractHighlightFormatState() {
        // 测试从属性中提取高亮格式状态
        var state = FormatState()
        state.isHighlight = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        XCTAssertTrue(extractedState.isHighlight, "提取的格式状态应该包含高亮")
    }
    
    func testExtractMultipleFormatsState() {
        // 测试从属性中提取多种格式状态
        // _Requirements: 2.6_
        var state = FormatState()
        state.isBold = true
        state.isUnderline = true
        state.isHighlight = true
        
        let attributes = FormatAttributesBuilder.build(from: state)
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        XCTAssertTrue(extractedState.isBold, "提取的格式状态应该包含加粗")
        XCTAssertTrue(extractedState.isUnderline, "提取的格式状态应该包含下划线")
        XCTAssertTrue(extractedState.isHighlight, "提取的格式状态应该包含高亮")
    }
    
    // MARK: - 边界条件测试
    
    func testBuildFromEmptyState() {
        // 测试空格式状态
        let state = FormatState()
        let attributes = FormatAttributesBuilder.build(from: state)
        
        // 应该至少包含字体和文本颜色
        XCTAssertNotNil(attributes[.font], "应该包含字体")
        XCTAssertNotNil(attributes[.foregroundColor], "应该包含文本颜色")
    }
    
    func testExtractFromEmptyAttributes() {
        // 测试从空属性字典提取格式状态
        let attributes: [NSAttributedString.Key: Any] = [:]
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        // 应该返回默认格式状态
        XCTAssertFalse(extractedState.isBold, "不应该包含加粗")
        XCTAssertFalse(extractedState.isItalic, "不应该包含斜体")
        XCTAssertFalse(extractedState.isUnderline, "不应该包含下划线")
        XCTAssertFalse(extractedState.isStrikethrough, "不应该包含删除线")
        XCTAssertFalse(extractedState.isHighlight, "不应该包含高亮")
    }
    
    func testExtractFromPartialAttributes() {
        // 测试从部分属性字典提取格式状态
        let attributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let extractedState = FormatAttributesBuilder.extractFormatState(from: attributes)
        
        XCTAssertTrue(extractedState.isUnderline, "应该包含下划线")
        XCTAssertFalse(extractedState.isBold, "不应该包含加粗")
    }
    
    // MARK: - 属性合并测试
    
    func testMergeAttributes() {
        // 测试属性合并
        let existing: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ]
        
        let new: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.red  // 覆盖现有颜色
        ]
        
        let merged = FormatAttributesBuilder.merge(existing: existing, with: new)
        
        // 验证合并结果
        XCTAssertNotNil(merged[.font], "应该保留字体")
        XCTAssertNotNil(merged[.underlineStyle], "应该包含下划线")
        
        // 验证新属性覆盖旧属性
        if let color = merged[.foregroundColor] as? NSColor {
            XCTAssertEqual(color, NSColor.red, "颜色应该被覆盖为红色")
        } else {
            XCTFail("应该包含文本颜色")
        }
    }
    
    // MARK: - 字体构建测试
    
    func testBuildFontDefault() {
        // 测试默认字体构建
        let state = FormatState()
        let font = FormatAttributesBuilder.buildFont(from: state)
        
        XCTAssertEqual(font.pointSize, 13, "默认字体大小应该是 13")
    }
    
    func testBuildFontBold() {
        // 测试加粗字体构建
        var state = FormatState()
        state.isBold = true
        
        let font = FormatAttributesBuilder.buildFont(from: state)
        let traits = font.fontDescriptor.symbolicTraits
        
        XCTAssertTrue(traits.contains(.bold), "字体应该包含加粗特性")
    }
    
    // MARK: - 字体大小常量测试
    // 任务 1.1: 编写字体大小常量的单元测试
    // _需求: 1.6, 1.7, 4.6, 4.7_
    
    func testDetermineFontSizeForBody() {
        // 测试正文字体大小应该是 13pt
        var state = FormatState()
        state.paragraphFormat = .body
        
        let font = FormatAttributesBuilder.buildFont(from: state)
        
        XCTAssertEqual(font.pointSize, 13, "正文字体大小应该是 13pt")
    }
    
    func testDetermineFontSizeForHeading3() {
        // 测试三级标题字体大小应该是 16pt
        var state = FormatState()
        state.paragraphFormat = .heading3
        
        let font = FormatAttributesBuilder.buildFont(from: state)
        
        XCTAssertEqual(font.pointSize, 16, "三级标题字体大小应该是 16pt")
    }
    
    func testDetermineFontSizeForHeading2() {
        // 测试二级标题字体大小应该是 18pt
        var state = FormatState()
        state.paragraphFormat = .heading2
        
        let font = FormatAttributesBuilder.buildFont(from: state)
        
        XCTAssertEqual(font.pointSize, 18, "二级标题字体大小应该是 18pt")
    }
    
    func testDetermineFontSizeForHeading1() {
        // 测试大标题字体大小应该是 22pt
        var state = FormatState()
        state.paragraphFormat = .heading1
        
        let font = FormatAttributesBuilder.buildFont(from: state)
        
        XCTAssertEqual(font.pointSize, 22, "大标题字体大小应该是 22pt")
    }
}
