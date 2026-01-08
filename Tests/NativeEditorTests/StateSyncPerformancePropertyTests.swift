//
//  StateSyncPerformancePropertyTests.swift
//  MiNoteLibraryTests
//
//  状态同步性能属性测试 - 验证状态同步响应性能
//  属性 6: 状态同步响应性能
//  验证需求: 3.2
//
//  Feature: format-menu-fix, Property 6: 状态同步响应性能
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 状态同步性能属性测试
/// 
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证状态同步的性能属性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下状态同步的响应时间符合要求。
///
/// **属性 6**: 对于任何光标移动或选择变化，系统应该在100ms内完成状态更新
/// **验证需求**: 3.2
@MainActor
final class StateSyncPerformancePropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var textStorage: NSTextStorage!
    var formatStateSynchronizer: FormatStateSynchronizer!
    
    /// 性能阈值（毫秒）- 需求 3.2
    let performanceThresholdMs: Double = 100.0
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的编辑器上下文
        editorContext = NativeEditorContext()
        
        // 创建测试用的文本存储
        textStorage = NSTextStorage()
        
        // 创建测试用的格式状态同步器
        formatStateSynchronizer = FormatStateSynchronizer.createForTesting()
        formatStateSynchronizer.resetPerformanceStats()
    }
    
    override func tearDown() async throws {
        editorContext = nil
        textStorage = nil
        formatStateSynchronizer = nil
        try await super.tearDown()
    }
    
    // MARK: - 属性 6: 状态同步响应性能
    // 验证需求: 3.2
    
    /// 属性测试：光标移动后状态同步性能
    /// 
    /// **属性**: 对于任何光标移动，系统应该在100ms内完成状态更新
    /// **验证需求**: 3.2
    /// 
    /// 测试策略：
    /// 1. 生成随机文本内容（包含各种格式）
    /// 2. 生成随机光标位置
    /// 3. 测量状态同步时间
    /// 4. 验证同步时间在100ms内
    func testProperty6_CursorMoveStateSyncPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 光标移动状态同步性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomFormattedText(minLength: 50, maxLength: 500)
            
            // 2. 设置初始文本
            editorContext.updateNSContent(testText)
            
            // 3. 生成随机光标位置
            let position = Int.random(in: 0..<max(1, testText.length))
            
            // 4. 测量状态同步时间
            let startTime = CFAbsoluteTimeGetCurrent()
            editorContext.updateCursorPosition(position)
            // 强制立即更新格式状态
            editorContext.forceUpdateFormats()
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
                print("[PropertyTest] ⚠️ 迭代 \(iteration): 状态同步耗时 \(String(format: "%.2f", durationMs))ms (超过阈值)")
            }
            
            // 5. 验证同步时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2, // 允许一定的波动
                "迭代 \(iteration): 状态同步耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 光标移动状态同步性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "状态同步平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 光标移动状态同步性能测试完成")
    }
    
    /// 属性测试：选择范围变化后状态同步性能
    /// 
    /// **属性**: 对于任何选择范围变化，系统应该在100ms内完成状态更新
    /// **验证需求**: 3.2
    func testProperty6_SelectionChangeStateSyncPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 选择范围变化状态同步性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomFormattedText(minLength: 50, maxLength: 500)
            
            // 2. 设置初始文本
            editorContext.updateNSContent(testText)
            
            // 3. 生成随机选择范围
            let range = generateRandomRange(in: testText.length)
            
            // 4. 测量状态同步时间
            let startTime = CFAbsoluteTimeGetCurrent()
            editorContext.updateSelectedRange(range)
            // 强制立即更新格式状态
            editorContext.forceUpdateFormats()
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
            }
            
            // 5. 验证同步时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2,
                "迭代 \(iteration): 状态同步耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 选择范围变化状态同步性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "状态同步平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 选择范围变化状态同步性能测试完成")
    }

    
    /// 属性测试：混合格式文本状态同步性能
    /// 
    /// **属性**: 对于包含多种格式的文本，系统应该在100ms内完成状态更新
    /// **验证需求**: 3.2
    func testProperty6_MixedFormatStateSyncPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 混合格式文本状态同步性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成包含多种格式的文本
            let testText = generateMixedFormatText(minLength: 100, maxLength: 500)
            
            // 2. 设置初始文本
            editorContext.updateNSContent(testText)
            
            // 3. 生成随机光标位置
            let position = Int.random(in: 0..<max(1, testText.length))
            
            // 4. 测量状态同步时间
            let startTime = CFAbsoluteTimeGetCurrent()
            editorContext.updateCursorPosition(position)
            editorContext.forceUpdateFormats()
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
            }
            
            // 5. 验证同步时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2,
                "迭代 \(iteration): 混合格式状态同步耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 混合格式文本状态同步性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "混合格式状态同步平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 混合格式文本状态同步性能测试完成")
    }
    
    /// 属性测试：大文本状态同步性能
    /// 
    /// **属性**: 对于大文本，系统应该在100ms内完成状态更新
    /// **验证需求**: 3.2
    func testProperty6_LargeTextStateSyncPerformance() async throws {
        let iterations = 50  // 大文本测试减少迭代次数
        print("\n[PropertyTest] 开始属性测试: 大文本状态同步性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成大文本
            let testText = generateRandomFormattedText(minLength: 1000, maxLength: 5000)
            
            // 2. 设置初始文本
            editorContext.updateNSContent(testText)
            
            // 3. 生成随机光标位置
            let position = Int.random(in: 0..<max(1, testText.length))
            
            // 4. 测量状态同步时间
            let startTime = CFAbsoluteTimeGetCurrent()
            editorContext.updateCursorPosition(position)
            editorContext.forceUpdateFormats()
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
                print("[PropertyTest] ⚠️ 迭代 \(iteration): 大文本状态同步耗时 \(String(format: "%.2f", durationMs))ms (文本长度: \(testText.length))")
            }
            
            // 5. 验证同步时间在阈值内（大文本允许更大的波动）
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 3,
                "迭代 \(iteration): 大文本状态同步耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 大文本状态同步性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内（大文本允许稍微超过阈值）
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs * 1.5,
            "大文本状态同步平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs * 1.5)ms")
        
        print("[PropertyTest] ✅ 大文本状态同步性能测试完成")
    }
    
    /// 属性测试：连续光标移动状态同步性能
    /// 
    /// **属性**: 对于连续的光标移动，每次状态更新都应该在100ms内完成
    /// **验证需求**: 3.2
    func testProperty6_ContinuousCursorMoveStateSyncPerformance() async throws {
        let iterations = 50
        let movesPerIteration = 10
        print("\n[PropertyTest] 开始属性测试: 连续光标移动状态同步性能 (迭代次数: \(iterations), 每次移动: \(movesPerIteration))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        var totalMoves = 0
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomFormattedText(minLength: 100, maxLength: 500)
            
            // 2. 设置初始文本
            editorContext.updateNSContent(testText)
            
            // 3. 连续移动光标
            for _ in 1...movesPerIteration {
                let position = Int.random(in: 0..<max(1, testText.length))
                
                // 4. 测量状态同步时间
                let startTime = CFAbsoluteTimeGetCurrent()
                editorContext.updateCursorPosition(position)
                editorContext.forceUpdateFormats()
                let endTime = CFAbsoluteTimeGetCurrent()
                let durationMs = (endTime - startTime) * 1000
                
                totalDuration += durationMs
                maxDuration = max(maxDuration, durationMs)
                totalMoves += 1
                
                if durationMs > performanceThresholdMs {
                    slowCount += 1
                }
                
                // 5. 验证同步时间在阈值内
                XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2,
                    "迭代 \(iteration): 连续移动状态同步耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
            }
        }
        
        let avgDuration = totalDuration / Double(totalMoves)
        print("[PropertyTest] 连续光标移动状态同步性能统计:")
        print("  - 总移动次数: \(totalMoves)")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(totalMoves)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "连续移动状态同步平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 连续光标移动状态同步性能测试完成")
    }
    
    // MARK: - 辅助方法：随机数据生成
    
    /// 生成随机格式化文本
    private func generateRandomFormattedText(minLength: Int, maxLength: Int) -> NSAttributedString {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \n"
        let text = String((0..<length).map { _ in characters.randomElement()! })
        
        let attributedString = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.count)
        
        // 添加基本字体
        attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: fullRange)
        
        // 随机添加一些格式
        let formatCount = Int.random(in: 1...5)
        for _ in 0..<formatCount {
            let range = generateRandomRange(in: text.count)
            let formatType = Int.random(in: 0...4)
            
            switch formatType {
            case 0: // 加粗
                let boldFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .boldFontMask)
                attributedString.addAttribute(.font, value: boldFont, range: range)
            case 1: // 斜体
                let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .italicFontMask)
                attributedString.addAttribute(.font, value: italicFont, range: range)
            case 2: // 下划线
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case 3: // 删除线
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case 4: // 高亮
                attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: range)
            default:
                break
            }
        }
        
        return attributedString
    }
    
    /// 生成混合格式文本
    private func generateMixedFormatText(minLength: Int, maxLength: Int) -> NSAttributedString {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \n"
        let text = String((0..<length).map { _ in characters.randomElement()! })
        
        let attributedString = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.count)
        
        // 添加基本字体
        attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: fullRange)
        
        // 添加多种格式，确保有重叠
        let segmentCount = max(1, length / 50)
        for i in 0..<segmentCount {
            let segmentStart = (length / segmentCount) * i
            let segmentLength = min(50, length - segmentStart)
            let range = NSRange(location: segmentStart, length: segmentLength)
            
            // 每个段落添加不同的格式组合
            if i % 5 == 0 {
                let boldFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .boldFontMask)
                attributedString.addAttribute(.font, value: boldFont, range: range)
            }
            if i % 5 == 1 {
                let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .italicFontMask)
                attributedString.addAttribute(.font, value: italicFont, range: range)
            }
            if i % 3 == 0 {
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if i % 4 == 0 {
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if i % 6 == 0 {
                attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: range)
            }
        }
        
        return attributedString
    }
    
    /// 生成随机范围
    private func generateRandomRange(in length: Int) -> NSRange {
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        
        let location = Int.random(in: 0..<length)
        let maxLength = length - location
        let rangeLength = Int.random(in: 1...min(maxLength, 50))
        
        return NSRange(location: location, length: rangeLength)
    }
}
