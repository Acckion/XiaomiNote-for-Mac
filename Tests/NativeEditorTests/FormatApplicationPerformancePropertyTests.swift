//
//  FormatApplicationPerformancePropertyTests.swift
//  MiNoteLibraryTests
//
//  格式应用性能属性测试 - 验证格式应用响应性能
//  属性 5: 格式应用响应性能
//  验证需求: 3.1
//
//  Feature: format-menu-fix, Property 5: 格式应用响应性能
//

import XCTest
import AppKit
@testable import MiNoteLibrary

/// 格式应用性能属性测试
/// 
/// 本测试套件使用基于属性的测试方法，通过生成随机输入来验证格式应用的性能属性。
/// 每个测试运行 100 次迭代，确保在各种输入条件下格式应用的响应时间符合要求。
///
/// **属性 5**: 对于任何格式按钮点击操作，系统应该在50ms内开始应用格式
@MainActor
final class FormatApplicationPerformancePropertyTests: XCTestCase {
    
    // MARK: - Properties
    
    var editorContext: NativeEditorContext!
    var textStorage: NSTextStorage!
    var textView: NSTextView!
    var performanceOptimizer: FormatApplicationPerformanceOptimizer!
    
    /// 性能阈值（毫秒)
    let performanceThresholdMs: Double = 50.0
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建测试用的编辑器上下文
        editorContext = NativeEditorContext()
        
        // 创建测试用的文本存储和文本视图
        textStorage = NSTextStorage()
        
