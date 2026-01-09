//
//  NativeEditorMetrics.swift
//  MiNoteMac
//
//  原生编辑器性能指标收集器 - 收集和分析编辑器性能数据
//  需求: 13.2, 13.3
//

import Foundation

// MARK: - 性能指标类型

/// 性能指标类型
enum MetricType: String, CaseIterable {
    case initialization = "初始化"
    case rendering = "渲染"
    case formatConversion = "格式转换"
    case contentLoad = "内容加载"
    case contentSave = "内容保存"
    case userInput = "用户输入"
    case scrolling = "滚动"
    case attachmentCreation = "附件创建"
    case cacheOperation = "缓存操作"
    case other = "其他"
}

// MARK: - 性能指标记录

/// 性能指标记录
struct MetricRecord {
    let type: MetricType
    let operation: String
    let duration: TimeInterval
    let timestamp: Date
    let additionalData: [String: Any]?
    
    var durationMs: Double {
        return duration * 1000
    }
}

// MARK: - 性能统计

/// 性能统计
struct MetricStatistics {
    let type: MetricType
    let count: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let minDuration: TimeInterval
    let maxDuration: TimeInterval
    let p50Duration: TimeInterval  // 中位数
    let p95Duration: TimeInterval  // 95 百分位
    let p99Duration: TimeInterval  // 99 百分位
    
    var averageMs: Double { averageDuration * 1000 }
    var minMs: Double { minDuration * 1000 }
    var maxMs: Double { maxDuration * 1000 }
    var p50Ms: Double { p50Duration * 1000 }
    var p95Ms: Double { p95Duration * 1000 }
    var p99Ms: Double { p99Duration * 1000 }
    
    var summary: String {
        return """
        \(type.rawValue):
          - 次数: \(count)
          - 平均: \(String(format: "%.2f", averageMs))ms
          - 最小: \(String(format: "%.2f", minMs))ms
          - 最大: \(String(format: "%.2f", maxMs))ms
          - P50: \(String(format: "%.2f", p50Ms))ms
          - P95: \(String(format: "%.2f", p95Ms))ms
          - P99: \(String(format: "%.2f", p99Ms))ms
        """
    }
}

// MARK: - 原生编辑器性能指标收集器

/// 原生编辑器性能指标收集器
/// 收集、分析和报告编辑器性能数据
@MainActor
final class NativeEditorMetrics {
    
    // MARK: - Singleton
    
    static let shared = NativeEditorMetrics()
    
    // MARK: - Properties
    
    /// 性能记录
    private var records: [MetricRecord] = []
    
    /// 最大记录数
    private let maxRecords = 10000
    
    /// 是否启用收集
    var isEnabled: Bool = true
    
    /// 性能阈值（毫秒）
    var thresholds: [MetricType: TimeInterval] = [
        .initialization: 0.1,      // 100ms
        .rendering: 0.016,         // 16ms (60fps)
        .formatConversion: 0.05,   // 50ms
        .contentLoad: 0.2,         // 200ms
        .contentSave: 0.1,         // 100ms
        .userInput: 0.016,         // 16ms
        .scrolling: 0.016,         // 16ms
        .attachmentCreation: 0.01, // 10ms
        .cacheOperation: 0.001     // 1ms
    ]
    
    /// 超过阈值的记录回调
    var onThresholdExceeded: ((MetricRecord, TimeInterval) -> Void)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Recording
    
    /// 记录操作性能
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - duration: 持续时间
    ///   - type: 指标类型
    ///   - additionalData: 附加数据
    func recordOperation(
        _ operation: String,
        duration: TimeInterval,
        type: MetricType = .other,
        additionalData: [String: Any]? = nil
    ) {
        guard isEnabled else { return }
        
        let record = MetricRecord(
            type: type,
            operation: operation,
            duration: duration,
            timestamp: Date(),
            additionalData: additionalData
        )
        
        records.append(record)
        
        // 限制记录数量
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        
        // 检查阈值
        if let threshold = thresholds[type], duration > threshold {
            onThresholdExceeded?(record, threshold)
        }
    }
    
