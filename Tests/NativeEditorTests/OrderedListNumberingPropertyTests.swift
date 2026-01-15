//
//  OrderedListNumberingPropertyTests.swift
//  MiNoteLibraryTests
//
//  有序列表编号连续性属性测试
//  Property 7: 编号连续性
//
//  Feature: list-behavior-optimization, Property 7: 编号连续性
// 
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 有序列表编号连续性属性测试
///
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证有序列表编号的连续性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下编号始终从 1 开始连续递增。
@MainActor
final class OrderedListNumberingPropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var textStorage: NSTextStorage!
    var textView: NSTextView!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500), textContainer: textContainer)
    }
    
    override func tearDown() async throws {
        textStorage = nil
        textView = nil
        try await super.tearDown()
    }
    
    // MARK: - Property 7: 编号连续性 
    
    /// 属性测试：新建有序列表编号从 1 开始
    ///
    /// **Property 7**: 对于任何新建的有序列表，编号应该从 1 开始 
    ///
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 应用有序列表格式
    /// 3. 验证编号为 1
    func testProperty7_NewOrderedListStartsFromOne() async throws {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 新建有序列表编号从 1 开始 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 5, maxLength: 30)
            let indent = Int.random(in: 1...3)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText + "\n")
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: testText.count + 1))
            textStorage.setAttributedString(attributedString)
            
            // 3. 应用有序列表格式
            ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: 0, length: 0), number: 1, indent: indent)
            
            // 4. 验证编号为 1
            let number = ListFormatHandler.getListNumber(in: textStorage, at: 0)
            XCTAssertEqual(number, 1, "迭代 \(iteration): 新建有序列表编号应该为 1，实际为 \(number)")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 新建有序列表编号测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 新建有序列表编号从 1 开始测试完成")
    }
    
    /// 属性测试：插入新列表项后编号连续递增
    ///
    /// **Property 7**: 对于任何有序列表，在插入新列表项后，编号应该连续递增 
    ///
    /// 测试策略：
    /// 1. 创建有序列表
    /// 2. 在列表中间插入新项
    /// 3. 验证所有编号连续递增
    func testProperty7_InsertionMaintainsConsecutiveNumbering() async throws {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 插入新列表项后编号连续递增 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let itemCount = Int.random(in: 2...5)
            let indent = Int.random(in: 1...3)
            
            // 2. 创建多行有序列表
            var content = ""
            for i in 1...itemCount {
                content += "列表项 \(i)\n"
            }
            
            let attributedString = NSMutableAttributedString(string: content)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: content.count))
            textStorage.setAttributedString(attributedString)
            
            // 为每一行应用有序列表格式
            let string = textStorage.string as NSString
            var position = 0
            var lineNumber = 1
            while position < textStorage.length {
                let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: lineRange.location, length: 0), number: lineNumber, indent: indent)
                position = lineRange.location + lineRange.length
                lineNumber += 1
            }
            
            // 3. 验证初始编号连续
            let initialNumbers = ListBehaviorHandler.getOrderedListNumbers(in: textStorage, at: 0)
            let expectedInitial = Array(1...itemCount)
            XCTAssertEqual(initialNumbers, expectedInitial, "迭代 \(iteration): 初始编号应该是 \(expectedInitial)，实际是 \(initialNumbers)")
            
            // 4. 在第一行末尾插入新列表项（模拟回车）
            let firstLineRange = string.lineRange(for: NSRange(location: 0, length: 0))
            let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: 0)
            
            if let info = listInfo {
                // 模拟在第一行末尾按回车
                let cursorPosition = firstLineRange.location + firstLineRange.length - 1
                textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))
                
                // 使用 splitTextAtCursor 插入新行
                let _ = ListBehaviorHandler.splitTextAtCursor(
                    textView: textView,
                    textStorage: textStorage,
                    cursorPosition: cursorPosition,
                    listInfo: info
                )
                
                // 5. 验证编号仍然连续
                let newNumbers = ListBehaviorHandler.getOrderedListNumbers(in: textStorage, at: 0)
                let expectedNew = Array(1...(itemCount + 1))
                XCTAssertEqual(newNumbers, expectedNew, "迭代 \(iteration): 插入后编号应该是 \(expectedNew)，实际是 \(newNumbers)")
                
                // 验证编号连续性
                let isConsecutive = ListBehaviorHandler.isOrderedListNumberingConsecutive(in: textStorage, at: 0)
                XCTAssertTrue(isConsecutive, "迭代 \(iteration): 编号应该连续")
            }
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 插入后编号连续性测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 插入新列表项后编号连续递增测试完成")
    }
    
    /// 属性测试：删除列表项后编号连续递增
    ///
    /// **Property 7**: 对于任何有序列表，在删除列表项后，编号应该连续递增 
    ///
    /// 测试策略：
    /// 1. 创建有序列表
    /// 2. 删除列表中的某一项
    /// 3. 验证所有编号连续递增
    func testProperty7_DeletionMaintainsConsecutiveNumbering() async throws {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 删除列表项后编号连续递增 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let itemCount = Int.random(in: 3...6)
            let indent = Int.random(in: 1...3)
            
            // 2. 创建多行有序列表
            var content = ""
            for i in 1...itemCount {
                content += "列表项 \(i)\n"
            }
            
            let attributedString = NSMutableAttributedString(string: content)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: content.count))
            textStorage.setAttributedString(attributedString)
            
            // 为每一行应用有序列表格式
            let string = textStorage.string as NSString
            var position = 0
            var lineNumber = 1
            while position < textStorage.length {
                let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: lineRange.location, length: 0), number: lineNumber, indent: indent)
                position = lineRange.location + lineRange.length
                lineNumber += 1
            }
            
            // 3. 验证初始编号连续
            let initialNumbers = ListBehaviorHandler.getOrderedListNumbers(in: textStorage, at: 0)
            let expectedInitial = Array(1...itemCount)
            XCTAssertEqual(initialNumbers, expectedInitial, "迭代 \(iteration): 初始编号应该是 \(expectedInitial)，实际是 \(initialNumbers)")
            
            // 4. 找到第二行的内容起始位置
            let firstLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let secondLineStart = firstLineRange.location + firstLineRange.length
            
            if secondLineStart < textStorage.length {
                let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: secondLineStart)
                
                if let info = listInfo {
                    // 模拟在第二行内容起始位置按删除键
                    textView.setSelectedRange(NSRange(location: info.contentStartPosition, length: 0))
                    
                    // 使用 mergeWithPreviousLine 删除行
                    let _ = ListBehaviorHandler.mergeWithPreviousLine(
                        textView: textView,
                        textStorage: textStorage,
                        listInfo: info
                    )
                    
                    // 5. 验证编号仍然连续
                    let newNumbers = ListBehaviorHandler.getOrderedListNumbers(in: textStorage, at: 0)
                    let expectedNew = Array(1...(itemCount - 1))
                    XCTAssertEqual(newNumbers, expectedNew, "迭代 \(iteration): 删除后编号应该是 \(expectedNew)，实际是 \(newNumbers)")
                    
                    // 验证编号连续性
                    let isConsecutive = ListBehaviorHandler.isOrderedListNumberingConsecutive(in: textStorage, at: 0)
                    XCTAssertTrue(isConsecutive, "迭代 \(iteration): 编号应该连续")
                }
            }
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 删除后编号连续性测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 删除列表项后编号连续递增测试完成")
    }
    
    /// 属性测试：重新编号确保从 1 开始连续递增
    ///
    /// **Property 7**: 对于任何有序列表，调用重新编号后，编号应该从 1 开始连续递增 
    ///
    /// 测试策略：
    /// 1. 创建有序列表（可能有不连续的编号）
    /// 2. 调用重新编号方法
    /// 3. 验证编号从 1 开始连续递增
    func testProperty7_RenumberingEnsuresConsecutiveFromOne() async throws {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 重新编号确保从 1 开始连续递增 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let itemCount = Int.random(in: 2...5)
            let indent = Int.random(in: 1...3)
            
            // 2. 创建多行有序列表（使用不连续的编号）
            var content = ""
            for i in 1...itemCount {
                content += "列表项 \(i)\n"
            }
            
            let attributedString = NSMutableAttributedString(string: content)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: content.count))
            textStorage.setAttributedString(attributedString)
            
            // 为每一行应用有序列表格式（使用随机不连续编号）
            let string = textStorage.string as NSString
            var position = 0
            var randomNumbers: [Int] = []
            while position < textStorage.length {
                let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
                let randomNumber = Int.random(in: 1...100)
                randomNumbers.append(randomNumber)
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: lineRange.location, length: 0), number: randomNumber, indent: indent)
                position = lineRange.location + lineRange.length
            }
            
            // 3. 调用重新编号方法
            ListBehaviorHandler.renumberOrderedListFromBeginning(in: textStorage, at: 0)
            
            // 4. 验证编号从 1 开始连续递增
            let newNumbers = ListBehaviorHandler.getOrderedListNumbers(in: textStorage, at: 0)
            let expectedNumbers = Array(1...itemCount)
            XCTAssertEqual(newNumbers, expectedNumbers, "迭代 \(iteration): 重新编号后应该是 \(expectedNumbers)，实际是 \(newNumbers)")
            
            // 验证编号连续性
            let isConsecutive = ListBehaviorHandler.isOrderedListNumberingConsecutive(in: textStorage, at: 0)
            XCTAssertTrue(isConsecutive, "迭代 \(iteration): 编号应该连续")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 重新编号测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 重新编号确保从 1 开始连续递增测试完成")
    }
    
    /// 属性测试：编号验证方法正确检测不连续编号
    ///
    /// **Property 7**: 编号验证方法应该正确检测不连续的编号 
    ///
    /// 测试策略：
    /// 1. 创建有序列表（使用不连续的编号）
    /// 2. 验证 isOrderedListNumberingConsecutive 返回 false
    /// 3. 重新编号后验证返回 true
    func testProperty7_ValidationDetectsNonConsecutiveNumbering() async throws {
        let iterations = 20
        print("\n[PropertyTest] 开始属性测试: 编号验证方法正确检测不连续编号 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let itemCount = Int.random(in: 2...5)
            let indent = Int.random(in: 1...3)
            
            // 2. 创建多行有序列表
            var content = ""
            for i in 1...itemCount {
                content += "列表项 \(i)\n"
            }
            
            let attributedString = NSMutableAttributedString(string: content)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: content.count))
            textStorage.setAttributedString(attributedString)
            
            // 为每一行应用有序列表格式（使用不连续的编号）
            let string = textStorage.string as NSString
            var position = 0
            var lineIndex = 0
            let nonConsecutiveNumbers = [1, 3, 5, 7, 9] // 不连续的编号
            while position < textStorage.length && lineIndex < nonConsecutiveNumbers.count {
                let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
                ListFormatHandler.applyOrderedList(to: textStorage, range: NSRange(location: lineRange.location, length: 0), number: nonConsecutiveNumbers[lineIndex], indent: indent)
                position = lineRange.location + lineRange.length
                lineIndex += 1
            }
            
            // 3. 验证编号不连续
            let isConsecutiveBefore = ListBehaviorHandler.isOrderedListNumberingConsecutive(in: textStorage, at: 0)
            XCTAssertFalse(isConsecutiveBefore, "迭代 \(iteration): 不连续编号应该被检测到")
            
            // 4. 重新编号
            ListBehaviorHandler.renumberOrderedListFromBeginning(in: textStorage, at: 0)
            
            // 5. 验证编号现在连续
            let isConsecutiveAfter = ListBehaviorHandler.isOrderedListNumberingConsecutive(in: textStorage, at: 0)
            XCTAssertTrue(isConsecutiveAfter, "迭代 \(iteration): 重新编号后应该连续")
            
            if iteration % 20 == 0 {
                print("[PropertyTest] 迭代 \(iteration): 编号验证测试通过")
            }
        }
        
        print("[PropertyTest] ✅ 编号验证方法正确检测不连续编号测试完成")
    }
    
    // MARK: - 辅助方法：随机数据生成
    
    /// 生成随机文本
    /// - Parameters:
    ///   - minLength: 最小长度
    ///   - maxLength: 最大长度
    /// - Returns: 随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 中文测试内容"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
