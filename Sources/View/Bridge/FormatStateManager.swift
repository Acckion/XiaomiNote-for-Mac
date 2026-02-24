//
//  FormatStateManager.swift
//  MiNoteMac
//
//  格式状态管理器 - 负责同步工具栏和菜单栏的格式状态
//  管理当前活动的格式提供者，并在格式状态变化时发送通知
//
//

import Combine
import Foundation

// MARK: - 性能监控记录

/// 格式状态更新性能记录
public struct FormatStatePerformanceRecord: Sendable {
    public let timestamp: Date
    public let durationMs: Double
    public let updateType: UpdateType
    public let stateChanged: Bool

    public enum UpdateType: String, Sendable {
        case debounced
        case immediate
        case forced
    }
}

// MARK: - 格式状态管理器

/// 格式状态管理器
/// 负责同步工具栏和菜单栏的格式状态
@MainActor
public final class FormatStateManager: ObservableObject {

    // MARK: - Singleton

    /// 共享实例
    public static let shared = FormatStateManager()

    // MARK: - Published Properties

    /// 当前格式状态
    @Published public private(set) var currentState = FormatState()

    /// 当前活动的格式提供者
    @Published public private(set) var activeProvider: (any FormatMenuProvider)?

    /// 是否有活动的编辑器
    @Published public private(set) var hasActiveEditor = false

    // MARK: - Private Properties

    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 状态变化主题
    private let stateSubject = PassthroughSubject<FormatState, Never>()

    /// 防抖定时器
    private var debounceTimer: Timer?

    /// 防抖间隔（毫秒）
    private let debounceInterval: TimeInterval = 0.05 // 50ms

    // MARK: - 性能监控属性

    /// 性能监控是否启用
    private var performanceMonitoringEnabled = true

    /// 性能记录
    private var performanceRecords: [FormatStatePerformanceRecord] = []

    /// 最大记录数量
    private let maxRecordCount = 200

    /// 更新计数
    private var updateCount = 0

    /// 总更新时间（毫秒）
    private var totalUpdateTime: Double = 0

    /// 最大更新时间（毫秒）
    private var maxUpdateTime: Double = 0

    /// 最小更新时间（毫秒）
    private var minUpdateTime = Double.infinity

    /// 跳过的更新次数（因为状态未变化）
    private var skippedUpdateCount = 0

    /// 上次状态更新时间
    private var lastUpdateTime: Date?

    // MARK: - Public Publishers

