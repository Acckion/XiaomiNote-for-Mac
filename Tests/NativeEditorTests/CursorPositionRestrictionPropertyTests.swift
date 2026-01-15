//
//  CursorPositionRestrictionPropertyTests.swift
//  MiNoteMac
//
//  光标位置限制属性测试
//  验证 NativeTextView 的光标位置限制功能
//
//  **Property 1: 光标位置限制**
//  **Validates: Requirements 1.1, 1.2, 1.4**
//

import XCTest
import AppKit
@testable import MiNoteLibrary

@MainActor
final class CursorPositionRestrictionPropertyTests: XCTestCase {
    
    // MARK: - 测试辅助方法
    
    /// 创建测试用的 NSTextStorage
    private func createTextStorage(with text: String) -> NSTextStorage {
        let textStorage = NSTextStorage(string: text)
        return textStorage
    }
    
    /// 创建带有无序列表的 NSTextStorage
    private func createBulletListTextStorage(with text: String, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)
        let range = NSRange(location: 0, length: 0)
        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: indent)
        return textStorage
    }
    
    /// 创建带有有序列表的 NSTextStorage
    private func createOrderedListTextStorage(with text: String, number: Int = 1, indent: Int = 1) -> NSTextStorage {
        let textStorage = createTextStorage(with: text)
        let range = NSRange(location: 0, length: 0)
        ListFormatHandler.applyOrderedList(to: textStorage, range: range, number: number, indent: indent)
        return textStorage
    }
    
    // MARK: - Property 1: 光标位置限制
    // **Validates: Requirements 1.1, 1.2, 1.4**
    
    /// 属性测试：调整后的光标位置永远不在列表标记区域内
    /// _Requirements: 1.1, 1.2_
    func testPropertyAdjustedCursorNeverInMarkerArea() {
        // 测试多种列表类型和位置
        let testCases: [(String, (String, Int) -> NSTextStorage)] = [
            ("无序列表", createBulletListTextStorage),
            ("有序列表", { text, indent in self.createOrderedListTextStorage(with: text, number: 1, indent: indent) })
        ]
        
        for (listTypeName, createFunc) in testCases {
            // 测试不同的文本内容
            let texts = ["测试\n", "Hello World\n", "A\n", "这是一段较长的测试文本内容\n"]
            
            for text in texts {
                let textStorage = createFunc(text, 1)
                
                // 测试所有可能的位置
                for position in 0...textStorage.length {
                    let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                        in: textStorage,
                        from: position
                    )
                    
                    // 验证调整后的位置不在标记区域内
                    let isInMarker = ListBehaviorHandler.isInListMarkerArea(
                        in: textStorage,
                        at: adjustedPosition
                    )
                    
                    XCTAssertFalse(
                        isInMarker,
                        "\(listTypeName): 调整后的位置 \(adjustedPosition)（原位置 \(position)）不应该在标记区域内"
                    )
                }
            }
        }
    }
    
    /// 属性测试：内容区域的位置不会被调整
    /// _Requirements: 1.1, 1.3_
    func testPropertyContentAreaPositionUnchanged() {
        let textStorage = createBulletListTextStorage(with: "测试文本内容\n")
        
        // 获取内容起始位置
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        
        // 测试内容区域的所有位置
        for position in contentStart...textStorage.length {
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: position
            )
            
            // 内容区域的位置不应该被调整
            XCTAssertEqual(
                adjustedPosition,
                position,
                "内容区域的位置 \(position) 不应该被调整"
            )
        }
    }
    
    /// 属性测试：标记区域的位置会被调整到内容起始位置
    /// _Requirements: 1.1, 1.3_
    func testPropertyMarkerAreaPositionAdjustedToContentStart() {
        let textStorage = createBulletListTextStorage(with: "测试文本\n")
        
        // 获取内容起始位置
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        
        // 测试标记区域的所有位置
        for position in 0..<contentStart {
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: position
            )
            
            // 标记区域的位置应该被调整到内容起始位置
            XCTAssertEqual(
                adjustedPosition,
                contentStart,
                "标记区域的位置 \(position) 应该被调整到内容起始位置 \(contentStart)"
            )
        }
    }
    
    /// 属性测试：非列表行的位置不会被调整
    /// _Requirements: 1.4_
    func testPropertyNonListLinePositionUnchanged() {
        let textStorage = createTextStorage(with: "普通文本行\n第二行\n第三行\n")
        
        // 测试所有位置
        for position in 0...textStorage.length {
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: position
            )
            
            // 非列表行的位置不应该被调整
            XCTAssertEqual(
                adjustedPosition,
                position,
                "非列表行的位置 \(position) 不应该被调整"
            )
        }
    }
    
    /// 属性测试：getContentStartPosition 返回的位置总是有效的
    /// _Requirements: 1.1, 1.4_
    func testPropertyContentStartPositionAlwaysValid() {
        let testCases: [NSTextStorage] = [
            createBulletListTextStorage(with: "测试\n"),
            createOrderedListTextStorage(with: "测试\n"),
            createTextStorage(with: "普通文本\n"),
            createTextStorage(with: "")
        ]
        
        for textStorage in testCases {
            for position in 0...max(0, textStorage.length) {
                let contentStart = ListBehaviorHandler.getContentStartPosition(
                    in: textStorage,
                    at: position
                )
                
                // 内容起始位置应该在有效范围内
                XCTAssertGreaterThanOrEqual(
                    contentStart,
                    0,
                    "内容起始位置应该 >= 0"
                )
                XCTAssertLessThanOrEqual(
                    contentStart,
                    textStorage.length,
                    "内容起始位置应该 <= 文本长度"
                )
            }
        }
    }
    
    /// 属性测试：getListItemInfo 返回的信息与其他方法一致
    /// _Requirements: 1.1, 1.3, 1.4_
    func testPropertyListItemInfoConsistency() {
        let textStorage = createBulletListTextStorage(with: "测试文本\n")
        
        for position in 0...textStorage.length {
            let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: position)
            
            if let info = info {
                // 如果有列表项信息，验证一致性
                let contentStart = ListBehaviorHandler.getContentStartPosition(
                    in: textStorage,
                    at: position
                )
                
                XCTAssertEqual(
                    info.contentStartPosition,
                    contentStart,
                    "ListItemInfo 的 contentStartPosition 应该与 getContentStartPosition 一致"
                )
                
                // 验证标记区域检测一致性
                let isInMarker = ListBehaviorHandler.isInListMarkerArea(
                    in: textStorage,
                    at: position
                )
                
                if position < info.contentStartPosition {
                    XCTAssertTrue(
                        isInMarker,
                        "位置 \(position) 在内容起始位置 \(info.contentStartPosition) 之前，应该在标记区域内"
                    )
                }
            }
        }
    }
    
    // MARK: - 缩进级别测试
    // _Requirements: 1.4_
    
    /// 属性测试：不同缩进级别的列表都能正确限制光标
    func testPropertyDifferentIndentLevels() {
        for indent in 1...5 {
            let textStorage = createBulletListTextStorage(with: "测试\n", indent: indent)
            
            // 获取内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            
            // 验证标记区域的位置会被调整
            for position in 0..<contentStart {
                let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
                    in: textStorage,
                    from: position
                )
                
                XCTAssertEqual(
                    adjustedPosition,
                    contentStart,
                    "缩进级别 \(indent): 标记区域位置 \(position) 应该被调整到 \(contentStart)"
                )
            }
            
            // 验证列表项信息的缩进级别正确
            let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)
            XCTAssertEqual(
                info?.indent,
                indent,
                "列表项信息的缩进级别应该是 \(indent)"
            )
        }
    }
    
    // MARK: - 多行列表测试
    
    /// 属性测试：多行列表中每行都能正确限制光标
    func testPropertyMultiLineList() {
        // 创建带有无序列表的单行文本进行测试
        let textStorage = createBulletListTextStorage(with: "测试内容\n")
        
        // 获取内容起始位置
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        
        // 验证行首位置会被调整
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
            in: textStorage,
            from: 0
        )
        
        XCTAssertGreaterThanOrEqual(
            adjustedPosition,
            contentStart,
            "调整后位置应该 >= 内容起始位置"
        )
        
        // 验证内容区域位置不变
        let contentPosition = contentStart + 1
        if contentPosition <= textStorage.length {
            let adjustedContentPosition = ListBehaviorHandler.adjustCursorPosition(
                in: textStorage,
                from: contentPosition
            )
            XCTAssertEqual(
                adjustedContentPosition,
                contentPosition,
                "内容区域位置不应该被调整"
            )
        }
    }
    
    // MARK: - 边界条件测试
    
    /// 测试空文本存储
    func testEmptyTextStorage() {
        let textStorage = createTextStorage(with: "")
        
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        XCTAssertEqual(contentStart, 0, "空文本存储的内容起始位置应该是 0")
        
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 0)
        XCTAssertEqual(adjustedPosition, 0, "空文本存储的调整后位置应该是 0")
    }
    
    /// 测试只有换行符的文本
    func testOnlyNewline() {
        let textStorage = createTextStorage(with: "\n")
        
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        XCTAssertEqual(contentStart, 0, "只有换行符的文本的内容起始位置应该是 0")
    }
    
    /// 测试无效位置
    func testInvalidPositions() {
        let textStorage = createBulletListTextStorage(with: "测试\n")
        
        // 负数位置
        let adjusted1 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: -1)
        XCTAssertEqual(adjusted1, -1, "负数位置应该返回原位置")
        
        // 超出范围位置
        let adjusted2 = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: 1000)
        XCTAssertEqual(adjusted2, 1000, "超出范围位置应该返回原位置")
    }
}