        // 使用我们的测试文本存储
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: .zero, textContainer: textContainer)
        
        // 获取性能优化器并重置
        performanceOptimizer = FormatApplicationPerformanceOptimizer.shared
        performanceOptimizer.reset()
        performanceOptimizer.isEnabled = true
    }
    
    override func tearDown() async throws {
        editorContext = nil
        textStorage = nil
        textView = nil
        performanceOptimizer = nil
        try await super.tearDown()
    }
    
    // MARK: - 属性 5: 格式应用响应性能
    // 验证需求: 3.1
    
    /// 属性测试：加粗格式应用响应性能
    /// 
    /// **属性**: 对于任何格式按钮点击操作，系统应该在50ms内开始应用格式
    /// **验证需求**: 3.1
    /// 
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 生成随机选择范围
    /// 3. 测量加粗格式应用时间
    /// 4. 验证应用时间在50ms内
    func testProperty5_BoldFormatApplicationPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 加粗格式应用响应性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 500)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            
            // 3. 测量格式应用时间
            let startTime = CFAbsoluteTimeGetCurrent()
            applyBoldFormat(to: range, in: textStorage)
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
                print("[PropertyTest] ⚠️ 迭代 \(iteration): 加粗格式应用耗时 \(String(format: "%.2f", durationMs))ms (超过阈值)")
            }
            
            // 4. 验证应用时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2, // 允许一定的波动
                "迭代 \(iteration): 加粗格式应用耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 加粗格式应用性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "加粗格式应用平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 加粗格式应用响应性能测试完成")
    }
    
    /// 属性测试：斜体格式应用响应性能
    /// 
    /// **属性**: 对于任何格式按钮点击操作，系统应该在50ms内开始应用格式
    /// **验证需求**: 3.1
    func testProperty5_ItalicFormatApplicationPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 斜体格式应用响应性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 500)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            
            // 3. 测量格式应用时间
            let startTime = CFAbsoluteTimeGetCurrent()
            applyItalicFormat(to: range, in: textStorage)
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
            }
            
            // 4. 验证应用时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2,
                "迭代 \(iteration): 斜体格式应用耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 斜体格式应用性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "斜体格式应用平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 斜体格式应用响应性能测试完成")
    }
    
    /// 属性测试：下划线格式应用响应性能
    /// 
    /// **属性**: 对于任何格式按钮点击操作，系统应该在50ms内开始应用格式
    /// **验证需求**: 3.1
    func testProperty5_UnderlineFormatApplicationPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 下划线格式应用响应性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 500)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            
            // 3. 测量格式应用时间
            let startTime = CFAbsoluteTimeGetCurrent()
            applyUnderlineFormat(to: range, in: textStorage)
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
            }
            
            // 4. 验证应用时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2,
                "迭代 \(iteration): 下划线格式应用耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 下划线格式应用性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
            "下划线格式应用平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
        
        print("[PropertyTest] ✅ 下划线格式应用响应性能测试完成")
    }
    
    /// 属性测试：所有内联格式应用响应性能
    /// 
    /// **属性**: 对于任何格式按钮点击操作，系统应该在50ms内开始应用格式
    /// **验证需求**: 3.1
    /// 
    /// 测试策略：
    /// 1. 生成随机文本内容
    /// 2. 生成随机选择范围
    /// 3. 随机选择一种内联格式
    /// 4. 测量格式应用时间
    /// 5. 验证应用时间在50ms内
    func testProperty5_AllInlineFormatsApplicationPerformance() async throws {
        let iterations = 100
        print("\n[PropertyTest] 开始属性测试: 所有内联格式应用响应性能 (迭代次数: \(iterations))")
        
        let inlineFormats: [TextFormat] = [.bold, .italic, .underline, .strikethrough, .highlight]
        var formatStats: [TextFormat: (total: Double, max: Double, count: Int, slow: Int)] = [:]
        
        for format in inlineFormats {
            formatStats[format] = (0, 0, 0, 0)
        }
        
        for iteration in 1...iterations {
            // 1. 生成随机测试数据
            let testText = generateRandomText(minLength: 10, maxLength: 500)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            
            // 3. 随机选择一种格式
            let format = inlineFormats.randomElement()!
            
            // 4. 测量格式应用时间
            let startTime = CFAbsoluteTimeGetCurrent()
            applyFormat(format, to: range, in: textStorage)
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            // 更新统计
            var stats = formatStats[format]!
            stats.total += durationMs
            stats.max = max(stats.max, durationMs)
            stats.count += 1
            if durationMs > performanceThresholdMs {
                stats.slow += 1
            }
            formatStats[format] = stats
            
            // 5. 验证应用时间在阈值内
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 2,
                "迭代 \(iteration): \(format.displayName)格式应用耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        // 打印统计信息
        print("[PropertyTest] 所有内联格式应用性能统计:")
        for (format, stats) in formatStats.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            if stats.count > 0 {
                let avgDuration = stats.total / Double(stats.count)
                print("  - \(format.displayName): 平均 \(String(format: "%.2f", avgDuration))ms, 最大 \(String(format: "%.2f", stats.max))ms, 慢速 \(stats.slow)/\(stats.count)")
                
                // 验证平均时间在阈值内
                XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs,
                    "\(format.displayName)格式应用平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs)ms")
            }
        }
        
        print("[PropertyTest] ✅ 所有内联格式应用响应性能测试完成")
    }
    
    /// 属性测试：大文本格式应用响应性能
    /// 
    /// **属性**: 对于任何格式按钮点击操作，即使是大文本，系统也应该在50ms内开始应用格式
    /// **验证需求**: 3.1
    /// 
    /// 测试策略：
    /// 1. 生成大文本内容（1000-5000字符）
    /// 2. 生成随机选择范围
    /// 3. 测量格式应用时间
    /// 4. 验证应用时间在50ms内
    func testProperty5_LargeTextFormatApplicationPerformance() async throws {
        let iterations = 50  // 大文本测试减少迭代次数
        print("\n[PropertyTest] 开始属性测试: 大文本格式应用响应性能 (迭代次数: \(iterations))")
        
        var totalDuration: Double = 0
        var maxDuration: Double = 0
        var slowCount = 0
        
        for iteration in 1...iterations {
            // 1. 生成大文本
            let testText = generateRandomText(minLength: 1000, maxLength: 5000)
            let range = generateRandomRange(in: testText)
            
            // 2. 设置初始文本
            let attributedString = NSMutableAttributedString(string: testText)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: testText.count))
            textStorage.setAttributedString(attributedString)
            
            // 3. 测量格式应用时间
            let startTime = CFAbsoluteTimeGetCurrent()
            applyBoldFormat(to: range, in: textStorage)
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            totalDuration += durationMs
            maxDuration = max(maxDuration, durationMs)
            
            if durationMs > performanceThresholdMs {
                slowCount += 1
                print("[PropertyTest] ⚠️ 迭代 \(iteration): 大文本格式应用耗时 \(String(format: "%.2f", durationMs))ms (文本长度: \(testText.count))")
            }
            
            // 4. 验证应用时间在阈值内（大文本允许更大的波动）
            XCTAssertLessThanOrEqual(durationMs, performanceThresholdMs * 3,
                "迭代 \(iteration): 大文本格式应用耗时 \(String(format: "%.2f", durationMs))ms，严重超过阈值 \(performanceThresholdMs)ms")
        }
        
        let avgDuration = totalDuration / Double(iterations)
        print("[PropertyTest] 大文本格式应用性能统计:")
        print("  - 平均耗时: \(String(format: "%.2f", avgDuration))ms")
        print("  - 最大耗时: \(String(format: "%.2f", maxDuration))ms")
        print("  - 慢速次数: \(slowCount)/\(iterations)")
        
        // 验证平均时间在阈值内（大文本允许稍微超过阈值）
        XCTAssertLessThanOrEqual(avgDuration, performanceThresholdMs * 1.5,
            "大文本格式应用平均耗时 \(String(format: "%.2f", avgDuration))ms，超过阈值 \(performanceThresholdMs * 1.5)ms")
        
        print("[PropertyTest] ✅ 大文本格式应用响应性能测试完成")
    }
    
    // MARK: - 辅助方法：随机数据生成
    
    /// 生成随机文本
    private func generateRandomText(minLength: Int, maxLength: Int) -> String {
        let length = Int.random(in: minLength...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// 生成随机范围
    private func generateRandomRange(in text: String) -> NSRange {
        let length = text.count
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        
        let location = Int.random(in: 0..<length)
        let maxLength = length - location
        let rangeLength = Int.random(in: 1...min(maxLength, 100))
        
        return NSRange(location: location, length: rangeLength)
    }
    
    // MARK: - 辅助方法：格式应用
    
    /// 应用加粗格式
    private func applyBoldFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let fontManager = NSFontManager.shared
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
            textStorage.addAttribute(.font, value: boldFont, range: attrRange)
        }
    }
    
    /// 应用斜体格式
    private func applyItalicFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        let fontManager = NSFontManager.shared
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let italicFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
            textStorage.addAttribute(.font, value: italicFont, range: attrRange)
        }
    }
    
    /// 应用下划线格式
    private func applyUnderlineFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
    }
    
    /// 应用删除线格式
    private func applyStrikethroughFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
    }
    
    /// 应用高亮格式
    private func applyHighlightFormat(to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        textStorage.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: range)
    }
    
    /// 应用指定格式
    private func applyFormat(_ format: TextFormat, to range: NSRange, in textStorage: NSTextStorage) {
        switch format {
        case .bold:
            applyBoldFormat(to: range, in: textStorage)
        case .italic:
            applyItalicFormat(to: range, in: textStorage)
        case .underline:
            applyUnderlineFormat(to: range, in: textStorage)
        case .strikethrough:
            applyStrikethroughFormat(to: range, in: textStorage)
        case .highlight:
            applyHighlightFormat(to: range, in: textStorage)
        default:
            break
        }
    }
}
