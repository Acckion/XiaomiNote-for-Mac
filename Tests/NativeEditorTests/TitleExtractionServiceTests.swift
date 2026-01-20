//
//  TitleExtractionServiceTests.swift
//  MiNoteMac
//
//  TitleExtractionService 单元测试
//  验证标题提取服务的基本功能
//
//  Created by Title Content Integration Fix
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// TitleExtractionService 单元测试类
///
/// 测试覆盖：
/// 1. XML 标题提取功能
/// 2. 原生编辑器标题提取功能
/// 3. 标题验证逻辑
/// 4. 特殊字符和 XML 实体处理
/// 5. 边界情况处理
@MainActor
final class TitleExtractionServiceTests: XCTestCase {
    
    var service: TitleExtractionService!
    
    override func setUp() {
        super.setUp()
        service = TitleExtractionService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - XML 标题提取测试
    
    /// 测试从标准 XML 提取标题
    func testExtractTitleFromXML_StandardCase() {
        let xml = "<title>我的笔记标题</title><content>正文内容</content>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "我的笔记标题")
        XCTAssertEqual(result.source, .xml)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.error)
    }
    
    /// 测试从空 XML 提取标题
    func testExtractTitleFromXML_EmptyContent() {
        let xml = ""
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.source, .xml)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.originalLength, 0)
    }
    
    /// 测试从没有标题标签的 XML 提取标题
    func testExtractTitleFromXML_NoTitleTag() {
        let xml = "<content>只有正文内容</content>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.source, .xml)
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试从格式错误的 XML 提取标题（缺少结束标签）
    func testExtractTitleFromXML_MalformedXML() {
        let xml = "<title>标题没有结束标签"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.source, .xml)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error?.contains("缺少 </title> 结束标签") == true)
    }
    
    /// 测试 XML 实体解码
    func testExtractTitleFromXML_XMLEntities() {
        let xml = "<title>标题 &amp; 特殊字符 &lt;test&gt; &quot;引号&quot;</title>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "标题 & 特殊字符 <test> \"引号\"")
        XCTAssertEqual(result.source, .xml)
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试数字字符引用解码
    func testExtractTitleFromXML_NumericCharacterReferences() {
        let xml = "<title>标题&#39;单引号&#x27;和&#39;测试</title>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "标题'单引号'和'测试")
        XCTAssertEqual(result.source, .xml)
        XCTAssertTrue(result.isValid)
    }
    
    // MARK: - 原生编辑器标题提取测试
    
    /// 测试从空编辑器提取标题
    func testExtractTitleFromEditor_EmptyContent() {
        let textStorage = NSTextStorage()
        let result = service.extractTitleFromEditor(textStorage)
        
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.source, .nativeEditor)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.originalLength, 0)
    }
    
    /// 测试从包含标题段落的编辑器提取标题
    func testExtractTitleFromEditor_WithTitleParagraph() {
        let textStorage = NSTextStorage()
        let titleText = "我的笔记标题"
        let contentText = "这是正文内容"
        
        // 创建标题段落
        let titleString = NSMutableAttributedString(string: titleText + "\n")
        titleString.addAttribute(.isTitle, value: true, range: NSRange(location: 0, length: titleString.length))
        
        // 创建正文段落
        let contentString = NSAttributedString(string: contentText)
        
        // 组合内容
        textStorage.append(titleString)
        textStorage.append(contentString)
        
        let result = service.extractTitleFromEditor(textStorage)
        
        XCTAssertEqual(result.title, titleText)
        XCTAssertEqual(result.source, .nativeEditor)
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试从包含 ParagraphType.title 的编辑器提取标题
    func testExtractTitleFromEditor_WithParagraphType() {
        let textStorage = NSTextStorage()
        let titleText = "标题通过 ParagraphType"
        
        // 创建标题段落（使用 ParagraphType.title）
        let titleString = NSMutableAttributedString(string: titleText + "\n")
        titleString.addAttribute(.paragraphType, value: ParagraphType.title, range: NSRange(location: 0, length: titleString.length))
        
        textStorage.append(titleString)
        
        let result = service.extractTitleFromEditor(textStorage)
        
        XCTAssertEqual(result.title, titleText)
        XCTAssertEqual(result.source, .nativeEditor)
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试从没有标题段落的编辑器提取标题
    func testExtractTitleFromEditor_NoTitleParagraph() {
        let textStorage = NSTextStorage()
        let normalText = "这是普通文本，不是标题"
        
        // 创建普通段落（没有标题属性）
        let normalString = NSAttributedString(string: normalText)
        textStorage.append(normalString)
        
        let result = service.extractTitleFromEditor(textStorage)
        
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.source, .nativeEditor)
        XCTAssertTrue(result.isValid)
    }
    
    // MARK: - 标题验证测试
    
    /// 测试有效标题验证
    func testValidateTitle_ValidTitle() {
        let title = "这是一个有效的标题"
        let validation = service.validateTitle(title)
        
        XCTAssertTrue(validation.isValid)
        XCTAssertNil(validation.error)
    }
    
    /// 测试超长标题验证
    func testValidateTitle_TooLong() {
        let title = String(repeating: "很长的标题", count: 50) // 超过 200 字符
        let validation = service.validateTitle(title)
        
        XCTAssertFalse(validation.isValid)
        XCTAssertNotNil(validation.error)
        XCTAssertTrue(validation.error?.contains("长度超过限制") == true)
    }
    
    /// 测试包含换行符的标题验证
    func testValidateTitle_WithNewlines() {
        let title = "标题\n包含换行符"
        let validation = service.validateTitle(title)
        
        XCTAssertFalse(validation.isValid)
        XCTAssertNotNil(validation.error)
        XCTAssertTrue(validation.error?.contains("不能包含换行符") == true)
    }
    
    /// 测试包含控制字符的标题验证
    func testValidateTitle_WithControlCharacters() {
        let title = "标题\u{0001}包含控制字符"
        let validation = service.validateTitle(title)
        
        XCTAssertFalse(validation.isValid)
        XCTAssertNotNil(validation.error)
        XCTAssertTrue(validation.error?.contains("不能包含控制字符") == true)
    }
    
    // MARK: - 边界情况和错误处理测试
    
    /// 测试标题清理功能
    func testTitleCleaning() {
        let xml = "<title>  \n  标题前后有空白  \n  </title>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "标题前后有空白")
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试多个空白字符合并
    func testMultipleWhitespaceCollapse() {
        let xml = "<title>标题    中间    有多个    空格</title>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title, "标题 中间 有多个 空格")
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试超长标题自动截断
    func testLongTitleTruncation() {
        let longTitle = String(repeating: "很长的标题", count: 50)
        let xml = "<title>\(longTitle)</title>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.title.count, 200)
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试结果元数据
    func testResultMetadata() {
        let xml = "<title>测试标题</title>"
        let result = service.extractTitleFromXML(xml)
        
        XCTAssertEqual(result.source, .xml)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.originalLength, xml.count)
        XCTAssertEqual(result.processedLength, "测试标题".count)
        XCTAssertNotNil(result.extractionTime)
        XCTAssertNil(result.error)
    }
}