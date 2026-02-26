//
//  FormatStateSynchronizer.swift
//  MiNoteMac
//
//  格式状态同步器 - 管理格式菜单按钮状态与编辑器实际状态的同步
//

import AppKit
import Foundation

/// 格式状态同步器
///
/// 使用防抖机制避免频繁更新格式菜单按钮状态。
@MainActor
class FormatStateSynchronizer {

    // MARK: - Properties

    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval
    private var updateCallback: (() -> Void)?

    // MARK: - Initialization

    init(debounceInterval: TimeInterval = 0.1) {
        self.debounceInterval = debounceInterval
    }

    // MARK: - Public Methods

    func setUpdateCallback(_ callback: @escaping () -> Void) {
        updateCallback = callback
    }

    /// 调度状态更新（使用防抖）
    func scheduleStateUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.performStateUpdate()
        }
    }

    /// 立即执行状态更新（不使用防抖）
    func performImmediateUpdate() {
        debounceTimer?.invalidate()
        performStateUpdate()
    }

    func cancelPendingUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    // MARK: - Private Methods

    private func performStateUpdate() {
        guard let callback = updateCallback else { return }
        PerformanceService.shared.measure(.editor, "格式状态同步", thresholdMs: 100) {
            callback()
        }
    }
}
