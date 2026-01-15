//
//  TextSplitPropertyTests.swift
//  MiNoteMac
//
//  文本分割属性测试
//  验证 ListBehaviorHandler 的文本分割功能
//
//  **Feature: list-behavior-optimization, Property 2: 文本分割正确性**
//  **Validates: Requirements 2.1, 2.2, 2.3**
//

import XCTest
import AppKit
@testable import MiNoteLibrary

@MainActor
final class TextSplitPropertyTests: XCTestCase {
    
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
    
    /// 生成随机测试文本
    private func generateRandomText(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789中文测试"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    // MARK: - Property 2: 文本分割正确性
    // **Feature: list-behavior-optimization, Property 2: 文本分割正确性**
    // **Validates: Requirements 2.1, 2.2, 2.3**
    
    /// 属性测试：文本分割结果的前后文本拼接等于原始内容
    /// *For any* 有内容的列表项和任意光标位置，光标前的文本 + 光标后的文本 = 原始内容
    /// _Requirements: 2.1, 2.2, 2.3_
    func testPropertyTextSplitPreservesContent() {
        // 测试多种文本内容
        let testTexts = [
            "测试文本",
            "Hello World",
            "A",
            "这是一段较长的测试文本内容用于测试分割功能",
            "Mixed混合Content内容123"
        ]
        
        // 运行 100 次迭代
        for iteration in 0..<100 {
            // 随机选择文本或生成随机文本
            let text: String
            if iteration < testTexts.count {
                text = testTexts[iteration]
            } else {
                text = generateRandomText(length: Int.random(in: 1...50))
            }
            
            let textStorage = createBulletListTextStorage(with: text + "\n")
            
            // 获取内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            
            // 获取列表项信息
            guard let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0) else {
                XCTFail("应该能获取列表项信息")
                continue
            }
            
            let originalContent = listInfo.contentText
            
            // 测试所有可能的光标位置（在内容区域内）
            let lineRange = listInfo.lineRange
            let contentEnd = lineRange.location + lineRange.length - 1 // 不包括换行符
            
            for cursorPosition in contentStart...contentEnd {
                // 获取分割结果
                guard let splitResult = ListBehaviorHandler.getTextSplitResult(
                    in: textStorage,
                    at: cursorPosition
                ) else {
                    continue
                }
                
                // 验证：前文本 + 后文本 = 原始内容
                let combinedText = splitResult.textBefore + splitResult.textAfter
                XCTAssertEqual(
                    combinedText,
                    originalContent,
                    "迭代 \(iteration): 分割后的文本拼接应该等于原始内容。" +
                    "原始=\"\(originalContent)\", 前=\"\(splitResult.textBefore)\", 后=\"\(splitResult.textAfter)\""
                )
            }
        }
    }
    
    /// 属性测试：光标在行首时，前文本为空
    /// _Requirements: 2.8_
    func testPropertyCursorAtStartProducesEmptyBefore() {
        let testTexts = ["测试", "Hello", "内容"]
        
        for text in testTexts {
            let textStorage = createBulletListTextStorage(with: text + "\n")
            
            // 获取内容起始位置
            let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
            
            // 在内容起始位置获取分割结果
            guard let splitResult = ListBehaviorHandler.getTextSplitResult(
                in: textStorage,
                at: contentStart
            ) else {
                XCTFail("应该能获取分割结果")
                continue
            }
            
            // 验证前文本为空
            XCTAssertEqual(
                splitResult.textBefore,
                "",
                "光标在内容起始位置时，前文本应该为空"
            )
            
            // 验证后文本等于原始内容
            XCTAssertEqual(
                splitResult.textAfter,
                text,
                "光标在内容起始位置时，后文本应该等于原始内容"
            )
        }
    }
    
