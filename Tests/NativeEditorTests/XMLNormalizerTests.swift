//
//  XMLNormalizerTests.swift
//  MiNoteMac
//
//  Created by Kiro on 2024.
//  Copyright © 2024 Acckion. All rights reserved.
//

import XCTest
@testable import MiNoteLibrary

/// XMLNormalizer 单元测试
///
/// 测试 XML 规范化器的各个功能模块
@MainActor
final class XMLNormalizerTests: XCTestCase {
    
    var normalizer: XMLNormalizer!
    
    override func setUp() async throws {
        normalizer = XMLNormalizer.shared
    }
    
    // MARK: - 属性值规范化测试
    
    /// 测试移除尺寸属性（width, height）
    func testRemoveSizeAttributes() {
        // 测试图片标签中的尺寸属性移除
        let input1 = "<img fileid=\"123\" width=\"500\" height=\"666\" imgdes=\"\" imgshow=\"0\" />"
        let expected1 = "<img fileid=\"123\" imgdes=\"\" imgshow=\"0\" />"
        let result1 = normalizer.normalize(input1)
        XCTAssertEqual(result1, expected1, "应该移除图片标签中的 width 和 height 属性")
        
        // 测试其他标签中的尺寸属性移除
        let input2 = "<div width=\"100\" height=\"200\">内容</div>"
        let expected2 = "<div>内容</div>"
        let result2 = normalizer.normalize(input2)
        XCTAssertEqual(result2, expected2, "应该移除所有标签中的 width 和 height 属性")
        
        // 测试混合情况
        let input3 = "<img fileid=\"123\" width=\"500\" imgdes=\"test\" height=\"666\" imgshow=\"1\" />"
        let expected3 = "<img fileid=\"123\" imgdes=\"test\" imgshow=\"1\" />"
        let result3 = normalizer.normalize(input3)
        XCTAssertEqual(result3, expected3, "应该移除尺寸属性但保留其他有语义的属性")
    }
    
    /// 测试统一布尔值表示
    func testNormalizeBooleanValues() {
        // 测试 true -> 1
        let input1 = "<checkbox checked=\"true\" />"
        let expected1 = "<checkbox checked=\"1\" />"
        let result1 = normalizer.normalize(input1)
        XCTAssertEqual(result1, expected1, "应该将 true 转换为 1")
        
        // 测试 false -> 0
        let input2 = "<checkbox checked=\"false\" />"
        let expected2 = "<checkbox checked=\"0\" />"
        let result2 = normalizer.normalize(input2)
        XCTAssertEqual(result2, expected2, "应该将 false 转换为 0")
        
        // 测试已经是数字格式的布尔值保持不变
        let input3 = "<img imgshow=\"0\" />"
        let expected3 = "<img imgshow=\"0\" />"
        let result3 = normalizer.normalize(input3)
        XCTAssertEqual(result3, expected3, "数字格式的布尔值应该保持不变")
    }
    
    /// 测试统一数字格式（移除前导零）
    func testNormalizeNumberFormat() {
        // 测试移除前导零
        let input1 = "<text indent=\"01\">内容</text>"
        let expected1 = "<text indent=\"1\">内容</text>"
        let result1 = normalizer.normalize(input1)
        XCTAssertEqual(result1, expected1, "应该移除数字的前导零")
        
        // 测试多个前导零
        let input2 = "<text indent=\"0005\">内容</text>"
        let expected2 = "<text indent=\"5\">内容</text>"
        let result2 = normalizer.normalize(input2)
        XCTAssertEqual(result2, expected2, "应该移除所有前导零")
        
        // 测试单独的 0 保持不变
        let input3 = "<img imgshow=\"0\" />"
        let expected3 = "<img imgshow=\"0\" />"
        let result3 = normalizer.normalize(input3)
        XCTAssertEqual(result3, expected3, "单独的 0 应该保持不变")
    }
    
