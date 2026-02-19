//
//  AutoSaveManager.swift
//  MiNoteMac
//
//  自动保存管理器 - 负责自动保存的调度、防抖和并发控制
//  需求: 59.6
//

import Foundation

/// 自动保存管理器
///
/// 负责自动保存的调度、防抖和并发控制
///
/// **功能**：
/// 1. 防抖机制：避免频繁保存
/// 2. 保存调度：延迟执行保存操作
/// 3. 并发控制：管理保存队列
/// 4. 取消保存：可以取消待处理的保存
///
/// **使用示例**：
/// ```swift
/// let manager = AutoSaveManager { [weak self] in
///     await self?.performSave()
/// }
///
/// // 调度保存（2秒后执行）
/// manager.scheduleAutoSave()
///
/// // 取消保存
/// manager.cancelAutoSave()
///
/// // 立即保存
/// await manager.saveImmediately()
/// ```
///
/// _Requirements: FR-6_
@MainActor
public class AutoSaveManager {
    // MARK: - 配置

    /// 防抖延迟时间（秒）
    ///
    /// _Requirements: FR-6.1_
    private let debounceDelay: TimeInterval

    // MARK: - 状态

    /// 防抖定时器
    private var debounceTimer: Timer?

    /// 正在保存的版本号
    private var savingVersion: Int?

    /// 保存回调
    private var saveCallback: (() async -> Void)?

    // MARK: - 初始化

    /// 初始化自动保存管理器
    ///
    /// - Parameters:
    ///   - debounceDelay: 防抖延迟时间（默认 2 秒）
    ///   - saveCallback: 保存回调函数
    public init(
        debounceDelay: TimeInterval = 2.0,
        saveCallback: @escaping () async -> Void
    ) {
        self.debounceDelay = debounceDelay
        self.saveCallback = saveCallback

    }

    // MARK: - 调度保存

    /// 调度自动保存
    ///
    /// 使用防抖机制，避免频繁保存
    /// 如果在延迟时间内再次调用，会取消之前的定时器并重新计时
    ///
    /// _Requirements: FR-6.1, FR-6.2_
    public func scheduleAutoSave() {
        // 取消之前的定时器
        debounceTimer?.invalidate()

        // 创建新的定时器
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.triggerSave()
            }
        }

    }

    /// 取消自动保存
    ///
    /// 取消待处理的保存任务
    ///
    /// _Requirements: FR-6.3_
    public func cancelAutoSave() {
        debounceTimer?.invalidate()
        debounceTimer = nil

    }

    /// 立即保存
    ///
    /// 取消防抖延迟，立即执行保存
    public func saveImmediately() async {
        cancelAutoSave()
        await triggerSave()
    }

    // MARK: - 保存执行

    /// 触发保存
    ///
    /// 执行保存回调函数
    private func triggerSave() async {
        guard let callback = saveCallback else {
            return
        }

        await callback()
    }

    /// 标记保存开始
    ///
    /// 记录正在保存的版本号，用于检测并发编辑
    ///
    /// - Parameter version: 正在保存的版本号
    ///
    /// _Requirements: FR-5.1_
    public func markSaveStarted(version: Int) {
        savingVersion = version
    }

    /// 标记保存完成
    ///
    /// 清除正在保存的版本号
    public func markSaveCompleted() {
        let version = savingVersion
        savingVersion = nil
    }

    /// 检查是否正在保存
    public var isSaving: Bool {
        savingVersion != nil
    }

    /// 获取正在保存的版本号
    public var currentSavingVersion: Int? {
        savingVersion
    }

    // MARK: - 调试信息

    /// 获取调试信息
    public func getDebugInfo() -> String {
        """
        AutoSaveManager 状态:
        - debounceDelay: \(debounceDelay)秒
        - isSaving: \(isSaving)
        - savingVersion: \(savingVersion?.description ?? "nil")
        - hasPendingSave: \(debounceTimer != nil)
        """
    }

    /// 打印调试信息
    public func printDebugInfo() {
    }

    // MARK: - 清理

    deinit {
        // 注意：由于 Swift 6 的 Sendable 限制，我们不能在 deinit 中直接访问 Timer
        // Timer 会在 AutoSaveManager 释放时自动失效
    }
}
