//
//  TypingOptimizer.swift
//  MiNoteMac
//
//  打字优化器 - 检测简单输入场景并跳过完整解析以提高性能
//  需求: 6.1, 6.3, 6.4
//

import Foundation
import AppKit

// MARK: - 打字优化器

/// 打字优化器
///
/// 负责检测简单输入场景并优化打字性能。通过识别简单的单字符输入，
/// 跳过完整的段落解析，从而提高打字响应速度。同时支持批量处理
/// 连续的文本变化，在用户停止输入后统一处理。
@MainActor
final class TypingOptimizer {
    
    // MARK: - Singleton
    
    static let shared = TypingOptimizer()
    
    // MARK: - 常量
    
    /// 输入停止检测延迟（秒）
    private let inputStopDelay: TimeInterval = 0.5
    
    /// 特殊格式符号集合
    private let specialFormatCharacters: Set<Character> = [
        "*",  // 加粗、斜体
        "_",  // 下划线、斜体
        "~",  // 删除线
        "`",  // 代码
        "#",  // 标题
        "-",  // 列表
        "+",  // 列表
        "[",  // 复选框、链接
        "]",  // 复选框、链接
        "!",  // 图片
        ">",  // 引用
        "|",  // 表格
    ]
    
    /// 段落结构变化字符集合
    private let structureChangeCharacters: Set<Character> = [
        "\n",  // 换行符
        "\r",  // 回车符
    ]
    
    // MARK: - Properties
    
    /// 是否启用打字优化
    var isEnabled: Bool = true
    
    /// 是否启用详细日志
    var verboseLogging: Bool = false
    
    /// 累积的文本变化
    private var accumulatedChanges: [TextChange] = []
    
    /// 批量处理定时器
    private var batchProcessTimer: Timer?
    
    /// 上次输入时间
    private var lastInputTime: Date?
    
    /// 批量处理回调
    var onBatchProcess: (([TextChange]) -> Void)?
    
    /// 简单输入检测统计
    private(set) var simpleInputCount: Int = 0
    
    /// 完整解析触发统计
    private(set) var fullParseCount: Int = 0
    
    /// 批量处理触发统计
    private(set) var batchProcessCount: Int = 0
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - 简单输入检测（任务 7.1）
    
    /// 检测是否为简单输入
    ///
    /// 简单输入的定义：
    /// 1. 单字符输入
    /// 2. 周围没有特殊格式符号
    /// 3. 不是段落结构变化字符
    ///
    /// - Parameters:
    ///   - change: 文本变化内容
    ///   - location: 变化位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否为简单输入场景
    /// - 需求: 6.1
    func isSimpleTyping(change: String, at location: Int, in textStorage: NSTextStorage) -> Bool {
        guard isEnabled else { return false }
        
        // 1. 检测单字符输入
        guard change.count == 1 else {
            if verboseLogging {
                print("[TypingOptimizer] ❌ 非简单输入: 多字符输入 (\(change.count) 字符)")
            }
            return false
        }
        
        let character = change.first!
        
        // 2. 检查是否为段落结构变化字符
        if structureChangeCharacters.contains(character) {
            if verboseLogging {
                print("[TypingOptimizer] ❌ 非简单输入: 段落结构变化字符 '\(character)'")
            }
            return false
        }
        
        // 3. 检查是否为特殊格式符号
        if specialFormatCharacters.contains(character) {
            if verboseLogging {
                print("[TypingOptimizer] ❌ 非简单输入: 特殊格式符号 '\(character)'")
            }
            return false
        }
        
        // 4. 检查周围是否有特殊格式符号
        let hasSpecialCharactersAround = checkSpecialCharactersAround(
            location: location,
            in: textStorage
        )
        
        if hasSpecialCharactersAround {
            if verboseLogging {
                print("[TypingOptimizer] ❌ 非简单输入: 周围有特殊格式符号")
            }
            return false
        }
        
        // 5. 通过所有检查，是简单输入
        simpleInputCount += 1
        
        if verboseLogging {
            print("[TypingOptimizer] ✅ 简单输入检测通过: '\(character)' at \(location)")
        }
        
        return true
    }
    
