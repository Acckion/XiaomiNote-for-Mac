//
//  XMLNormalizerTests.swift
//  MiNoteMac
//
//  Created by Kiro on 2024.
//  Copyright © 2024 Acckion. All rights reserved.
//

import XCTest
@testable import MiNoteLibrary

/// XMLNormalizer 测试
///
/// 测试 XML 规范化逻辑的一致性，确保可以用于内容比较
@MainActor
final class XMLNormalizerTests: XCTestCase {

    var normalizer: XMLNormalizer!

    override func setUp() async throws {
        normalizer = XMLNormalizer.shared
    }

    // MARK: - 基本规范化测试

    /// 测试：相同内容的规范化结果应该一致
    func testNormalizationConsistency() {
        let xml = """
        <text indent="1">测试文本</text>
        <img fileid="123" imgshow="0" width="500" height="666" />
        """

        // 多次规范化应该得到相同结果
        let result1 = normalizer.normalize(xml)
        let result2 = normalizer.normalize(xml)
        let result3 = normalizer.normalize(xml)

        XCTAssertEqual(result1, result2, "第一次和第二次规范化结果应该相同")
        XCTAssertEqual(result2, result3, "第二次和第三次规范化结果应该相同")
    }

    /// 测试：规范化是幂等的（多次规范化结果相同）
    func testNormalizationIdempotence() {
        let xml = """
        <text indent="1">测试文本</text>
        <img fileid="123" imgshow="0" width="500" height="666" />
        """

        // 第一次规范化
        let normalized1 = normalizer.normalize(xml)

        // 对规范化结果再次规范化
        let normalized2 = normalizer.normalize(normalized1)

        XCTAssertEqual(normalized1, normalized2, "规范化应该是幂等的")
    }

    // MARK: - 图片格式规范化测试

    /// 测试：移除图片尺寸属性
    func testRemoveImageSizeAttributes() {
        let xml = """
        <img fileid="123" imgshow="0" width="500" height="666" />
        """

        let normalized = normalizer.normalize(xml)

        // 验证尺寸属性被移除
        XCTAssertFalse(normalized.contains("width="), "应该移除 width 属性")
        XCTAssertFalse(normalized.contains("height="), "应该移除 height 属性")

        // 验证保留有意义的属性
        XCTAssertTrue(normalized.contains("fileid=\"123\""), "应该保留 fileid 属性")
        XCTAssertTrue(normalized.contains("imgshow=\"0\""), "应该保留 imgshow 属性")
    }

    /// 测试：移除空的 imgdes 属性
    func testRemoveEmptyImgdesAttribute() {
        let xml = """
        <img fileid="123" imgdes="" imgshow="0" />
        """

        let normalized = normalizer.normalize(xml)

        // 验证空的 imgdes 属性被移除
        XCTAssertFalse(normalized.contains("imgdes="), "应该移除空的 imgdes 属性")

        // 验证保留其他属性
        XCTAssertTrue(normalized.contains("fileid=\"123\""), "应该保留 fileid 属性")
        XCTAssertTrue(normalized.contains("imgshow=\"0\""), "应该保留 imgshow 属性")
    }

    /// 测试：保留非空的 imgdes 属性
    func testKeepNonEmptyImgdesAttribute() {
        let xml = """
        <img fileid="123" imgdes="图片描述" imgshow="0" />
        """

        let normalized = normalizer.normalize(xml)

        // 验证非空的 imgdes 属性被保留
        XCTAssertTrue(normalized.contains("imgdes=\"图片描述\""), "应该保留非空的 imgdes 属性")
    }

    /// 测试：旧版图片格式转换
    func testOldImageFormatConversion() {
        let oldFormat = "☺ 123<0/><图片描述/>"

        let normalized = normalizer.normalize(oldFormat)

        // 验证转换为新版格式
        XCTAssertTrue(normalized.contains("<img"), "应该转换为新版 img 标签")
        XCTAssertTrue(normalized.contains("fileid=\"123\""), "应该包含 fileid 属性")
        XCTAssertTrue(normalized.contains("imgshow=\"0\""), "应该包含 imgshow 属性")
        XCTAssertTrue(normalized.contains("imgdes=\"图片描述\""), "应该包含 imgdes 属性")
    }

    // MARK: - 属性顺序规范化测试

    /// 测试：属性按字母顺序排列
    func testAttributeOrderNormalization() {
        let xml1 = """
        <img width="500" fileid="123" height="666" imgshow="0" />
        """

        let xml2 = """
        <img imgshow="0" fileid="123" height="666" width="500" />
        """

        let normalized1 = normalizer.normalize(xml1)
        let normalized2 = normalizer.normalize(xml2)

        // 不同顺序的属性应该规范化为相同结果
        XCTAssertEqual(normalized1, normalized2, "不同属性顺序应该规范化为相同结果")
    }

