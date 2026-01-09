//
//  NativeEditorDebugger.swift
//  MiNoteMac
//
//  原生编辑器调试器 - 提供调试和监控功能
//  需求: 13.1, 13.2, 13.3, 13.4, 13.5
//

import Foundation
import AppKit
import Combine

// MARK: - 调试模式

/// 调试模式
enum DebugMode: String, CaseIterable {
    case off = "关闭"
    case basic = "基础"
    case verbose = "详细"
    case performance = "性能"
    case all = "全部"
    
    var description: String {
        switch self {
        case .off:
            return "关闭所有调试输出"
        case .basic:
            return "仅输出错误和警告"
        case .verbose:
            return "输出所有日志信息"
        case .performance:
            return "仅输出性能相关信息"
        case .all:
            return "输出所有调试信息"
        }
    }
}

// MARK: - 调试事件

/// 调试事件类型
enum DebugEventType: String {
    case formatConversion = "格式转换"
    case rendering = "渲染"
    case userInput = "用户输入"
    case stateChange = "状态变化"
    case error = "错误"
    case performance = "性能"
    case cache = "缓存"
}

/// 调试事件
struct DebugEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: DebugEventType
    let message: String
    let details: [String: Any]?
    let duration: TimeInterval?
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    var summary: String {
        var result = "[\(formattedTimestamp)] [\(type.rawValue)] \(message)"
        if let duration = duration {
            result += " (\(String(format: "%.2f", duration * 1000))ms)"
        }
        return result
    }
}

// MARK: - 原生编辑器调试器

