//
//  ParagraphStyleConsistencyTests.swift
//  MiNoteLibraryTests
//
//  Bug 条件探索测试 - 段落样式行距属性缺失
//  验证各段落样式创建点是否包含正确的 lineSpacing、paragraphSpacing、minimumLineHeight
//

import AppKit
import XCTest
@testable import MiNoteMac

// MARK: - Bug 条件探索测试

/// 段落样式一致性测试
///
/// 此测试验证 ParagraphStyleFactory 创建的段落样式包含正确的行距属性。
/// 修复前：直接创建 NSMutableParagraphStyle() 导致行距属性缺失（测试失败）
/// 修复后：通过 ParagraphStyleFactory 创建段落样式，确保行距属性完整（测试通过）
final class ParagraphStyleConsistencyTests: XCTestCase {

    // MARK: - 常量

    /// 期望的行间距
    private let expectedLineSpacing: CGFloat = 4

    /// 期望的段落间距
    private let expectedParagraphSpacing: CGFloat = 8

    /// 行高系数
    private let lineHeightMultiplier: CGFloat = 1.2

    // MARK: - 测试 1: NewLineHandler.buildCleanTypingAttributes 行为验证

    /// 验证 ParagraphStyleFactory.makeDefault() 包含正确的行距属性
    func testNewLineHandlerBuildCleanTypingAttributes_ShouldHaveLineSpacing() {
        let paragraphStyle = ParagraphStyleFactory.makeDefault(alignment: .left)

        XCTAssertEqual(
            paragraphStyle.lineSpacing, expectedLineSpacing,
            "NewLineHandler.buildCleanTypingAttributes 创建的段落样式 lineSpacing 应为 \(expectedLineSpacing)，实际为 \(paragraphStyle.lineSpacing)"
        )
        XCTAssertEqual(
            paragraphStyle.paragraphSpacing, expectedParagraphSpacing,
            "NewLineHandler.buildCleanTypingAttributes 创建的段落样式 paragraphSpacing 应为 \(expectedParagraphSpacing)，实际为 \(paragraphStyle.paragraphSpacing)"
        )
    }

    // MARK: - 测试 2: ParagraphManager.removeBlockFormat 行为验证

    /// 验证 ParagraphStyleFactory.makeDefault(alignment:) 包含行距属性
    func testParagraphManagerRemoveBlockFormat_ShouldHaveLineSpacing() {
        let currentAlignment: NSTextAlignment = .center
        let paragraphStyle = ParagraphStyleFactory.makeDefault(alignment: currentAlignment)

        XCTAssertEqual(
            paragraphStyle.lineSpacing, expectedLineSpacing,
            "ParagraphManager.removeBlockFormat 创建的段落样式 lineSpacing 应为 \(expectedLineSpacing)，实际为 \(paragraphStyle.lineSpacing)"
        )
        XCTAssertEqual(
            paragraphStyle.paragraphSpacing, expectedParagraphSpacing,
            "ParagraphManager.removeBlockFormat 创建的段落样式 paragraphSpacing 应为 \(expectedParagraphSpacing)，实际为 \(paragraphStyle.paragraphSpacing)"
        )
    }

    // MARK: - 测试 3: 标题字体大小的 minimumLineHeight

    /// 验证 H1 字体大小设置了正确的 minimumLineHeight
    func testHeadingParagraphStyle_ShouldHaveMinimumLineHeight() {
        let h1FontSize: CGFloat = 23
        let expectedMinLineHeight = h1FontSize * lineHeightMultiplier

        let paragraphStyle = ParagraphStyleFactory.makeDefault(
            alignment: .left,
            fontSize: h1FontSize
        )

        // 验证 minimumLineHeight
        XCTAssertGreaterThanOrEqual(
            paragraphStyle.minimumLineHeight, expectedMinLineHeight,
            "H1（\(h1FontSize)pt）段落样式的 minimumLineHeight 应 >= \(expectedMinLineHeight)，实际为 \(paragraphStyle.minimumLineHeight)"
        )
    }

    // MARK: - 测试 4: 引用块段落样式行距

    /// 验证引用块段落样式包含行距属性
    func testQuoteParagraphStyle_ShouldHaveLineSpacing() {
        let paragraphStyle = ParagraphStyleFactory.makeQuote(indent: 1)

        XCTAssertEqual(
            paragraphStyle.lineSpacing, expectedLineSpacing,
            "引用块段落样式 lineSpacing 应为 \(expectedLineSpacing)，实际为 \(paragraphStyle.lineSpacing)"
        )
        XCTAssertEqual(
            paragraphStyle.paragraphSpacing, expectedParagraphSpacing,
            "引用块段落样式 paragraphSpacing 应为 \(expectedParagraphSpacing)，实际为 \(paragraphStyle.paragraphSpacing)"
        )
    }
}