    /// 属性测试：光标在行尾时，后文本为空
    /// _Requirements: 2.7_
    func testPropertyCursorAtEndProducesEmptyAfter() {
        let testTexts = ["测试", "Hello", "内容"]
        
        for text in testTexts {
            let textStorage = createBulletListTextStorage(with: text + "\n")
            
            // 获取列表项信息
            guard let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0) else {
                XCTFail("应该能获取列表项信息")
                continue
            }
            
            // 计算内容结束位置（不包括换行符）
            let lineRange = listInfo.lineRange
            let contentEnd = lineRange.location + lineRange.length - 1
            
            // 在内容结束位置获取分割结果
            guard let splitResult = ListBehaviorHandler.getTextSplitResult(
                in: textStorage,
                at: contentEnd
            ) else {
                XCTFail("应该能获取分割结果")
                continue
            }
            
            // 验证后文本为空
            XCTAssertEqual(
                splitResult.textAfter,
                "",
                "光标在内容结束位置时，后文本应该为空"
            )
            
            // 验证前文本等于原始内容
            XCTAssertEqual(
                splitResult.textBefore,
                text,
                "光标在内容结束位置时，前文本应该等于原始内容"
            )
        }
    }
    
    /// 属性测试：有序列表的分割结果与无序列表一致
    /// _Requirements: 2.1, 2.2, 2.3_
    func testPropertyOrderedListSplitConsistency() {
        let text = "测试文本内容"
        
        // 创建无序列表和有序列表
        let bulletStorage = createBulletListTextStorage(with: text + "\n")
        let orderedStorage = createOrderedListTextStorage(with: text + "\n")
        
        // 获取内容起始位置
        let bulletContentStart = ListBehaviorHandler.getContentStartPosition(in: bulletStorage, at: 0)
        let orderedContentStart = ListBehaviorHandler.getContentStartPosition(in: orderedStorage, at: 0)
        
        // 获取列表项信息
        guard let bulletInfo = ListBehaviorHandler.getListItemInfo(in: bulletStorage, at: 0),
              let orderedInfo = ListBehaviorHandler.getListItemInfo(in: orderedStorage, at: 0) else {
            XCTFail("应该能获取列表项信息")
            return
        }
        
        // 验证内容文本相同
        XCTAssertEqual(
            bulletInfo.contentText,
            orderedInfo.contentText,
            "无序列表和有序列表的内容文本应该相同"
        )
        
        // 测试相同相对位置的分割结果
        let bulletLineRange = bulletInfo.lineRange
        let orderedLineRange = orderedInfo.lineRange
        
        let bulletContentEnd = bulletLineRange.location + bulletLineRange.length - 1
        let orderedContentEnd = orderedLineRange.location + orderedLineRange.length - 1
        
        // 测试中间位置
        let bulletMidPosition = bulletContentStart + (bulletContentEnd - bulletContentStart) / 2
        let orderedMidPosition = orderedContentStart + (orderedContentEnd - orderedContentStart) / 2
        
        guard let bulletSplit = ListBehaviorHandler.getTextSplitResult(in: bulletStorage, at: bulletMidPosition),
              let orderedSplit = ListBehaviorHandler.getTextSplitResult(in: orderedStorage, at: orderedMidPosition) else {
            XCTFail("应该能获取分割结果")
            return
        }
        
        // 验证分割结果一致
        XCTAssertEqual(
            bulletSplit.textBefore,
            orderedSplit.textBefore,
            "无序列表和有序列表在相同相对位置的前文本应该相同"
        )
        XCTAssertEqual(
            bulletSplit.textAfter,
            orderedSplit.textAfter,
            "无序列表和有序列表在相同相对位置的后文本应该相同"
        )
    }
    
    /// 属性测试：分割位置总是在有效范围内
    /// _Requirements: 2.1_
    func testPropertySplitPositionAlwaysValid() {
        // 运行 100 次迭代
        for _ in 0..<100 {
            let text = generateRandomText(length: Int.random(in: 1...30))
            let textStorage = createBulletListTextStorage(with: text + "\n")
            
            // 获取列表项信息
            guard let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0) else {
                continue
            }
            
            let contentStart = listInfo.contentStartPosition
            let lineRange = listInfo.lineRange
            let contentEnd = lineRange.location + lineRange.length - 1
            
            // 随机选择一个位置
            let randomPosition = Int.random(in: contentStart...contentEnd)
            
            // 获取分割结果
            guard let splitResult = ListBehaviorHandler.getTextSplitResult(
                in: textStorage,
                at: randomPosition
            ) else {
                continue
            }
            
            // 验证分割位置在有效范围内
            XCTAssertGreaterThanOrEqual(
                splitResult.cursorPosition,
                contentStart,
                "分割位置应该 >= 内容起始位置"
            )
            XCTAssertLessThanOrEqual(
                splitResult.cursorPosition,
                contentEnd,
                "分割位置应该 <= 内容结束位置"
            )
        }
    }
    
    /// 属性测试：非列表行不返回分割结果
    /// _Requirements: 2.1_
    func testPropertyNonListLineReturnsNil() {
        let textStorage = createTextStorage(with: "普通文本行\n")
        
        // 测试所有位置
        for position in 0...textStorage.length {
            let splitResult = ListBehaviorHandler.getTextSplitResult(
                in: textStorage,
                at: position
            )
            
            XCTAssertNil(
                splitResult,
                "非列表行不应该返回分割结果"
            )
        }
    }
    
    // MARK: - createNewListItem 测试
    // _Requirements: 2.4, 2.5, 2.6_
    
    /// 属性测试：创建的新列表项包含正确的文本
    /// _Requirements: 2.4_
    func testPropertyNewListItemContainsCorrectText() {
        let testTexts = ["测试", "Hello", "内容123", ""]
        
        for text in testTexts {
            // 测试无序列表
            let bulletItem = ListBehaviorHandler.createNewListItem(
                listType: .bullet,
                indent: 1,
                number: 1,
                textAfter: text
            )
            
            // 验证包含文本（附件占用 1 个字符）
            let bulletString = bulletItem.string
            XCTAssertTrue(
                bulletString.contains(text) || text.isEmpty,
                "无序列表项应该包含文本 \"\(text)\""
            )
            
            // 测试有序列表
            let orderedItem = ListBehaviorHandler.createNewListItem(
                listType: .ordered,
                indent: 1,
                number: 5,
                textAfter: text
            )
            
            let orderedString = orderedItem.string
            XCTAssertTrue(
                orderedString.contains(text) || text.isEmpty,
                "有序列表项应该包含文本 \"\(text)\""
            )
        }
    }
    
    /// 属性测试：创建的新列表项具有正确的列表类型属性
    /// _Requirements: 2.4, 2.5_
    func testPropertyNewListItemHasCorrectType() {
        let listTypes: [MiNoteLibrary.ListType] = [.bullet, .ordered, .checkbox]
        
        for listType in listTypes {
            let item = ListBehaviorHandler.createNewListItem(
                listType: listType,
                indent: 1,
                number: 1,
                textAfter: "测试"
            )
            
            // 检查列表类型属性
            if item.length > 0 {
                var effectiveRange = NSRange()
                let attrs = item.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualType = attrs[.listType] as? MiNoteLibrary.ListType
                
                XCTAssertEqual(
                    actualType,
                    listType,
                    "新列表项的类型应该是 \(listType)"
                )
            }
        }
    }
    
    /// 属性测试：有序列表的新项具有正确的编号
    /// _Requirements: 2.5_
    func testPropertyOrderedListNewItemHasCorrectNumber() {
        // 测试不同的编号
        for number in 1...10 {
            let item = ListBehaviorHandler.createNewListItem(
                listType: .ordered,
                indent: 1,
                number: number,
                textAfter: "测试"
            )
            
            // 检查编号属性
            if item.length > 0 {
                var effectiveRange = NSRange()
                let attrs = item.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualNumber = attrs[.listNumber] as? Int
                
                XCTAssertEqual(
                    actualNumber,
                    number,
                    "有序列表新项的编号应该是 \(number)"
                )
            }
        }
    }
    
    /// 属性测试：勾选框列表的新项默认为未勾选状态
    /// _Requirements: 2.6_
    func testPropertyCheckboxNewItemIsUnchecked() {
        let item = ListBehaviorHandler.createNewListItem(
            listType: .checkbox,
            indent: 1,
            number: 1,
            textAfter: "测试"
        )
        
        // 检查勾选状态属性
        if item.length > 0 {
            var effectiveRange = NSRange()
            let attrs = item.attributes(at: 0, effectiveRange: &effectiveRange)
            let isChecked = attrs[.checkboxChecked] as? Bool
            
            XCTAssertEqual(
                isChecked,
                false,
                "勾选框列表新项应该默认为未勾选状态"
            )
        }
    }
    
    /// 属性测试：新列表项继承正确的缩进级别
    /// _Requirements: 2.4_
    func testPropertyNewListItemInheritsIndent() {
        for indent in 1...5 {
            let item = ListBehaviorHandler.createNewListItem(
                listType: .bullet,
                indent: indent,
                number: 1,
                textAfter: "测试"
            )
            
            // 检查缩进属性
            if item.length > 0 {
                var effectiveRange = NSRange()
                let attrs = item.attributes(at: 0, effectiveRange: &effectiveRange)
                let actualIndent = attrs[.listIndent] as? Int
                
                XCTAssertEqual(
                    actualIndent,
                    indent,
                    "新列表项的缩进级别应该是 \(indent)"
                )
            }
        }
    }
    
    // MARK: - 边界条件测试
    
    /// 测试空列表项的分割
    func testEmptyListItemSplit() {
        let textStorage = createBulletListTextStorage(with: "\n")
        
        // 获取列表项信息
        let info = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)
        
        XCTAssertNotNil(info, "应该能获取空列表项信息")
        XCTAssertTrue(info?.isEmpty ?? false, "空列表项的 isEmpty 应该为 true")
    }
    
    /// 测试单字符内容的分割
    func testSingleCharacterSplit() {
        let textStorage = createBulletListTextStorage(with: "A\n")
        
        // 获取内容起始位置
        let contentStart = ListBehaviorHandler.getContentStartPosition(in: textStorage, at: 0)
        
        // 在字符前分割
        let splitBefore = ListBehaviorHandler.getTextSplitResult(in: textStorage, at: contentStart)
        XCTAssertEqual(splitBefore?.textBefore, "", "字符前分割的前文本应该为空")
        XCTAssertEqual(splitBefore?.textAfter, "A", "字符前分割的后文本应该是 'A'")
        
        // 在字符后分割
        let splitAfter = ListBehaviorHandler.getTextSplitResult(in: textStorage, at: contentStart + 1)
        XCTAssertEqual(splitAfter?.textBefore, "A", "字符后分割的前文本应该是 'A'")
        XCTAssertEqual(splitAfter?.textAfter, "", "字符后分割的后文本应该为空")
    }
    
    /// 测试包含特殊字符的分割
    func testSpecialCharactersSplit() {
        let specialTexts = ["Hello\tWorld", "Line1", "中文English混合", "🎉Emoji测试"]
        
        for text in specialTexts {
            let textStorage = createBulletListTextStorage(with: text + "\n")
            
            guard let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0) else {
                continue
            }
            
            let contentStart = listInfo.contentStartPosition
            let lineRange = listInfo.lineRange
            let contentEnd = lineRange.location + lineRange.length - 1
            
            // 测试中间位置
            let midPosition = contentStart + (contentEnd - contentStart) / 2
            
            guard let splitResult = ListBehaviorHandler.getTextSplitResult(
                in: textStorage,
                at: midPosition
            ) else {
                continue
            }
            
            // 验证拼接后等于原始内容
            let combined = splitResult.textBefore + splitResult.textAfter
            XCTAssertEqual(
                combined,
                text,
                "特殊字符文本分割后拼接应该等于原始内容"
            )
        }
    }
}
