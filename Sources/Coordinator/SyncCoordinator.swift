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
/// 负责协调同步操作，通过 EventBus 发布同步请求事件，由 SyncEngine 实际执行。
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

    /// 笔记存储服务（本地数据库）
    private let noteStorage: NoteStorageProtocol

    /// 网络监控服务
    private let networkMonitor: NetworkMonitorProtocol

    /// 事件总线
    private let eventBus = EventBus.shared

    // MARK: - Private Properties

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 是否正在处理离线操作
    private var isProcessingOfflineOperations = false

    // MARK: - Initialization

    /// 初始化同步协调器
    ///
    /// - Parameters:
    ///   - noteStorage: 笔记存储服务（本地数据库）
    ///   - networkMonitor: 网络监控服务
    public init(
        noteStorage: NoteStorageProtocol,
        networkMonitor: NetworkMonitorProtocol
    ) {
        self.noteStorage = noteStorage
        self.networkMonitor = networkMonitor

        setupObservers()

        LogService.shared.info(.viewmodel, "SyncCoordinator 初始化完成")
    }

    // MARK: - Public Methods

    /// 启动同步（通过 EventBus 发布增量同步请求）
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

        LogService.shared.info(.viewmodel, "发布增量同步请求")
        await eventBus.publish(SyncEvent.requested(mode: .incremental))

        syncProgress = 1.0
        syncStatusMessage = "同步请求已发送"
        lastSyncTime = Date()
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

    /// 强制全量同步（通过 EventBus 发布全量同步请求）
    public func forceFullSync() async {
        LogService.shared.info(.viewmodel, "发布强制全量同步请求")

        lastSyncTime = nil
        await eventBus.publish(SyncEvent.requested(mode: .full(.normal)))
        lastSyncTime = Date()
    }

    public func syncNote(_ note: Note) async {
        guard networkMonitor.isConnected else {
            errorMessage = "无网络连接，无法同步笔记"
            LogService.shared.warning(.viewmodel, "无网络连接，无法同步笔记")
            return
        }

        LogService.shared.debug(.viewmodel, "同步笔记: \(note.title)")
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