    // MARK: - 空白字符规范化测试

    /// 测试：移除多余空格
    func testRemoveExtraWhitespace() {
        let xml = """
        <text indent="1">测试</text>

        <text indent="1">文本</text>
        """

        let normalized = normalizer.normalize(xml)

        // 验证多余空格被移除
        XCTAssertFalse(normalized.contains("  "), "不应该包含多余空格")
        XCTAssertFalse(normalized.contains("\n\n"), "不应该包含多余换行")
    }

    /// 测试：保留标签内的空格
    func testPreserveInnerWhitespace() {
        let xml = """
        <text indent="1">测试  文本</text>
        """

        let normalized = normalizer.normalize(xml)

        // 验证标签内的空格被保留
        XCTAssertTrue(normalized.contains("测试  文本"), "应该保留标签内的空格")
    }

    // MARK: - 空标签移除测试

    /// 测试：移除空的 text 标签
    func testRemoveEmptyTextTags() {
        let xml = """
        <text indent="1"></text>
        <text indent="2">有内容</text>
        """

        let normalized = normalizer.normalize(xml)

        // 验证空标签被移除
        let emptyTagPattern = "<text\\s+[^>]+>\\s*</text>"
        let regex = try? NSRegularExpression(pattern: emptyTagPattern, options: [])
        let matches = regex?.matches(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length))

        XCTAssertEqual(matches?.count ?? 0, 0, "不应该包含空的 text 标签")

        // 验证有内容的标签被保留
        XCTAssertTrue(normalized.contains("有内容"), "应该保留有内容的标签")
    }

    // MARK: - 属性值规范化测试

    /// 测试：统一布尔值表示
    func testBooleanValueNormalization() {
        let xml1 = """
        <checkbox checked="true" />
        """

        let xml2 = """
        <checkbox checked="1" />
        """

        let normalized1 = normalizer.normalize(xml1)
        let normalized2 = normalizer.normalize(xml2)

        // true 应该转换为 1
        XCTAssertEqual(normalized1, normalized2, "true 和 1 应该规范化为相同结果")
        XCTAssertTrue(normalized1.contains("checked=\"1\""), "true 应该转换为 1")
    }

    /// 测试：移除数字前导零
    func testRemoveLeadingZeros() {
        let xml1 = """
        <text indent="01">测试</text>
        """

        let xml2 = """
        <text indent="1">测试</text>
        """

        let normalized1 = normalizer.normalize(xml1)
        let normalized2 = normalizer.normalize(xml2)

        // 前导零应该被移除
        XCTAssertEqual(normalized1, normalized2, "01 和 1 应该规范化为相同结果")
        XCTAssertTrue(normalized1.contains("indent=\"1\""), "应该移除前导零")
    }

    // MARK: - 综合测试

    /// 测试：复杂内容的规范化一致性
    func testComplexContentNormalization() {
        let xml1 = """
        <text indent="01">测试文本</text>

        <img width="500" fileid="123" height="666" imgshow="0" imgdes="" />
        <text indent="2">  更多内容  </text>
        """

        let xml2 = """
        <text indent="1">测试文本</text>
        <img fileid="123" imgshow="0" />
        <text indent="2">  更多内容  </text>
        """

        let normalized1 = normalizer.normalize(xml1)
        let normalized2 = normalizer.normalize(xml2)

        // 语义相同的内容应该规范化为相同结果
        XCTAssertEqual(normalized1, normalized2, "语义相同的内容应该规范化为相同结果")
    }

    /// 测试：空内容的规范化
    func testEmptyContentNormalization() {
        let empty1 = ""
        let empty2 = "   "
        let empty3 = "\n\n"

        let normalized1 = normalizer.normalize(empty1)
        let normalized2 = normalizer.normalize(empty2)
        let normalized3 = normalizer.normalize(empty3)

        // 所有空内容应该规范化为空字符串
        XCTAssertEqual(normalized1, "", "空字符串应该保持为空")
        XCTAssertEqual(normalized2, "", "只包含空格的字符串应该规范化为空")
        XCTAssertEqual(normalized3, "", "只包含换行的字符串应该规范化为空")
    }

    // MARK: - 性能测试

    /// 测试：规范化性能
    func testNormalizationPerformance() {
        // 生成一个较大的 XML 内容
        var largeXML = ""
        for i in 0 ..< 100 {
            largeXML += "<text indent=\"\(i % 5)\">这是第 \(i) 行测试文本</text>\n"
            if i % 10 == 0 {
                largeXML += "<img fileid=\"img\(i)\" imgshow=\"0\" width=\"500\" height=\"666\" />\n"
            }
        }

        // 测量规范化性能
        measure {
            _ = normalizer.normalize(largeXML)
        }
    }
}