    /// 测量操作性能
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - type: 指标类型
    ///   - block: 要测量的代码块
    /// - Returns: 代码块的返回值
    func measure<T>(
        _ operation: String,
        type: MetricType = .other,
        block: () throws -> T
    ) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        recordOperation(operation, duration: duration, type: type)
        
        return result
    }
    
    /// 异步测量操作性能
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - type: 指标类型
    ///   - block: 要测量的异步代码块
    /// - Returns: 代码块的返回值
    func measureAsync<T>(
        _ operation: String,
        type: MetricType = .other,
        block: () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        recordOperation(operation, duration: duration, type: type)
        
        return result
    }
    
    // MARK: - Statistics
    
    /// 获取指定类型的统计信息
    /// - Parameter type: 指标类型
    /// - Returns: 统计信息
    func getStatistics(for type: MetricType) -> MetricStatistics? {
        let typeRecords = records.filter { $0.type == type }
        guard !typeRecords.isEmpty else { return nil }
        
        let durations = typeRecords.map { $0.duration }.sorted()
        let count = durations.count
        let total = durations.reduce(0, +)
        
        return MetricStatistics(
            type: type,
            count: count,
            totalDuration: total,
            averageDuration: total / Double(count),
            minDuration: durations.first ?? 0,
            maxDuration: durations.last ?? 0,
            p50Duration: percentile(durations, 0.50),
            p95Duration: percentile(durations, 0.95),
            p99Duration: percentile(durations, 0.99)
        )
    }
    
    /// 获取所有类型的统计信息
    /// - Returns: 统计信息字典
    func getAllStatistics() -> [MetricType: MetricStatistics] {
        var result: [MetricType: MetricStatistics] = [:]
        
        for type in MetricType.allCases {
            if let stats = getStatistics(for: type) {
                result[type] = stats
            }
        }
        
        return result
    }
    
    /// 计算百分位数
    private func percentile(_ sortedValues: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !sortedValues.isEmpty else { return 0 }
        
        let index = Int(Double(sortedValues.count - 1) * p)
        return sortedValues[index]
    }
    
    // MARK: - Analysis
    
    /// 获取超过阈值的记录
    /// - Parameter type: 指标类型（可选，nil 表示所有类型）
    /// - Returns: 超过阈值的记录
    func getThresholdExceededRecords(for type: MetricType? = nil) -> [MetricRecord] {
        return records.filter { record in
            if let type = type, record.type != type {
                return false
            }
            
            guard let threshold = thresholds[record.type] else {
                return false
            }
            
            return record.duration > threshold
        }
    }
    
    /// 获取最慢的操作
    /// - Parameters:
    ///   - count: 返回数量
    ///   - type: 指标类型（可选）
    /// - Returns: 最慢的操作记录
    func getSlowestOperations(count: Int = 10, type: MetricType? = nil) -> [MetricRecord] {
        var filtered = records
        
        if let type = type {
            filtered = filtered.filter { $0.type == type }
        }
        
        return Array(filtered.sorted { $0.duration > $1.duration }.prefix(count))
    }
    
    /// 获取最近的操作
    /// - Parameters:
    ///   - count: 返回数量
    ///   - type: 指标类型（可选）
    /// - Returns: 最近的操作记录
    func getRecentOperations(count: Int = 50, type: MetricType? = nil) -> [MetricRecord] {
        var filtered = records
        
        if let type = type {
            filtered = filtered.filter { $0.type == type }
        }
        
        return Array(filtered.suffix(count))
    }
    
    // MARK: - Reporting
    
    /// 获取性能摘要
    /// - Returns: 性能摘要字符串
    func getMetricsSummary() -> String {
        var summary = """
        ========================================
        原生编辑器性能指标摘要
        记录时间范围: \(getTimeRange())
        总记录数: \(records.count)
        ========================================
        
        """
        
        let allStats = getAllStatistics()
        
        for type in MetricType.allCases {
            if let stats = allStats[type] {
                summary += "\n" + stats.summary + "\n"
            }
        }
        
        // 添加阈值超出统计
        let exceededRecords = getThresholdExceededRecords()
        if !exceededRecords.isEmpty {
            summary += """
            
            ========================================
            阈值超出统计
            ========================================
            总次数: \(exceededRecords.count)
            
            """
            
            let groupedByType = Dictionary(grouping: exceededRecords) { $0.type }
            for (type, typeRecords) in groupedByType.sorted(by: { $0.value.count > $1.value.count }) {
                summary += "- \(type.rawValue): \(typeRecords.count) 次\n"
            }
        }
        
        return summary
    }
    
    /// 获取时间范围
    private func getTimeRange() -> String {
        guard let first = records.first, let last = records.last else {
            return "无数据"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return "\(formatter.string(from: first.timestamp)) - \(formatter.string(from: last.timestamp))"
    }
    
    /// 导出性能报告
    /// - Parameter url: 文件 URL
    /// - Throws: 写入错误
    func exportReport(to url: URL) throws {
        let report = getMetricsSummary()
        try report.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// 导出原始数据为 JSON
    /// - Parameter url: 文件 URL
    /// - Throws: 写入错误
    func exportRawData(to url: URL) throws {
        let data = records.map { record -> [String: Any] in
            var dict: [String: Any] = [
                "type": record.type.rawValue,
                "operation": record.operation,
                "duration_ms": record.durationMs,
                "timestamp": ISO8601DateFormatter().string(from: record.timestamp)
            ]
            if let additional = record.additionalData {
                dict["additionalData"] = additional
            }
            return dict
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        try jsonData.write(to: url)
    }
    
    // MARK: - Management
    
    /// 清除所有记录
    func clearRecords() {
        records.removeAll()
    }
    
    /// 清除指定类型的记录
    /// - Parameter type: 指标类型
    func clearRecords(for type: MetricType) {
        records.removeAll { $0.type == type }
    }
    
    /// 清除指定时间之前的记录
    /// - Parameter date: 截止日期
    func clearRecords(before date: Date) {
        records.removeAll { $0.timestamp < date }
    }
}

// MARK: - 性能测量辅助

/// 性能测量器
struct PerformanceMeasurer {
    let operation: String
    let type: MetricType
    let startTime: CFAbsoluteTime
    
    init(operation: String, type: MetricType = .other) {
        self.operation = operation
        self.type = type
        self.startTime = CFAbsoluteTimeGetCurrent()
    }
    
    /// 结束测量并记录
    @MainActor
    func finish(additionalData: [String: Any]? = nil) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        NativeEditorMetrics.shared.recordOperation(
            operation,
            duration: duration,
            type: type,
            additionalData: additionalData
        )
    }
}

// MARK: - 便捷扩展

extension NativeEditorMetrics {
    
    /// 记录初始化性能
    func recordInitialization(_ operation: String, duration: TimeInterval) {
        recordOperation(operation, duration: duration, type: .initialization)
    }
    
    /// 记录渲染性能
    func recordRendering(_ operation: String, duration: TimeInterval, cached: Bool = false) {
        recordOperation(operation, duration: duration, type: .rendering, additionalData: ["cached": cached])
    }
    
    /// 记录格式转换性能
    func recordFormatConversion(_ operation: String, duration: TimeInterval, success: Bool = true) {
        recordOperation(operation, duration: duration, type: .formatConversion, additionalData: ["success": success])
    }
    
    /// 记录内容加载性能
    func recordContentLoad(_ operation: String, duration: TimeInterval, contentSize: Int? = nil) {
        var data: [String: Any] = [:]
        if let size = contentSize {
            data["contentSize"] = size
        }
        recordOperation(operation, duration: duration, type: .contentLoad, additionalData: data.isEmpty ? nil : data)
    }
    
    /// 记录内容保存性能
    func recordContentSave(_ operation: String, duration: TimeInterval, contentSize: Int? = nil) {
        var data: [String: Any] = [:]
        if let size = contentSize {
            data["contentSize"] = size
        }
        recordOperation(operation, duration: duration, type: .contentSave, additionalData: data.isEmpty ? nil : data)
    }
}