/// 原生编辑器调试器
/// 提供调试、监控和诊断功能
@MainActor
final class NativeEditorDebugger: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NativeEditorDebugger()
    
    // MARK: - Published Properties
    
    /// 当前调试模式
    @Published var debugMode: DebugMode = .off {
        didSet {
            updateDebugSettings()
        }
    }
    
    /// 调试事件列表
    @Published var events: [DebugEvent] = []
    
    /// 是否显示调试面板
    @Published var isDebugPanelVisible: Bool = false
    
    /// 实时性能数据
    @Published var realtimeMetrics: RealtimeMetrics = RealtimeMetrics()
    
    // MARK: - Properties
    
    /// 日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 性能指标
    private let metrics = NativeEditorMetrics.shared
    
    /// 错误处理器
    private let errorHandler = NativeEditorErrorHandler.shared
    
    /// 最大事件数
    private let maxEvents = 500
    
    /// 性能更新定时器
    private var performanceTimer: Timer?
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // 监听错误
        errorHandler.onError = { [weak self] error, result in
            self?.recordEvent(
                type: .error,
                message: error.localizedDescription,
                details: [
                    "errorCode": error.errorCode,
                    "isRecoverable": error.isRecoverable,
                    "recoveryAction": result.recoveryAction.description
                ]
            )
        }
        
        // 监听性能阈值超出
        metrics.onThresholdExceeded = { [weak self] record, threshold in
            self?.recordEvent(
                type: .performance,
                message: "性能阈值超出: \(record.operation)",
                details: [
                    "duration_ms": record.durationMs,
                    "threshold_ms": threshold * 1000
                ],
                duration: record.duration
            )
        }
    }
    
    private func updateDebugSettings() {
        switch debugMode {
        case .off:
            logger.minimumLogLevel = .error
            logger.enableConsoleOutput = false
            logger.enableFormatConversionLogging = false
            logger.enableRenderingLogging = false
            logger.enablePerformanceLogging = false
            stopPerformanceMonitoring()
            
        case .basic:
            logger.minimumLogLevel = .warning
            logger.enableConsoleOutput = true
            logger.enableFormatConversionLogging = false
            logger.enableRenderingLogging = false
            logger.enablePerformanceLogging = false
            stopPerformanceMonitoring()
            
        case .verbose:
            logger.minimumLogLevel = .debug
            logger.enableConsoleOutput = true
            logger.enableFormatConversionLogging = true
            logger.enableRenderingLogging = true
            logger.enablePerformanceLogging = true
            startPerformanceMonitoring()
            
        case .performance:
            logger.minimumLogLevel = .info
            logger.enableConsoleOutput = true
            logger.enableFormatConversionLogging = false
            logger.enableRenderingLogging = false
            logger.enablePerformanceLogging = true
            startPerformanceMonitoring()
            
        case .all:
            logger.minimumLogLevel = .debug
            logger.enableConsoleOutput = true
            logger.enableFormatConversionLogging = true
            logger.enableRenderingLogging = true
            logger.enablePerformanceLogging = true
            startPerformanceMonitoring()
        }
        
        recordEvent(type: .stateChange, message: "调试模式已更改为: \(debugMode.rawValue)")
    }
    
    // MARK: - Event Recording
    
    /// 记录调试事件
    func recordEvent(
        type: DebugEventType,
        message: String,
        details: [String: Any]? = nil,
        duration: TimeInterval? = nil
    ) {
        guard debugMode != .off else { return }
        
        let event = DebugEvent(
            timestamp: Date(),
            type: type,
            message: message,
            details: details,
            duration: duration
        )
        
        events.append(event)
        
        // 限制事件数量
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        
        // 控制台输出
        if logger.enableConsoleOutput {
            print("[DEBUG] \(event.summary)")
        }
    }
    
    /// 记录格式转换事件
    func recordFormatConversion(
        direction: String,
        inputSize: Int,
        outputSize: Int,
        duration: TimeInterval,
        success: Bool
    ) {
        recordEvent(
            type: .formatConversion,
            message: "\(direction) - \(success ? "成功" : "失败")",
            details: [
                "inputSize": inputSize,
                "outputSize": outputSize,
                "success": success
            ],
            duration: duration
        )
    }
    
    /// 记录渲染事件
    func recordRendering(
        element: String,
        cached: Bool,
        duration: TimeInterval
    ) {
        recordEvent(
            type: .rendering,
            message: "渲染 \(element) - \(cached ? "缓存命中" : "新渲染")",
            details: [
                "element": element,
                "cached": cached
            ],
            duration: duration
        )
    }
    
    /// 记录用户输入事件
    func recordUserInput(
        action: String,
        details: [String: Any]? = nil
    ) {
        recordEvent(
            type: .userInput,
            message: action,
            details: details
        )
    }
    
    /// 记录状态变化事件
    func recordStateChange(
        from: String,
        to: String,
        reason: String? = nil
    ) {
        var details: [String: Any] = [
            "from": from,
            "to": to
        ]
        if let reason = reason {
            details["reason"] = reason
        }
        
        recordEvent(
            type: .stateChange,
            message: "状态变化: \(from) -> \(to)",
            details: details
        )
    }
    
    // MARK: - Performance Monitoring
    
    /// 开始性能监控
    func startPerformanceMonitoring() {
        stopPerformanceMonitoring()
        
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRealtimeMetrics()
            }
        }
    }
    
    /// 停止性能监控
    func stopPerformanceMonitoring() {
        performanceTimer?.invalidate()
        performanceTimer = nil
    }
    
    /// 更新实时指标
    private func updateRealtimeMetrics() {
        let allStats = metrics.getAllStatistics()
        
        realtimeMetrics = RealtimeMetrics(
            renderingAvgMs: allStats[.rendering]?.averageMs ?? 0,
            conversionAvgMs: allStats[.formatConversion]?.averageMs ?? 0,
            cacheHitRate: CustomRenderer.shared.cacheHitRate,
            totalOperations: allStats.values.reduce(0) { $0 + $1.count },
            errorCount: errorHandler.getErrorHistory().count
        )
    }
    
    // MARK: - Debug Panel
    
    /// 显示调试面板
    func showDebugPanel() {
        isDebugPanelVisible = true
    }
    
    /// 隐藏调试面板
    func hideDebugPanel() {
        isDebugPanelVisible = false
    }
    
    /// 切换调试面板
    func toggleDebugPanel() {
        isDebugPanelVisible.toggle()
    }
    
    // MARK: - Event Filtering
    
    /// 获取指定类型的事件
    func getEvents(type: DebugEventType) -> [DebugEvent] {
        return events.filter { $0.type == type }
    }
    
    /// 获取最近的事件
    func getRecentEvents(count: Int = 50) -> [DebugEvent] {
        return Array(events.suffix(count))
    }
    
    /// 清除所有事件
    func clearEvents() {
        events.removeAll()
    }
    
    // MARK: - Report Generation
    
    /// 生成调试报告
    func generateDebugReport() -> String {
        var report = """
        ========================================
        原生编辑器调试报告
        生成时间: \(ISO8601DateFormatter().string(from: Date()))
        调试模式: \(debugMode.rawValue)
        ========================================
        
        """
        
        // 系统信息
        report += """
        
        ## 系统信息
        - macOS 版本: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - 应用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
        - 内存使用: \(getMemoryUsage())
        
        """
        
        // 性能摘要
        report += """
        
        ## 性能摘要
        \(metrics.getMetricsSummary())
        
        """
        
        // 缓存状态
        let cacheStats = CustomRenderer.shared.getCacheStats()
        report += """
        
        ## 缓存状态
        - 附件缓存数: \(cacheStats.attachments)
        - 图片缓存数: \(cacheStats.images)
        - 缓存命中率: \(String(format: "%.1f", cacheStats.hitRate * 100))%
        
        """
        
        // 错误摘要
        let errors = errorHandler.getErrorHistory()
        report += """
        
        ## 错误摘要
        - 总错误数: \(errors.count)
        
        """
        
        if !errors.isEmpty {
            let errorCounts = Dictionary(grouping: errors) { $0.error.errorCode }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            
            for (code, count) in errorCounts.prefix(5) {
                report += "- 错误代码 \(code): \(count) 次\n"
            }
        }
        
        // 最近事件
        report += """
        
        ## 最近调试事件
        
        """
        
        for event in events.suffix(30).reversed() {
            report += "\(event.summary)\n"
        }
        
        report += """
        
        ========================================
        报告结束
        ========================================
        """
        
        return report
    }
    
    /// 获取内存使用情况
    private func getMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024 / 1024
            return String(format: "%.1f MB", usedMB)
        }
        
        return "未知"
    }
    
    /// 导出调试报告
    func exportDebugReport(to url: URL) throws {
        let report = generateDebugReport()
        try report.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("调试报告已导出到: \(url.path)", category: "Debug")
    }
}