    /// 检查指定位置周围是否有特殊格式符号
    ///
    /// 检查前后各 2 个字符的范围
    ///
    /// - Parameters:
    ///   - location: 检查位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否有特殊格式符号
    private func checkSpecialCharactersAround(location: Int, in textStorage: NSTextStorage) -> Bool {
        let text = textStorage.string
        let checkRadius = 2  // 检查前后各 2 个字符
        
        // 计算检查范围
        let startIndex = max(0, location - checkRadius)
        let endIndex = min(text.count, location + checkRadius + 1)
        
        guard startIndex < endIndex else { return false }
        
        // 获取检查范围的文本
        let startStringIndex = text.index(text.startIndex, offsetBy: startIndex)
        let endStringIndex = text.index(text.startIndex, offsetBy: endIndex)
        let surroundingText = text[startStringIndex..<endStringIndex]
        
        // 检查是否包含特殊格式符号
        for character in surroundingText {
            if specialFormatCharacters.contains(character) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - 完整解析判断（任务 7.2）
    
    /// 检测是否需要完整解析
    ///
    /// 需要完整解析的情况：
    /// 1. 段落结构变化（换行符、特殊符号）
    /// 2. 元属性变化
    /// 3. 非简单输入场景
    ///
    /// - Parameters:
    ///   - change: 文本变化内容
    ///   - location: 变化位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否需要完整解析
    /// - 需求: 6.3
    func needsFullParse(change: String, at location: Int, in textStorage: NSTextStorage) -> Bool {
        guard isEnabled else { return true }
        
        // 1. 检测段落结构变化
        if hasParagraphStructureChange(change: change) {
            fullParseCount += 1
            
            if verboseLogging {
                print("[TypingOptimizer] 🔄 需要完整解析: 段落结构变化")
            }
            
            return true
        }
        
        // 2. 检测元属性变化
        if hasMetaAttributeChange(at: location, in: textStorage) {
            fullParseCount += 1
            
            if verboseLogging {
                print("[TypingOptimizer] 🔄 需要完整解析: 元属性变化")
            }
            
            return true
        }
        
        // 3. 检查是否为简单输入
        let isSimple = isSimpleTyping(change: change, at: location, in: textStorage)
        
        if !isSimple {
            fullParseCount += 1
            
            if verboseLogging {
                print("[TypingOptimizer] 🔄 需要完整解析: 非简单输入")
            }
        }
        
        return !isSimple
    }
    
    /// 检测是否有段落结构变化
    ///
    /// - Parameter change: 文本变化内容
    /// - Returns: 是否有段落结构变化
    private func hasParagraphStructureChange(change: String) -> Bool {
        // 检查是否包含换行符
        if change.contains("\n") || change.contains("\r") {
            return true
        }
        
        // 检查是否包含多个特殊格式符号（可能形成新的格式结构）
        let specialCharCount = change.filter { specialFormatCharacters.contains($0) }.count
        if specialCharCount >= 2 {
            return true
        }
        
        return false
    }
    
    /// 检测是否有元属性变化
    ///
    /// 元属性包括：段落类型、标题级别、列表类型等
    ///
    /// - Parameters:
    ///   - location: 检查位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否有元属性变化
    private func hasMetaAttributeChange(at location: Int, in textStorage: NSTextStorage) -> Bool {
        guard location < textStorage.length else { return false }
        
        // 获取当前位置的属性
        let attributes = textStorage.attributes(
            at: location,
            effectiveRange: nil
        )
        
        // 检查是否有段落类型属性
        if attributes[.paragraphType] != nil {
            return true
        }
        
        // 检查是否有标题属性
        if attributes[.isTitle] != nil {
            return true
        }
        
        // 检查是否有列表属性
        if attributes[.listType] != nil || attributes[.listLevel] != nil {
            return true
        }
        
        return false
    }
    
    // MARK: - 批量处理机制（任务 7.3）
    
    /// 累积文本变化
    ///
    /// 将连续的文本变化累积起来，等待批量处理
    ///
    /// - Parameters:
    ///   - change: 文本变化内容
    ///   - location: 变化位置
    ///   - textStorage: 文本存储
    /// - 需求: 6.4
    func accumulateChange(change: String, at location: Int, in textStorage: NSTextStorage) {
        guard isEnabled else { return }
        
        // 记录变化
        let textChange = TextChange(
            content: change,
            location: location,
            timestamp: Date()
        )
        
        accumulatedChanges.append(textChange)
        lastInputTime = Date()
        
        if verboseLogging {
            print("[TypingOptimizer] 📝 累积变化: '\(change)' at \(location), 总计: \(accumulatedChanges.count)")
        }
        
        // 重置定时器
        resetBatchProcessTimer()
    }
    
    /// 重置批量处理定时器
    ///
    /// 使用定时器检测用户输入停止
    private func resetBatchProcessTimer() {
        // 取消现有定时器
        batchProcessTimer?.invalidate()
        
        // 创建新定时器
        batchProcessTimer = Timer.scheduledTimer(
            withTimeInterval: inputStopDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.processBatchedChanges()
            }
        }
    }
    
    /// 批量处理累积的变化
    ///
    /// 在用户停止输入后，批量处理所有累积的变化
    ///
    /// - 需求: 6.4
    func processBatchedChanges() {
        guard isEnabled else { return }
        guard !accumulatedChanges.isEmpty else { return }
        
        batchProcessCount += 1
        
        if verboseLogging {
            print("[TypingOptimizer] 🔄 批量处理开始: \(accumulatedChanges.count) 个变化")
        }
        
        // 调用批量处理回调
        onBatchProcess?(accumulatedChanges)
        
        // 清空累积的变化
        accumulatedChanges.removeAll()
        lastInputTime = nil
        
        if verboseLogging {
            print("[TypingOptimizer] ✅ 批量处理完成")
        }
    }
    
    /// 立即处理累积的变化
    ///
    /// 强制立即处理，不等待定时器
    func flushBatchedChanges() {
        batchProcessTimer?.invalidate()
        batchProcessTimer = nil
        processBatchedChanges()
    }
    
    /// 取消批量处理
    ///
    /// 清空累积的变化，不进行处理
    func cancelBatchProcessing() {
        batchProcessTimer?.invalidate()
        batchProcessTimer = nil
        accumulatedChanges.removeAll()
        lastInputTime = nil
        
        if verboseLogging {
            print("[TypingOptimizer] ❌ 批量处理已取消")
        }
    }
    
    // MARK: - 统计和报告
    
    /// 获取优化统计信息
    ///
    /// - Returns: 统计信息字符串
    func getStatistics() -> String {
        let totalInputs = simpleInputCount + fullParseCount
        let optimizationRate = totalInputs > 0
            ? Double(simpleInputCount) / Double(totalInputs) * 100
            : 0
        
        return """
        ========================================
        打字优化器统计
        ========================================
        
        ## 输入统计
        - 简单输入次数: \(simpleInputCount)
        - 完整解析次数: \(fullParseCount)
        - 总输入次数: \(totalInputs)
        - 优化率: \(String(format: "%.1f", optimizationRate))%
        
        ## 批量处理统计
        - 批量处理次数: \(batchProcessCount)
        - 当前累积变化: \(accumulatedChanges.count)
        - 上次输入时间: \(lastInputTime?.description ?? "无")
        
        ## 配置
        - 优化启用: \(isEnabled ? "是" : "否")
        - 输入停止延迟: \(inputStopDelay)秒
        - 详细日志: \(verboseLogging ? "是" : "否")
        
        ========================================
        """
    }
    
    /// 重置统计信息
    func resetStatistics() {
        simpleInputCount = 0
        fullParseCount = 0
        batchProcessCount = 0
        accumulatedChanges.removeAll()
        lastInputTime = nil
        
        if verboseLogging {
            print("[TypingOptimizer] 🔄 统计信息已重置")
        }
    }
    
    /// 获取当前累积的变化数量
    var accumulatedChangeCount: Int {
        return accumulatedChanges.count
    }
    
    /// 检查是否有待处理的变化
    var hasPendingChanges: Bool {
        return !accumulatedChanges.isEmpty
    }
}

// MARK: - 支持类型

/// 文本变化记录
struct TextChange {
    /// 变化内容
    let content: String
    
    /// 变化位置
    let location: Int
    
    /// 时间戳
    let timestamp: Date
}

// MARK: - 属性键扩展

extension NSAttributedString.Key {
    /// 段落类型属性键
    static let paragraphType = NSAttributedString.Key("ParagraphType")
    
    /// 是否为标题属性键
    static let isTitle = NSAttributedString.Key("IsTitle")
    
    /// 列表类型属性键
    static let listType = NSAttributedString.Key("ListType")
    
    /// 列表级别属性键
    static let listLevel = NSAttributedString.Key("ListLevel")
}
