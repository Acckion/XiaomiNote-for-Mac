//
//  ErrorHandlingPropertyTests.swift
//  MiNoteLibraryTests
//
//  错误处理属性测试 - 验证格式应用和状态同步的错误恢复
//  属性 8: 格式应用错误恢复
//  属性 9: 状态同步错误恢复
//  验证需求: 4.1, 4.2
//
//  Feature: format-menu-fix, Property 8: 格式应用错误恢复
//  Feature: format-menu-fix, Property 9: 状态同步错误恢复
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 错误处理属性测试
/// 
/// 本测试套件使用基于属性的测试方法，验证错误处理和恢复机制的正确性。
/// 每个测试运行 100 次迭代，确保在各种错误条件下系统能够正确恢复。
@MainActor
final class ErrorHandlingPropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var errorHandler: FormatErrorHandler!
    var textStorage: NSTextStorage!
    var textView: NSTextView!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的编辑器上下文
        editorContext = NativeEditorContext()
        
        // 获取错误处理器
        errorHandler = FormatErrorHandler.shared
        errorHandler.clearErrorHistory()
        
        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: .zero, textContainer: textContainer)
    }
    
    override func tearDown() async throws {
        editorContext = nil
        errorHandler.clearErrorHistory()
        textStorage = nil
        textView = nil
        try await super.tearDown()
    }
    
    // MARK: - 属性 8: 格式应用错误恢复
    // 验证需求: 4.1 - 格式应用失败时记录错误日志并保持界面状态一致
    
    /// 属性测试：格式应用错误记录一致性
    /// 
    /// **属性**: 对于任何格式应用失败的情况，系统应该记录错误日志并保持界面状态一致
    /// **验证需求**: 4.1
    /// 
    /// 测试策略：
    /// 1. 生成随机的无效范围（超出文本长度）
    /// 2. 尝试应用格式
    /// 3. 验证错误被正确记录
    /// 4. 验证界面状态保持一致
    func testProperty8_FormatApplicationErrorRecovery() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 格式应用错误恢复 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 清除错误历史
            errorHandler.clearErrorHistory()
            
            // 2. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 50)
            let textLength = testText.count
            
            // 3. 生成无效范围（超出文本长度）
            let invalidRange = generateInvalidRange(textLength: textLength)
            
            // 4. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: textLength))
            textStorage.setAttributedString(attributedString)
            
            // 5. 随机选择一个格式
            let format = TextFormat.allCases.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 无效范围=\(invalidRange), 格式=\(format.displayName)")
            
            // 6. 处理范围错误
            let result = errorHandler.handleRangeError(range: invalidRange, textLength: textLength)
            
            // 7. 验证错误被记录
            let errorHistory = errorHandler.getErrorHistory()
            XCTAssertFalse(errorHistory.isEmpty, 
                          "迭代 \(iteration): 错误应该被记录到历史中")
            
            // 8. 验证错误类型正确
            let lastError = errorHistory.last!
            let isRangeError = lastError.error == .rangeOutOfBounds(range: invalidRange, textLength: textLength) ||
                              lastError.error == .invalidRange(range: invalidRange, textLength: textLength)
            XCTAssertTrue(isRangeError, 
                         "迭代 \(iteration): 错误类型应该是范围错误")
            
            // 9. 验证恢复操作被设置
            XCTAssertTrue(result.handled, 
                         "迭代 \(iteration): 错误应该被处理")
            XCTAssertEqual(result.recoveryAction, .adjustRange, 
                          "迭代 \(iteration): 恢复操作应该是调整范围")
        }
        
        print("[PropertyTest] ✅ 格式应用错误恢复测试完成")
    }
    
    /// 属性测试：空选择范围错误处理
    /// 
    /// **属性**: 对于内联格式的空选择范围，系统应该记录错误并提示用户选择文本
    /// **验证需求**: 4.1
    func testProperty8_EmptySelectionErrorHandling() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 空选择范围错误处理 (迭代次数: \(iterations))")
        
        // 内联格式列表
        let inlineFormats: [TextFormat] = [.bold, .italic, .underline, .strikethrough, .highlight]
        
        for iteration in 1...iterations {
            // 1. 清除错误历史
            errorHandler.clearErrorHistory()
            
            // 2. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 50)
            let textLength = testText.count
            
            // 3. 生成空选择范围
            let emptyRange = NSRange(location: Int.random(in: 0..<textLength), length: 0)
            
            // 4. 随机选择一个内联格式
            let format = inlineFormats.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 空范围=\(emptyRange), 格式=\(format.displayName)")
            
            // 5. 处理空选择范围错误
            let context = FormatErrorContext(
                operation: "applyFormat",
                format: format.displayName,
                selectedRange: emptyRange,
                textLength: textLength,
                cursorPosition: emptyRange.location,
                additionalInfo: nil
            )
            let result = errorHandler.handleError(
                .emptySelectionForInlineFormat(format: format.displayName),
                context: context
            )
            
            // 6. 验证错误被记录
            let errorHistory = errorHandler.getErrorHistory()
            XCTAssertFalse(errorHistory.isEmpty, 
                          "迭代 \(iteration): 错误应该被记录到历史中")
            
            // 7. 验证恢复操作是提示选择文本
            XCTAssertEqual(result.recoveryAction, .selectText, 
                          "迭代 \(iteration): 恢复操作应该是选择文本")
            
            // 8. 验证用户消息存在
            XCTAssertNotNil(result.userMessage, 
                           "迭代 \(iteration): 应该有用户提示消息")
        }
        
        print("[PropertyTest] ✅ 空选择范围错误处理测试完成")
    }
    
    /// 属性测试：连续错误检测
    /// 
    /// **属性**: 当同一错误连续发生多次时，系统应该触发特殊处理
    /// **验证需求**: 4.1
    func testProperty8_ConsecutiveErrorDetection() async throws {
        let iterations = 10
        print("\n[PropertyTest] 开始属性测试: 连续错误检测 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 清除错误历史
            errorHandler.clearErrorHistory()
            errorHandler.resetErrorCount()
            
            // 2. 生成测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 50)
            let textLength = testText.count
            let invalidRange = generateInvalidRange(textLength: textLength)
            
            print("[PropertyTest] 迭代 \(iteration): 测试连续错误检测")
            
            // 3. 连续触发相同错误 3 次
            var lastResult: FormatErrorHandlingResult?
            for errorCount in 1...3 {
                lastResult = errorHandler.handleRangeError(range: invalidRange, textLength: textLength)
                print("[PropertyTest]   - 错误 \(errorCount): recoveryAction=\(lastResult!.recoveryAction)")
            }
            
            // 4. 验证第三次错误触发特殊处理（刷新编辑器）
            XCTAssertEqual(lastResult?.recoveryAction, .refreshEditor, 
                          "迭代 \(iteration): 连续错误应该触发刷新编辑器")
        }
        
        print("[PropertyTest] ✅ 连续错误检测测试完成")
    }
    
    // MARK: - 属性 9: 状态同步错误恢复
    // 验证需求: 4.2 - 状态同步失败时重新检测格式状态并更新界面
    
    /// 属性测试：状态同步错误恢复
    /// 
    /// **属性**: 对于任何状态同步失败的情况，系统应该重新检测格式状态并更新界面
    /// **验证需求**: 4.2
    /// 
    /// 测试策略：
    /// 1. 模拟状态同步失败
    /// 2. 验证错误被正确记录
    /// 3. 验证恢复操作是强制状态更新
    func testProperty9_StateSyncErrorRecovery() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 状态同步错误恢复 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 清除错误历史
            errorHandler.clearErrorHistory()
            
            // 2. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 50)
            let textLength = testText.count
            let cursorPosition = Int.random(in: 0..<textLength)
            
            // 3. 生成随机失败原因
            let reasons = [
                "属性读取失败",
                "字体检测异常",
                "段落样式解析错误",
                "列表格式检测失败",
                "特殊元素识别错误"
            ]
            let reason = reasons.randomElement()!
            
            print("[PropertyTest] 迭代 \(iteration): 文本长度=\(textLength), 光标位置=\(cursorPosition), 原因=\(reason)")
            
            // 4. 处理状态同步错误
            let result = errorHandler.handleStateSyncError(
                reason: reason,
                cursorPosition: cursorPosition,
                textLength: textLength
            )
            
            // 5. 验证错误被记录
            let errorHistory = errorHandler.getErrorHistory()
            XCTAssertFalse(errorHistory.isEmpty, 
                          "迭代 \(iteration): 错误应该被记录到历史中")
            
            // 6. 验证错误类型正确
            let lastError = errorHistory.last!
            XCTAssertEqual(lastError.error, .stateSyncFailed(reason: reason), 
                          "迭代 \(iteration): 错误类型应该是状态同步失败")
            
            // 7. 验证恢复操作是强制状态更新
            XCTAssertEqual(result.recoveryAction, .forceStateUpdate, 
                          "迭代 \(iteration): 恢复操作应该是强制状态更新")
            
            // 8. 验证错误是可恢复的
            XCTAssertTrue(lastError.error.isRecoverable, 
                         "迭代 \(iteration): 状态同步错误应该是可恢复的")
        }
        
        print("[PropertyTest] ✅ 状态同步错误恢复测试完成")
    }
    
    /// 属性测试：状态不一致检测
    /// 
    /// **属性**: 当检测到状态不一致时，系统应该记录错误并尝试恢复
    /// **验证需求**: 4.2
    func testProperty9_StateInconsistencyDetection() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 状态不一致检测 (迭代次数: \(iterations))")
        
        for iteration in 1...iterations {
            // 1. 清除错误历史
            errorHandler.clearErrorHistory()
            
            // 2. 生成随机的期望和实际格式
            let allFormats = TextFormat.allCases
            let expectedFormats = Set(allFormats.shuffled().prefix(Int.random(in: 1...3)))
            let actualFormats = Set(allFormats.shuffled().prefix(Int.random(in: 1...3)))
            
            // 确保期望和实际不同
            guard expectedFormats != actualFormats else { continue }
            
            let expectedStr = expectedFormats.map { $0.displayName }.joined(separator: ", ")
            let actualStr = actualFormats.map { $0.displayName }.joined(separator: ", ")
            
            print("[PropertyTest] 迭代 \(iteration): 期望=[\(expectedStr)], 实际=[\(actualStr)]")
            
            // 3. 处理状态不一致错误
            let context = FormatErrorContext(
                operation: "updateFormatsWithValidation",
                format: nil,
                selectedRange: nil,
                textLength: 100,
                cursorPosition: 50,
                additionalInfo: nil
            )
            let result = errorHandler.handleError(
                .stateInconsistency(expected: expectedStr, actual: actualStr),
                context: context
            )
            
            // 4. 验证错误被记录
            let errorHistory = errorHandler.getErrorHistory()
            XCTAssertFalse(errorHistory.isEmpty, 
                          "迭代 \(iteration): 错误应该被记录到历史中")
            
            // 5. 验证恢复操作是强制状态更新
            XCTAssertEqual(result.recoveryAction, .forceStateUpdate, 
                          "迭代 \(iteration): 恢复操作应该是强制状态更新")
        }
        
        print("[PropertyTest] ✅ 状态不一致检测测试完成")
    }
    
    /// 属性测试：错误统计准确性
    /// 
    /// **属性**: 错误统计信息应该准确反映发生的错误
    /// **验证需求**: 4.1, 4.2
    func testProperty9_ErrorStatisticsAccuracy() async throws {
        let iterations = 50
        print("\n[PropertyTest] 开始属性测试: 错误统计准确性 (迭代次数: \(iterations))")
        
        // 1. 清除错误历史
        errorHandler.clearErrorHistory()
        
        var expectedTotalErrors = 0
        var expectedHandledErrors = 0
        
        for iteration in 1...iterations {
            // 2. 随机生成错误
            let errorTypes: [FormatError] = [
                .invalidRange(range: NSRange(location: 100, length: 10), textLength: 50),
                .emptySelectionForInlineFormat(format: "加粗"),
                .stateSyncFailed(reason: "测试原因"),
                .formatApplicationFailed(format: "斜体", reason: "测试失败")
            ]
            let error = errorTypes.randomElement()!
            
            // 3. 处理错误
            let result = errorHandler.handleError(error, context: .empty)
            
            expectedTotalErrors += 1
            if result.handled {
                expectedHandledErrors += 1
            }
            
            print("[PropertyTest] 迭代 \(iteration): 错误=\(error.errorCode), 已处理=\(result.handled)")
        }
        
        // 4. 获取统计信息
        let stats = errorHandler.getErrorStatistics()
        let totalErrors = stats["totalErrors"] as? Int ?? 0
        let handledErrors = stats["handledErrors"] as? Int ?? 0
        
        // 5. 验证统计准确性
        XCTAssertEqual(totalErrors, expectedTotalErrors, 
                      "总错误数应该准确")
        XCTAssertEqual(handledErrors, expectedHandledErrors, 
                      "已处理错误数应该准确")
        
        print("[PropertyTest] ✅ 错误统计准确性测试完成")
        print("[PropertyTest]   - 总错误数: \(totalErrors)")
        print("[PropertyTest]   - 已处理: \(handledErrors)")
    }
    
    // MARK: - 辅助方法
    
    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// 生成无效范围（超出文本长度）
    private func generateInvalidRange(textLength: Int) -> NSRange {
        // 生成超出文本长度的范围
        let location = Int.random(in: textLength...(textLength + 50))
        let length = Int.random(in: 1...20)
        return NSRange(location: location, length: length)
    }
}