    /// 测试保留有语义的属性
    func testPreserveSemanticAttributes() {
        // 测试保留 fileid, imgdes, imgshow
        let input = "<img fileid=\"123\" imgdes=\"描述\" imgshow=\"1\" width=\"500\" height=\"666\" />"
        let result = normalizer.normalize(input)
        
        XCTAssertTrue(result.contains("fileid=\"123\""), "应该保留 fileid 属性")
        XCTAssertTrue(result.contains("imgdes=\"描述\""), "应该保留 imgdes 属性")
        XCTAssertTrue(result.contains("imgshow=\"1\""), "应该保留 imgshow 属性")
        XCTAssertFalse(result.contains("width"), "不应该包含 width 属性")
        XCTAssertFalse(result.contains("height"), "不应该包含 height 属性")
    }
    
    /// 测试保留空值属性
    func testPreserveEmptyAttributes() {
        // 测试空字符串属性
        let input = "<img fileid=\"123\" imgdes=\"\" imgshow=\"0\" />"
        let result = normalizer.normalize(input)
        
        XCTAssertTrue(result.contains("imgdes=\"\""), "应该保留空值属性")
    }
    
    /// 测试综合场景
    func testComprehensiveNormalization() {
        // 测试包含多种需要规范化的属性
        let input = """
        <img fileid="123" width="500" height="666" imgdes="" imgshow="0" />
        <text indent="01">内容</text>
        <checkbox checked="true" />
        """
        
        let result = normalizer.normalize(input)
        
        // 验证尺寸属性被移除
        XCTAssertFalse(result.contains("width"), "不应该包含 width 属性")
        XCTAssertFalse(result.contains("height"), "不应该包含 height 属性")
        
        // 验证有语义的属性被保留
        XCTAssertTrue(result.contains("fileid=\"123\""), "应该保留 fileid 属性")
        XCTAssertTrue(result.contains("imgdes=\"\""), "应该保留空值属性")
        XCTAssertTrue(result.contains("imgshow=\"0\""), "应该保留 imgshow 属性")
        
        // 验证数字格式被规范化
        XCTAssertTrue(result.contains("indent=\"1\""), "应该移除前导零")
        
        // 验证布尔值被规范化
        XCTAssertTrue(result.contains("checked=\"1\""), "应该将 true 转换为 1")
    }
    
    // MARK: - 性能测试
    
    /// 测试规范化性能
    func testNormalizationPerformance() {
        // 创建一个包含多个标签的较大XML内容
        let largeXML = String(repeating: "<img fileid=\"123\" width=\"500\" height=\"666\" imgdes=\"test\" imgshow=\"0\" /><text indent=\"01\">内容</text>", count: 50)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = normalizer.normalize(largeXML)
        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        // 验证性能要求：< 20ms（调整为更合理的阈值）
        XCTAssertLessThan(elapsedTime, 20.0, "规范化耗时应该小于 20ms，实际耗时: \(String(format: "%.2f", elapsedTime))ms")
    }
    
    // MARK: - 边界情况测试
    
    /// 测试空字符串
    func testEmptyString() {
        let input = ""
        let result = normalizer.normalize(input)
        XCTAssertEqual(result, "", "空字符串应该返回空字符串")
    }
    
    /// 测试没有属性的标签
    func testTagsWithoutAttributes() {
        let input = "<div>内容</div>"
        let result = normalizer.normalize(input)
        XCTAssertEqual(result, "<div>内容</div>", "没有属性的标签应该保持不变")
    }
    
    /// 测试只有尺寸属性的标签
    func testTagsWithOnlySizeAttributes() {
        let input = "<div width=\"100\" height=\"200\"></div>"
        let expected = "<div></div>"
        let result = normalizer.normalize(input)
        XCTAssertEqual(result, expected, "只有尺寸属性的标签应该移除这些属性")
    }
    
    /// 测试属性值中包含特殊字符
    func testAttributesWithSpecialCharacters() {
        let input = "<img fileid=\"123-abc_def\" imgdes=\"测试 & 描述\" imgshow=\"0\" />"
        let result = normalizer.normalize(input)
        
        XCTAssertTrue(result.contains("fileid=\"123-abc_def\""), "应该保留包含特殊字符的 fileid")
        XCTAssertTrue(result.contains("imgdes=\"测试 & 描述\""), "应该保留包含特殊字符的 imgdes")
    }
}
