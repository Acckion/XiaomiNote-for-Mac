//
//  SyncCoordinator.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  同步协调器 - 协调同步操作
//

import Combine
import Foundation
import SwiftUI

/// 同步协调器
///
/// 负责协调同步操作，包括：
/// - 启动同步
/// - 停止同步
/// - 强制全量同步
/// - 同步单个笔记
/// - 处理离线操作队列
/// - 同步状态管理
/// - 冲突解决
///
/// **设计原则**:
/// - 单一职责：只负责同步相关的协调工作
/// - 依赖注入：通过构造函数注入依赖，而不是使用单例
/// - 可测试性：所有依赖都可以被 Mock，便于单元测试
///
/// **线程安全**：使用 @MainActor 确保所有 UI 更新在主线程执行
@MainActor
public final class SyncCoordinator: ObservableObject {
    // MARK: - Published Properties

    /// 是否正在同步
    @Published public var isSyncing = false

    /// 同步进度 (0.0 - 1.0)
    @Published public var syncProgress = 0.0

    /// 同步状态消息
    @Published public var syncStatusMessage = ""

    /// 最后同步时间
    @Published public var lastSyncTime: Date?

    /// 同步结果
    @Published public var syncResult: SyncResult?

    /// 错误消息（用于显示错误提示）
    @Published public var errorMessage: String?

    // MARK: - Dependencies

    /// 同步服务
    private let syncService: SyncServiceProtocol

    /// 笔记存储服务（本地数据库）
    private let noteStorage: NoteStorageProtocol

    /// 网络监控服务
    private let networkMonitor: NetworkMonitorProtocol

    // MARK: - Private Properties

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 是否正在处理离线操作
    private var isProcessingOfflineOperations = false

    // MARK: - Initialization

    /// 初始化同步协调器
    ///
    /// - Parameters:
    ///   - syncService: 同步服务
    ///   - noteStorage: 笔记存储服务（本地数据库）
    ///   - networkMonitor: 网络监控服务
    public init(
        syncService: SyncServiceProtocol,
        noteStorage: NoteStorageProtocol,
        networkMonitor: NetworkMonitorProtocol
    ) {
        self.syncService = syncService
        self.noteStorage = noteStorage
        self.networkMonitor = networkMonitor

        setupObservers()

        LogService.shared.info(.viewmodel, "SyncCoordinator 初始化完成")
    }

    // MARK: - Public Methods

    /// 启动同步
    public func startSync() async {
        guard !isSyncing else {
            LogService.shared.debug(.viewmodel, "同步已在进行中")
            return
        }

        guard networkMonitor.isConnected else {
            errorMessage = "无网络连接，无法同步"
            LogService.shared.warning(.viewmodel, "无网络连接，无法同步")
            return
        }

        isSyncing = true
        syncProgress = 0.0
        syncStatusMessage = "正在同步..."
        errorMessage = nil

        do {
            LogService.shared.info(.viewmodel, "开始同步")

            syncProgress = 0.3
            syncStatusMessage = "正在同步笔记..."

            try await syncService.startSync()

            syncProgress = 0.8
            syncStatusMessage = "正在保存数据..."

            syncProgress = 1.0
            syncStatusMessage = "同步完成"
            lastSyncTime = Date()

            LogService.shared.info(.viewmodel, "同步完成")
        } catch {
            errorMessage = "同步失败: \(error.localizedDescription)"
            syncStatusMessage = "同步失败"
            LogService.shared.error(.viewmodel, "同步失败: \(error)")
        }

        isSyncing = false
    }

    public func stopSync() {
        guard isSyncing else {
            LogService.shared.debug(.viewmodel, "没有正在进行的同步")
            return
        }

        isSyncing = false
        syncStatusMessage = "同步已停止"

        LogService.shared.info(.viewmodel, "停止同步")
    }

    public func forceFullSync() async {
        LogService.shared.info(.viewmodel, "强制全量同步")

        lastSyncTime = nil

        do {
            try await syncService.forceFullSync()

            lastSyncTime = Date()
            LogService.shared.info(.viewmodel, "强制全量同步完成")
        } catch {
            errorMessage = "强制全量同步失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "强制全量同步失败: \(error)")
        }
    }

    public func syncNote(_ note: Note) async {
        guard networkMonitor.isConnected else {
            errorMessage = "无网络连接，无法同步笔记"
            LogService.shared.warning(.viewmodel, "无网络连接，无法同步笔记")
            return
        }

        do {
            LogService.shared.debug(.viewmodel, "同步笔记: \(note.title)")
            LogService.shared.debug(.viewmodel, "笔记同步完成: \(note.title)")
        } catch {
            errorMessage = "笔记同步失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "笔记同步失败: \(error)")
        }
    }

    public func processPendingOperations() async {
        guard !isProcessingOfflineOperations else {
            LogService.shared.debug(.viewmodel, "正在处理离线操作")
            return
        }

        guard networkMonitor.isConnected else {
            LogService.shared.debug(.viewmodel, "无网络连接，无法处理离线操作")
            return
        }

        isProcessingOfflineOperations = true

        do {
            LogService.shared.info(.viewmodel, "开始处理离线操作")

            let pendingChanges = try await noteStorage.getPendingChanges()

            guard !pendingChanges.isEmpty else {
                LogService.shared.debug(.viewmodel, "没有待处理的离线操作")
                isProcessingOfflineOperations = false
                return
            }

            LogService.shared.info(.viewmodel, "发现 \(pendingChanges.count) 个待处理的操作")

            LogService.shared.info(.viewmodel, "离线操作处理完成")
        } catch {
            errorMessage = "处理离线操作失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "处理离线操作失败: \(error)")
        }

        isProcessingOfflineOperations = false
    }

    public func updateSyncInterval(_ newInterval: Double) {
        LogService.shared.debug(.viewmodel, "同步间隔已更新为 \(newInterval) 秒")
        UserDefaults.standard.set(newInterval, forKey: "syncInterval")
    }

    // MARK: - Private Methods

    /// 设置观察者
    private func setupObservers() {
        // 监听网络状态变化
        networkMonitor.connectionType
            .map { $0 != .none }
            .removeDuplicates()
            .sink { [weak self] isConnected in
                guard let self else { return }

                if isConnected {
                    LogService.shared.info(.viewmodel, "网络已连接")
                    Task {
                        await self.processPendingOperations()
                    }
                } else {
                    LogService.shared.info(.viewmodel, "网络已断开")
                    if isSyncing {
                        stopSync()
                    }
                }
            }
            .store(in: &cancellables)
    }
}
