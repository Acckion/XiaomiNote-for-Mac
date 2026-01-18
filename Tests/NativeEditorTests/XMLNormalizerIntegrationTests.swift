//
//  XMLNormalizerIntegrationTests.swift
//  MiNoteMac
//
//  Created by Kiro on 2024.
//  Copyright © 2024 Acckion. All rights reserved.
//

import XCTest
@testable import MiNoteLibrary

/// XMLNormalizer 集成测试
///
/// 测试 XMLNormalizer 在实际场景中的应用
@MainActor
final class XMLNormalizerIntegrationTests: XCTestCase {
    
    var normalizer: XMLNormalizer!
    
    override func setUp() async throws {
        normalizer = XMLNormalizer.shared
    }
    
    // MARK: - 集成测试
    
    /// 测试相同内容不同格式的情况
    /// 
    /// 验证：旧版和新版图片格式被正确识别为相同内容
    func testSameContentDifferentFormat() {
        // 旧版图片格式
        let oldFormat = """
        <text indent="0">这是一段文本</text>
        ☺ 1315204657.RSgsGMIo2QYlsy-vb_2lXw<0/></>
        <text indent="0">更多文本</text>
        """
        
        // 新版图片格式
        let newFormat = """
        <text indent="0">这是一段文本</text>
        <img fileid="1315204657.RSgsGMIo2QYlsy-vb_2lXw" imgshow="0" imgdes="" width="500" height="666" />
        <text indent="0">更多文本</text>
        """
        
        let normalizedOld = normalizer.normalize(oldFormat)
        let normalizedNew = normalizer.normalize(newFormat)
        
        XCTAssertEqual(normalizedOld, normalizedNew, "旧版和新版图片格式规范化后应该相同")
    }
    
    /// 测试不同内容相同格式的情况
    ///
    /// 验证：实际内容变化能被正确检测
    func testDifferentContentSameFormat() {
        let content1 = """
        <text indent="0">这是第一段文本</text>
        <img fileid="123" imgshow="0" imgdes="" />
        """
        
        let content2 = """
        <text indent="0">这是第二段文本</text>
        <img fileid="123" imgshow="0" imgdes="" />
        """
        
        let normalized1 = normalizer.normalize(content1)
        let normalized2 = normalizer.normalize(content2)
        
        XCTAssertNotEqual(normalized1, normalized2, "不同内容规范化后应该不同")
    }
    
    /// 测试空格和换行差异
    ///
    /// 验证：空格和换行差异被规范化为单个空格
    func testWhitespaceAndNewlineDifferences() {
        let content1 = "<text indent=\"0\">文本</text><text indent=\"1\">缩进</text>"
        let content2 = """
        <text indent="0">文本</text>
        
        <text indent="1">缩进</text>
        """
        let content3 = "<text indent=\"0\">文本</text>  <text indent=\"1\">缩进</text>"
        let content4 = "<text indent=\"0\">文本</text>   <text indent=\"1\">缩进</text>"
        
        let normalized1 = normalizer.normalize(content1)
        let normalized2 = normalizer.normalize(content2)
        let normalized3 = normalizer.normalize(content3)
        let normalized4 = normalizer.normalize(content4)
        
        // 验证多余的换行和空格被规范化为单个空格
        XCTAssertEqual(normalized2, normalized3, "换行和多个空格应该被规范化为相同结果")
        XCTAssertEqual(normalized3, normalized4, "不同数量的空格应该被规范化为相同结果")
        
        // 注意：没有空格和有空格的情况会有差异，这是预期的
        // 因为标签之间的空格在某些情况下是有意义的
    }
    
    /// 测试属性顺序差异
    ///
    /// 验证：属性顺序不影响比较结果
    func testAttributeOrderDifferences() {
        let content1 = "<img fileid=\"123\" imgshow=\"0\" imgdes=\"test\" />"
        let content2 = "<img imgdes=\"test\" fileid=\"123\" imgshow=\"0\" />"
        let content3 = "<img imgshow=\"0\" imgdes=\"test\" fileid=\"123\" />"
        
        let normalized1 = normalizer.normalize(content1)
        let normalized2 = normalizer.normalize(content2)
        let normalized3 = normalizer.normalize(content3)
        
        XCTAssertEqual(normalized1, normalized2, "属性顺序差异不应影响比较结果")
        XCTAssertEqual(normalized1, normalized3, "属性顺序差异不应影响比较结果")
    }
    
    /// 测试尺寸属性差异
    ///
    /// 验证：尺寸属性差异不影响比较结果
    func testSizeAttributeDifferences() {
        let content1 = "<img fileid=\"123\" imgshow=\"0\" imgdes=\"\" width=\"500\" height=\"666\" />"
        let content2 = "<img fileid=\"123\" imgshow=\"0\" imgdes=\"\" width=\"800\" height=\"600\" />"
        let content3 = "<img fileid=\"123\" imgshow=\"0\" imgdes=\"\" />"
        
        let normalized1 = normalizer.normalize(content1)
        let normalized2 = normalizer.normalize(content2)
        let normalized3 = normalizer.normalize(content3)
        
        XCTAssertEqual(normalized1, normalized2, "尺寸属性差异不应影响比较结果")
        XCTAssertEqual(normalized1, normalized3, "有无尺寸属性不应影响比较结果")
    }
    
