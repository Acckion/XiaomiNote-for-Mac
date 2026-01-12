//
//  FormatApplicationConsistencyChecker.swift
//  MiNoteMac
//
//  格式应用一致性检查器 - 确保菜单和快捷键的格式应用效果一致
//  需求: 5.4 - 验证菜单和快捷键的格式应用效果，修复任何不一致的行为，添加一致性验证机制
//

import Foundation
import AppKit

// FormatApplicationMethod 已移至 FormatApplicationMethod.swift

/// 一致性检查专用的格式应用记录
/// 注意：与 FormatMenuDebugger 中的 FormatApplicationRecord 不同，此结构体包含更多一致性检查所需的字段
struct ConsistencyApplicationRecord {
    let method: FormatApplicationMethod
    let format: TextFormat
    let timestamp: Date
    let selectedRange: NSRange
    let textLength: Int
    let beforeState: Set<TextFormat>
    let afterState: Set<TextFormat>
    let success: Bool
    let errorMessage: String?
    
    /// 应用是否成功
    var isSuccessful: Bool {
        return success && errorMessage == nil
    }
    
    /// 格式是否被正确切换
    var isFormatToggled: Bool {
        if beforeState.contains(format) {
            // 格式之前存在，应该被移除
            return !afterState.contains(format)
        } else {
            // 格式之前不存在，应该被添加
            return afterState.contains(format)
        }
    }
}

/// 一致性检查结果
struct ConsistencyCheckResult {
    let format: TextFormat
    let menuRecord: ConsistencyApplicationRecord?
    let keyboardRecord: ConsistencyApplicationRecord?
    let isConsistent: Bool
    let inconsistencyReason: String?
    let recommendations: [String]
    
    /// 是否有足够的数据进行比较
    var hasComparisonData: Bool {
        return menuRecord != nil && keyboardRecord != nil
    }
}