    /// 格式状态变化发布者
    public var formatStatePublisher: AnyPublisher<FormatState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
    }

    // MARK: - Public Methods - 提供者管理

    /// 设置活动的格式提供者
    /// - Parameter provider: 格式提供者（传入 nil 表示没有活动的编辑器）
    public func setActiveProvider(_ provider: (any FormatMenuProvider)?) {
        // 取消之前的订阅
        cancellables.removeAll()

        activeProvider = provider
        hasActiveEditor = provider != nil

        // 订阅新提供者的状态变化
        if let provider {
            provider.formatStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.updateState(state)
                }
                .store(in: &cancellables)

            // 立即获取当前状态
            let state = provider.getCurrentFormatState()
            updateState(state)
        } else {
            // 没有活动的提供者，重置为默认状态
            updateState(FormatState.default)
        }
    }

    /// 清除活动的格式提供者
    public func clearActiveProvider() {
        setActiveProvider(nil)
    }

    // MARK: - Public Methods - 格式操作

    /// 应用格式
    /// - Parameter format: 要应用的格式
    public func applyFormat(_ format: TextFormat) {
        guard let provider = activeProvider else {
            return
        }

        provider.applyFormat(format)
    }

    /// 切换格式
    /// - Parameter format: 要切换的格式
    public func toggleFormat(_ format: TextFormat) {
        guard let provider = activeProvider else {
            return
        }

        provider.toggleFormat(format)
    }

    /// 清除段落格式（恢复为正文）
    public func clearParagraphFormat() {
        guard let provider = activeProvider else {
            return
        }

        provider.clearParagraphFormat()
    }

    /// 清除对齐格式（恢复为左对齐）
    public func clearAlignmentFormat() {
        guard let provider = activeProvider else {
            return
        }

        provider.clearAlignmentFormat()
    }

    // MARK: - Public Methods - 状态查询

    /// 检查指定格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    public func isFormatActive(_ format: TextFormat) -> Bool {
        currentState.isFormatActive(format)
    }

    /// 获取当前段落格式
    /// - Returns: 当前段落格式
    public func getCurrentParagraphFormat() -> ParagraphFormat {
        currentState.paragraphFormat
    }

    /// 获取当前对齐格式
    /// - Returns: 当前对齐格式
    public func getCurrentAlignment() -> AlignmentFormat {
        currentState.alignment
    }

    /// 强制刷新格式状态
    /// 用于在某些情况下需要立即更新状态
    public func forceRefresh() {
        guard let provider = activeProvider else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        let state = provider.getCurrentFormatState()
        updateStateImmediately(state, updateType: .forced)
    }

    // MARK: - Public Methods - 性能监控

    /// 启用或禁用性能监控
    /// - Parameter enabled: 是否启用
    public func setPerformanceMonitoring(enabled: Bool) {
        performanceMonitoringEnabled = enabled
    }

    /// 获取性能统计信息
    /// - Returns: 性能统计信息字典
    public func getPerformanceStats() -> [String: Any] {
        guard updateCount > 0 else {
            return [
                "updateCount": 0,
                "skippedCount": skippedUpdateCount,
                "averageTime": 0.0,
                "maxTime": 0.0,
                "minTime": 0.0,
                "totalTime": 0.0,
            ]
        }

        return [
            "updateCount": updateCount,
            "skippedCount": skippedUpdateCount,
            "averageTime": totalUpdateTime / Double(updateCount),
            "maxTime": maxUpdateTime,
            "minTime": minUpdateTime == Double.infinity ? 0.0 : minUpdateTime,
            "totalTime": totalUpdateTime,
            "skipRatio": Double(skippedUpdateCount) / Double(updateCount + skippedUpdateCount),
        ]
    }

    /// 重置性能统计信息
    public func resetPerformanceStats() {
        updateCount = 0
        skippedUpdateCount = 0
        totalUpdateTime = 0
        maxUpdateTime = 0
        minUpdateTime = Double.infinity
        performanceRecords.removeAll()
    }

    /// 获取最近的性能记录
    /// - Parameter count: 记录数量
    /// - Returns: 性能记录数组
    public func getRecentPerformanceRecords(count: Int = 50) -> [FormatStatePerformanceRecord] {
        let startIndex = max(0, performanceRecords.count - count)
        return Array(performanceRecords[startIndex...])
    }

    // MARK: - Private Methods - 状态更新

    /// 更新状态（带防抖）
    private func updateState(_ state: FormatState) {
        // 取消之前的定时器
        debounceTimer?.invalidate()

        // 设置新的定时器
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateStateImmediately(state, updateType: .debounced)
            }
        }
    }

    /// 立即更新状态（不使用防抖）
    /// - Parameters:
    ///   - state: 新的格式状态
    ///   - updateType: 更新类型（用于性能监控）
    private func updateStateImmediately(_ state: FormatState, updateType: FormatStatePerformanceRecord.UpdateType = .immediate) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 增量更新：检查状态是否真的变化了
        guard state != currentState else {
            skippedUpdateCount += 1
            return
        }

        // 更新当前状态
        currentState = state

        // 发送状态变化
        stateSubject.send(state)

        // 发送通知以更新菜单栏
        postFormatStateNotification(state)

        // 记录性能数据
        if performanceMonitoringEnabled {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            recordPerformance(duration: duration, updateType: updateType, stateChanged: true)
        }

        lastUpdateTime = Date()
    }

    /// 记录性能数据
    private func recordPerformance(duration: Double, updateType: FormatStatePerformanceRecord.UpdateType, stateChanged: Bool) {
        // 更新统计信息
        updateCount += 1
        totalUpdateTime += duration
        maxUpdateTime = max(maxUpdateTime, duration)
        minUpdateTime = min(minUpdateTime, duration)

        // 创建性能记录
        let record = FormatStatePerformanceRecord(
            timestamp: Date(),
            durationMs: duration,
            updateType: updateType,
            stateChanged: stateChanged
        )

        performanceRecords.append(record)

        // 限制记录数量
        if performanceRecords.count > maxRecordCount {
            performanceRecords.removeFirst(performanceRecords.count - maxRecordCount)
        }
    }

    /// 发送格式状态变化通知
    private func postFormatStateNotification(_ state: FormatState) {
        NotificationCenter.default.post(
            name: .formatStateDidChange,
            object: self,
            userInfo: ["state": state]
        )
    }

    // MARK: - Private Methods - 通知观察

    /// 设置通知观察者
    private func setupNotificationObservers() {
        // 监听编辑器焦点变化
        NotificationCenter.default.addObserver(
            forName: .editorFocusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 在主线程上提取 userInfo，避免跨隔离域传递 notification
            let isEditorFocused = (notification.userInfo?["isEditorFocused"] as? Bool) ?? false
            Task { @MainActor in
                self?.handleEditorFocusChange(isEditorFocused: isEditorFocused)
            }
        }

        // 监听格式状态更新请求
        NotificationCenter.default.addObserver(
            forName: .requestFormatStateUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.forceRefresh()
            }
        }
    }

    /// 处理编辑器焦点变化
    private func handleEditorFocusChange(isEditorFocused: Bool) {

        if isEditorFocused {
            // 编辑器获得焦点，刷新状态
            forceRefresh()
        } else {
            // 编辑器失去焦点，可以选择保持当前状态或重置
            // 这里选择保持当前状态，因为用户可能只是临时切换焦点
        }
    }

    // MARK: - Deinit

    nonisolated deinit {
        // 注意：在 deinit 中不能访问 MainActor 隔离的属性
        // debounceTimer 会在对象销毁时自动失效
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - 调试扩展

public extension FormatStateManager {

    /// 打印当前状态（调试用）
    func printCurrentState() {}
}
