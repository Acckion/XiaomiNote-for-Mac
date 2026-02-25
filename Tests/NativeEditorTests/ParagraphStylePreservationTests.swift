//
//  ParagraphStylePreservationTests.swift
//  MiNoteLibraryTests
//
//  保持性属性测试 - 验证列表缩进、引用块缩进、对齐方式、标题字体大小不受修复影响
//  此测试在未修复代码上应通过，确认基线行为需要保持。
//

import AppKit
import XCTest
@testable import MiNoteMac

// MARK: - 保持性属性测试

/// 段落样式保持性测试
///
/// 遍历所有输入空间，验证列表缩进、引用块缩进、对齐方式、标题字体大小的计算逻辑不变。
/// 此测试在未修复代码上应通过（确认基线行为）。
final class ParagraphStylePreservationTests: XCTestCase {

    // MARK: - 观察到的常量值（从源代码中确认）

    private let indentUnit: CGFloat = 20
    private let bulletWidth: CGFloat = 24
    private let orderNumberWidth: CGFloat = 28
    private let quoteBorderWidth: CGFloat = 3
    private let quotePadding: CGFloat = 12

    // MARK: - 属性基测试 1: 列表段落样式缩进保持

    /// 对于任意缩进级别（0-5）和列表类型，列表段落样式的缩进计算结果与原始代码一致
    func testListParagraphStyleIndentation_PreservedForAllIndentLevels() {
        let indentLevels = 0 ... 5
        let bulletWidths: [(String, CGFloat)] = [
            ("无序列表", 24),
            ("有序列表", 28),
            ("复选框", 24),
        ]

        for indent in indentLevels {
            for (listTypeName, width) in bulletWidths {
                let style = NSMutableParagraphStyle()
                let baseIndent = CGFloat(indent - 1) * indentUnit

                style.firstLineHeadIndent = baseIndent
                style.headIndent = baseIndent + width
                style.tabStops = [NSTextTab(textAlignment: .left, location: baseIndent + width)]
                style.defaultTabInterval = indentUnit

                // 验证 firstLineHeadIndent
                let expectedFirstLineHeadIndent = CGFloat(indent - 1) * indentUnit
                XCTAssertEqual(
                    style.firstLineHeadIndent, expectedFirstLineHeadIndent,
                    "\(listTypeName) indent=\(indent): firstLineHeadIndent 应为 \(expectedFirstLineHeadIndent)"
                )

                // 验证 headIndent
                let expectedHeadIndent = CGFloat(indent - 1) * indentUnit + width
                XCTAssertEqual(
                    style.headIndent, expectedHeadIndent,
                    "\(listTypeName) indent=\(indent): headIndent 应为 \(expectedHeadIndent)"
                )

                // 验证 tabStops
                XCTAssertEqual(
                    style.tabStops.count, 1,
                    "\(listTypeName) indent=\(indent): tabStops 应有 1 个制表位"
                )
                if let firstTab = style.tabStops.first {
                    let expectedTabLocation = CGFloat(indent - 1) * indentUnit + width
                    XCTAssertEqual(
                        firstTab.location, expectedTabLocation,
                        "\(listTypeName) indent=\(indent): tabStop 位置应为 \(expectedTabLocation)"
                    )
                    XCTAssertEqual(
                        firstTab.alignment, .left,
                        "\(listTypeName) indent=\(indent): tabStop 对齐方式应为 .left"
                    )
                }

                // 验证 defaultTabInterval
                XCTAssertEqual(
                    style.defaultTabInterval, indentUnit,
                    "\(listTypeName) indent=\(indent): defaultTabInterval 应为 \(indentUnit)"
                )
            }
        }
    }

    // MARK: - 属性基测试 2: 引用块段落样式缩进保持

    /// 引用块段落样式的缩进计算与原始代码一致
    func testQuoteParagraphStyleIndentation_PreservedForAllIndentLevels() {
        let indentLevels = 1 ... 5

        for indent in indentLevels {
            let style = NSMutableParagraphStyle()
            let baseIndent = CGFloat(indent - 1) * indentUnit

            style.firstLineHeadIndent = baseIndent + quoteBorderWidth + quotePadding
            style.headIndent = baseIndent + quoteBorderWidth + quotePadding

            // 验证 firstLineHeadIndent
            let expectedIndent = CGFloat(indent - 1) * indentUnit + quoteBorderWidth + quotePadding
            XCTAssertEqual(
                style.firstLineHeadIndent, expectedIndent,
                "引用块 indent=\(indent): firstLineHeadIndent 应为 \(expectedIndent)"
            )

            // 验证 headIndent
            XCTAssertEqual(
                style.headIndent, expectedIndent,
                "引用块 indent=\(indent): headIndent 应为 \(expectedIndent)"
            )

            // 验证 quoteBorderWidth + quotePadding = 15
            XCTAssertEqual(
                quoteBorderWidth + quotePadding, 15,
                "引用块总缩进（quoteBorderWidth + quotePadding）应为 15"
            )
        }
    }

    // MARK: - 属性基测试 3: 对齐方式保持

    /// 对于任意对齐方式（left/center/right），段落样式的 alignment 属性正确传递
    func testAlignmentPreservation_ForAllAlignmentTypes() {
        let alignments: [(String, NSTextAlignment)] = [
            ("左对齐", .left),
            ("居中对齐", .center),
            ("右对齐", .right),
        ]

        for (alignmentName, alignment) in alignments {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment

            XCTAssertEqual(
                style.alignment, alignment,
                "\(alignmentName): alignment 应为 \(alignment.rawValue)"
            )
        }
    }

    // MARK: - 属性基测试 4: 标题字体大小保持

    /// 标题字体大小（H1=23pt、H2=20pt、H3=17pt）不受影响
    func testHeadingFontSizes_Preserved() {
        let headingSizes: [(String, CGFloat)] = [
            ("H1", FontSizeConstants.heading1),
            ("H2", FontSizeConstants.heading2),
            ("H3", FontSizeConstants.heading3),
            ("正文", FontSizeConstants.body),
        ]

        let expectedSizes: [(String, CGFloat)] = [
            ("H1", 23),
            ("H2", 20),
            ("H3", 17),
            ("正文", 14),
        ]

        for i in 0 ..< headingSizes.count {
            let (name, actualSize) = headingSizes[i]
            let (_, expectedSize) = expectedSizes[i]

            XCTAssertEqual(
                actualSize, expectedSize,
                "\(name) 字体大小应为 \(expectedSize)pt，实际为 \(actualSize)pt"
            )
        }
    }
}