/// 格式应用一致性检查器
/// 
/// 此类负责：
/// 1. 记录不同方式的格式应用操作
/// 2. 比较菜单和快捷键应用的效果
/// 3. 检测不一致的行为
/// 4. 提供修复建议
@MainActor
class FormatApplicationConsistencyChecker: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = FormatApplicationConsistencyChecker()
    
    // MARK: - Properties
    
    /// 格式应用记录历史（最多保留100条记录）
    private var applicationHistory: [ConsistencyApplicationRecord] = []
    private let maxHistoryCount = 100
    
    /// 当前检查的格式
    @Published var currentCheckingFormat: TextFormat?
    
    /// 最近的一致性检查结果
    @Published var lastConsistencyResults: [ConsistencyCheckResult] = []
    
    /// 是否启用详细日志
    var isVerboseLoggingEnabled = false
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// 记录格式应用操作
    /// - Parameters:
    ///   - method: 应用方式
    ///   - format: 格式类型
    ///   - selectedRange: 选择范围
    ///   - textLength: 文本长度
    ///   - beforeState: 应用前的格式状态
    ///   - afterState: 应用后的格式状态
    ///   - success: 是否成功
    ///   - errorMessage: 错误信息（如果有）
    func recordFormatApplication(
        method: FormatApplicationMethod,
        format: TextFormat,
        selectedRange: NSRange,
        textLength: Int,
        beforeState: Set<TextFormat>,
        afterState: Set<TextFormat>,
        success: Bool,
        errorMessage: String? = nil
    ) {
        let record = ConsistencyApplicationRecord(
            method: method,
            format: format,
            timestamp: Date(),
            selectedRange: selectedRange,
            textLength: textLength,
            beforeState: beforeState,
            afterState: afterState,
            success: success,
            errorMessage: errorMessage
        )
        
        // 添加到历史记录
        applicationHistory.append(record)
        
        // 保持历史记录数量限制
        if applicationHistory.count > maxHistoryCount {
            applicationHistory.removeFirst(applicationHistory.count - maxHistoryCount)
        }
        
        // 详细日志
        if isVerboseLoggingEnabled {
            logFormatApplicationRecord(record)
        }
        
        // 检查一致性（如果有对比数据）
        checkConsistencyForFormat(format)
    }
    
    /// 检查特定格式的应用一致性
    /// - Parameter format: 要检查的格式
    /// - Returns: 一致性检查结果
    func checkConsistencyForFormat(_ format: TextFormat) -> ConsistencyCheckResult? {
        // 获取最近的菜单和快捷键应用记录
        let recentRecords = getRecentRecords(for: format, within: TimeInterval(60)) // 60秒内
        
        let menuRecord = recentRecords.first { $0.method == .menu }
        let keyboardRecord = recentRecords.first { $0.method == .keyboard }
        
        guard let menu = menuRecord, let keyboard = keyboardRecord else {
            // 没有足够的对比数据
            return nil
        }
        
        // 比较应用效果
        let isConsistent = compareApplicationEffects(menu, keyboard)
        var inconsistencyReason: String?
        var recommendations: [String] = []
        
        if !isConsistent {
            inconsistencyReason = analyzeInconsistency(menu, keyboard)
            recommendations = generateRecommendations(menu, keyboard)
        }
        
        let result = ConsistencyCheckResult(
            format: format,
            menuRecord: menu,
            keyboardRecord: keyboard,
            isConsistent: isConsistent,
            inconsistencyReason: inconsistencyReason,
            recommendations: recommendations
        )
        
        // 更新最近的检查结果
        updateConsistencyResults(with: result)
        
        // 如果发现不一致，记录警告
        if !isConsistent {
            print("⚠️ [FormatConsistencyChecker] 发现格式应用不一致: \(format.displayName)")
            print("   - 菜单应用: \(menu.isFormatToggled ? "成功" : "失败")")
            print("   - 快捷键应用: \(keyboard.isFormatToggled ? "成功" : "失败")")
            if let reason = inconsistencyReason {
                print("   - 不一致原因: \(reason)")
            }
        }
        
        return result
    }
    
    /// 检查所有支持快捷键的格式的一致性
    /// - Returns: 所有检查结果
    func checkAllFormatsConsistency() -> [ConsistencyCheckResult] {
        let shortcutFormats: [TextFormat] = [.bold, .italic, .underline]
        var results: [ConsistencyCheckResult] = []
        
        for format in shortcutFormats {
            if let result = checkConsistencyForFormat(format) {
                results.append(result)
            }
        }
        
        return results
    }
    
    /// 获取格式应用统计信息
    /// - Returns: 统计信息字典
    func getApplicationStatistics() -> [String: Any] {
        let totalApplications = applicationHistory.count
        let successfulApplications = applicationHistory.filter { $0.isSuccessful }.count
        let failedApplications = totalApplications - successfulApplications
        
        var methodCounts: [String: Int] = [:]
        var formatCounts: [String: Int] = [:]
        
        for record in applicationHistory {
            methodCounts[record.method.rawValue, default: 0] += 1
            formatCounts[record.format.displayName, default: 0] += 1
        }
        
        return [
            "totalApplications": totalApplications,
            "successfulApplications": successfulApplications,
            "failedApplications": failedApplications,
            "successRate": totalApplications > 0 ? Double(successfulApplications) / Double(totalApplications) : 0.0,
            "methodCounts": methodCounts,
            "formatCounts": formatCounts,
            "lastCheckTime": Date()
        ]
    }
    
    /// 清除历史记录
    func clearHistory() {
        applicationHistory.removeAll()
        lastConsistencyResults.removeAll()
        print("[FormatConsistencyChecker] 历史记录已清除")
    }
    
    /// 启用或禁用详细日志
    /// - Parameter enabled: 是否启用
    func setVerboseLogging(_ enabled: Bool) {
        isVerboseLoggingEnabled = enabled
        print("[FormatConsistencyChecker] 详细日志已\(enabled ? "启用" : "禁用")")
    }
    
    // MARK: - Private Methods
    
    /// 设置通知观察者
    private func setupNotificationObservers() {
        // 这里可以监听格式应用相关的通知
        // 目前主要通过显式调用 recordFormatApplication 来记录
    }
    
    /// 获取指定格式的最近记录
    /// - Parameters:
    ///   - format: 格式类型
    ///   - timeInterval: 时间范围（秒）
    /// - Returns: 最近的记录列表
    private func getRecentRecords(for format: TextFormat, within timeInterval: TimeInterval) -> [ConsistencyApplicationRecord] {
        let cutoffTime = Date().addingTimeInterval(-timeInterval)
        
        return applicationHistory
            .filter { $0.format == format && $0.timestamp >= cutoffTime }
            .sorted { $0.timestamp > $1.timestamp } // 最新的在前
    }
    
    /// 比较两个应用记录的效果
    /// - Parameters:
    ///   - record1: 第一个记录
    ///   - record2: 第二个记录
    /// - Returns: 是否一致
    private func compareApplicationEffects(_ record1: ConsistencyApplicationRecord, _ record2: ConsistencyApplicationRecord) -> Bool {
        // 检查基本成功状态
        guard record1.isSuccessful && record2.isSuccessful else {
            return false
        }
        
        // 检查格式切换效果
        let format1Toggled = record1.isFormatToggled
        let format2Toggled = record2.isFormatToggled
        
        // 如果初始状态相同，切换效果应该相同
        if record1.beforeState.contains(record1.format) == record2.beforeState.contains(record2.format) {
            return format1Toggled == format2Toggled
        }
        
        // 如果初始状态不同，需要更复杂的比较逻辑
        // 这里简化处理：只要都成功切换就认为一致
        return format1Toggled && format2Toggled
    }
    
    /// 分析不一致的原因
    /// - Parameters:
    ///   - menuRecord: 菜单应用记录
    ///   - keyboardRecord: 快捷键应用记录
    /// - Returns: 不一致原因描述
    private func analyzeInconsistency(_ menuRecord: ConsistencyApplicationRecord, _ keyboardRecord: ConsistencyApplicationRecord) -> String {
        if !menuRecord.isSuccessful && !keyboardRecord.isSuccessful {
            return "菜单和快捷键应用都失败"
        } else if !menuRecord.isSuccessful {
            return "菜单应用失败，快捷键应用成功"
        } else if !keyboardRecord.isSuccessful {
            return "快捷键应用失败，菜单应用成功"
        } else if !menuRecord.isFormatToggled && keyboardRecord.isFormatToggled {
            return "菜单应用未能正确切换格式状态"
        } else if menuRecord.isFormatToggled && !keyboardRecord.isFormatToggled {
            return "快捷键应用未能正确切换格式状态"
        } else {
            return "格式状态变化不一致"
        }
    }
    
    /// 生成修复建议
    /// - Parameters:
    ///   - menuRecord: 菜单应用记录
    ///   - keyboardRecord: 快捷键应用记录
    /// - Returns: 建议列表
    private func generateRecommendations(_ menuRecord: ConsistencyApplicationRecord, _ keyboardRecord: ConsistencyApplicationRecord) -> [String] {
        var recommendations: [String] = []
        
        if !menuRecord.isSuccessful {
            recommendations.append("检查格式菜单的应用逻辑")
            if let error = menuRecord.errorMessage {
                recommendations.append("修复菜单应用错误: \(error)")
            }
        }
        
        if !keyboardRecord.isSuccessful {
            recommendations.append("检查快捷键的应用逻辑")
            if let error = keyboardRecord.errorMessage {
                recommendations.append("修复快捷键应用错误: \(error)")
            }
        }
        
        if menuRecord.isSuccessful && keyboardRecord.isSuccessful {
            if !menuRecord.isFormatToggled || !keyboardRecord.isFormatToggled {
                recommendations.append("检查格式状态同步机制")
                recommendations.append("确保格式应用后状态正确更新")
            }
        }
        
        recommendations.append("使用相同的格式应用方法确保一致性")
        
        return recommendations
    }
    
    /// 更新一致性检查结果
    /// - Parameter result: 新的检查结果
    private func updateConsistencyResults(with result: ConsistencyCheckResult) {
        // 移除同一格式的旧结果
        lastConsistencyResults.removeAll { $0.format == result.format }
        
        // 添加新结果
        lastConsistencyResults.append(result)
        
        // 保持结果数量限制
        if lastConsistencyResults.count > 10 {
            lastConsistencyResults.removeFirst(lastConsistencyResults.count - 10)
        }
    }
    
    /// 记录格式应用记录的详细日志
    /// - Parameter record: 应用记录
    private func logFormatApplicationRecord(_ record: ConsistencyApplicationRecord) {
        print("📝 [FormatConsistencyChecker] 格式应用记录:")
        print("   - 方式: \(record.method.displayName)")
        print("   - 格式: \(record.format.displayName)")
        print("   - 时间: \(record.timestamp)")
        print("   - 选择范围: \(record.selectedRange)")
        print("   - 文本长度: \(record.textLength)")
        print("   - 应用前状态: \(record.beforeState.map { $0.displayName })")
        print("   - 应用后状态: \(record.afterState.map { $0.displayName })")
        print("   - 成功: \(record.success)")
        print("   - 格式切换: \(record.isFormatToggled)")
        if let error = record.errorMessage {
            print("   - 错误: \(error)")
        }
    }
}