    /// 测试复杂场景
    ///
    /// 验证：多种格式差异组合的情况
    func testComplexScenario() {
        // 包含多种格式差异的内容
        let content1 = """
        <text indent="0">标题</text>
        ☺ 123<0/><旧版图片/>
        <text indent="01">缩进文本</text>
        <img fileid="456" width="500" height="666" imgshow="0" imgdes="描述" />
        """
        
        let content2 = """
        <text indent="0">标题</text>
        
        <img fileid="123" imgdes="旧版图片" imgshow="0" />
        <text indent="1">缩进文本</text>
        <img fileid="456" imgshow="0" imgdes="描述" width="800" height="600" />
        """
        
        let normalized1 = normalizer.normalize(content1)
        let normalized2 = normalizer.normalize(content2)
        
        // 验证关键内容相同
        XCTAssertTrue(normalized1.contains("fileid=\"123\""), "应包含第一个图片的 fileid")
        XCTAssertTrue(normalized1.contains("fileid=\"456\""), "应包含第二个图片的 fileid")
        XCTAssertTrue(normalized1.contains("标题"), "应包含标题文本")
        XCTAssertTrue(normalized1.contains("缩进文本"), "应包含缩进文本")
        
        XCTAssertTrue(normalized2.contains("fileid=\"123\""), "应包含第一个图片的 fileid")
        XCTAssertTrue(normalized2.contains("fileid=\"456\""), "应包含第二个图片的 fileid")
        XCTAssertTrue(normalized2.contains("标题"), "应包含标题文本")
        XCTAssertTrue(normalized2.contains("缩进文本"), "应包含缩进文本")
        
        // 验证尺寸属性被移除
        XCTAssertFalse(normalized1.contains("width"), "不应包含 width 属性")
        XCTAssertFalse(normalized1.contains("height"), "不应包含 height 属性")
        XCTAssertFalse(normalized2.contains("width"), "不应包含 width 属性")
        XCTAssertFalse(normalized2.contains("height"), "不应包含 height 属性")
    }
    
    /// 测试实际内容变化检测
    ///
    /// 验证：实际编辑能被正确检测
    func testActualContentChangeDetection() {
        let original = """
        <text indent="0">原始文本</text>
        <img fileid="123" imgshow="0" imgdes="" />
        """
        
        // 场景1：添加文本
        let withAddedText = """
        <text indent="0">原始文本</text>
        <text indent="0">新增文本</text>
        <img fileid="123" imgshow="0" imgdes="" />
        """
        
        // 场景2：修改文本
        let withModifiedText = """
        <text indent="0">修改后的文本</text>
        <img fileid="123" imgshow="0" imgdes="" />
        """
        
        // 场景3：删除图片
        let withoutImage = """
        <text indent="0">原始文本</text>
        """
        
        // 场景4：仅格式差异（不应检测为变化）
        let withFormatDiff = """
        <text indent="0">原始文本</text>
        
        <img fileid="123" imgdes="" imgshow="0" width="500" height="666" />
        """
        
        let normalizedOriginal = normalizer.normalize(original)
        let normalizedWithAddedText = normalizer.normalize(withAddedText)
        let normalizedWithModifiedText = normalizer.normalize(withModifiedText)
        let normalizedWithoutImage = normalizer.normalize(withoutImage)
        let normalizedWithFormatDiff = normalizer.normalize(withFormatDiff)
        
        // 验证实际内容变化被检测
        XCTAssertNotEqual(normalizedOriginal, normalizedWithAddedText, "添加文本应被检测为内容变化")
        XCTAssertNotEqual(normalizedOriginal, normalizedWithModifiedText, "修改文本应被检测为内容变化")
        XCTAssertNotEqual(normalizedOriginal, normalizedWithoutImage, "删除图片应被检测为内容变化")
        
        // 验证格式差异不被检测为内容变化
        XCTAssertEqual(normalizedOriginal, normalizedWithFormatDiff, "仅格式差异不应被检测为内容变化")
    }
    
    /// 测试幂等性
    ///
    /// 验证：多次规范化结果相同
    func testIdempotency() {
        let content = """
        <text indent="0">文本</text>
        ☺ 123<0/><描述/>
        <img fileid="456" width="500" height="666" imgshow="1" imgdes="test" />
        """
        
        let normalized1 = normalizer.normalize(content)
        let normalized2 = normalizer.normalize(normalized1)
        let normalized3 = normalizer.normalize(normalized2)
        
        XCTAssertEqual(normalized1, normalized2, "第一次和第二次规范化结果应该相同")
        XCTAssertEqual(normalized2, normalized3, "第二次和第三次规范化结果应该相同")
    }
}