// MARK: - 实时指标

/// 实时性能指标
struct RealtimeMetrics {
    var renderingAvgMs: Double = 0
    var conversionAvgMs: Double = 0
    var cacheHitRate: Double = 0
    var totalOperations: Int = 0
    var errorCount: Int = 0
    
    var summary: String {
        return """
        渲染平均: \(String(format: "%.2f", renderingAvgMs))ms
        转换平均: \(String(format: "%.2f", conversionAvgMs))ms
        缓存命中: \(String(format: "%.1f", cacheHitRate * 100))%
        总操作数: \(totalOperations)
        错误数: \(errorCount)
        """
    }
}

// MARK: - 调试视图

import SwiftUI

/// 调试面板视图
struct DebugPanelView: View {
    @ObservedObject var debugger = NativeEditorDebugger.shared
    @State private var selectedEventType: DebugEventType?
    @State private var searchText = ""
    
    var filteredEvents: [DebugEvent] {
        var result = debugger.events
        
        if let type = selectedEventType {
            result = result.filter { $0.type == type }
        }
        
        if !searchText.isEmpty {
            result = result.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }
        
        return result.reversed()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("调试面板")
                    .font(.headline)
                
                Spacer()
                
                Picker("模式", selection: $debugger.debugMode) {
                    ForEach(DebugMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                Button(action: { debugger.clearEvents() }) {
                    Image(systemName: "trash")
                }
                .help("清除事件")
                
                Button(action: { debugger.hideDebugPanel() }) {
                    Image(systemName: "xmark")
                }
                .help("关闭")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 实时指标
            HStack(spacing: 16) {
                MetricBadge(title: "渲染", value: String(format: "%.1fms", debugger.realtimeMetrics.renderingAvgMs))
                MetricBadge(title: "转换", value: String(format: "%.1fms", debugger.realtimeMetrics.conversionAvgMs))
                MetricBadge(title: "缓存", value: String(format: "%.0f%%", debugger.realtimeMetrics.cacheHitRate * 100))
                MetricBadge(title: "错误", value: "\(debugger.realtimeMetrics.errorCount)")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 过滤器
            HStack {
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                
                Picker("类型", selection: $selectedEventType) {
                    Text("全部").tag(nil as DebugEventType?)
                    ForEach([DebugEventType.formatConversion, .rendering, .userInput, .stateChange, .error, .performance], id: \.self) { type in
                        Text(type.rawValue).tag(type as DebugEventType?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                Spacer()
                
                Text("\(filteredEvents.count) 条事件")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            Divider()
            
            // 事件列表
            List(filteredEvents) { event in
                EventRow(event: event)
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

/// 指标徽章
struct MetricBadge: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }
}

/// 事件行
struct EventRow: View {
    let event: DebugEvent
    
    var typeColor: Color {
        switch event.type {
        case .error:
            return .red
        case .performance:
            return .orange
        case .formatConversion:
            return .blue
        case .rendering:
            return .green
        case .userInput:
            return .purple
        case .stateChange:
            return .gray
        case .cache:
            return .cyan
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(typeColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(event.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let duration = event.duration {
                        Text(String(format: "%.2fms", duration * 1000))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Text(event.message)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