// MARK: - Extensions

extension FormatApplicationConsistencyChecker {
    
    /// 打印应用统计信息
    func printStatistics() {
        let stats = getApplicationStatistics()
        
        print("📊 [FormatConsistencyChecker] 格式应用统计:")
        print("   - 总应用次数: \(stats["totalApplications"] ?? 0)")
        print("   - 成功次数: \(stats["successfulApplications"] ?? 0)")
        print("   - 失败次数: \(stats["failedApplications"] ?? 0)")
        print("   - 成功率: \(String(format: "%.1f%%", (stats["successRate"] as? Double ?? 0) * 100))")
        
        if let methodCounts = stats["methodCounts"] as? [String: Int] {
            print("   - 应用方式统计:")
            for (method, count) in methodCounts {
                print("     - \(method): \(count)")
            }
        }
        
        if let formatCounts = stats["formatCounts"] as? [String: Int] {
            print("   - 格式统计:")
            for (format, count) in formatCounts {
                print("     - \(format): \(count)")
            }
        }
    }
    
    /// 打印一致性检查结果
    func printConsistencyResults() {
        guard !lastConsistencyResults.isEmpty else {
            print("📋 [FormatConsistencyChecker] 暂无一致性检查结果")
            return
        }
        
        print("📋 [FormatConsistencyChecker] 一致性检查结果:")
        
        for result in lastConsistencyResults {
            print("   - 格式: \(result.format.displayName)")
            print("     - 一致性: \(result.isConsistent ? "✅ 一致" : "❌ 不一致")")
            
            if let reason = result.inconsistencyReason {
                print("     - 不一致原因: \(reason)")
            }
            
            if !result.recommendations.isEmpty {
                print("     - 建议:")
                for recommendation in result.recommendations {
                    print("       - \(recommendation)")
                }
            }
        }
    }
}