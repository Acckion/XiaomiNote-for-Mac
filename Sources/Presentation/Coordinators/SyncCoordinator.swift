//
//  SyncCoordinator.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  同步协调器 - 负责协调笔记同步操作
//

@preconcurrency import Foundation
@preconcurrency import Combine

/// 同步协调器
///
/// 负责协调笔记同步相关的逻辑，包括：
/// - 触发同步操作
/// - 处理同步冲突
/// - 管理离线队列
/// - 同步状态通知
@MainActor
final class SyncCoordinator: LoadableViewModel {
    // MARK: - Dependencies

    private let syncService: SyncServiceProtocol
    private let noteStorage: NoteStorageProtocol
    private let networkMonitor: NetworkMonitorProtocol

    // MARK: - Published Properties

    /// 是否正在同步
    @Published var isSyncing: Bool = false

    /// 同步进度（0.0 - 1.0）
    @Published var syncProgress: Double = 0.0

    /// 最后同步时间
    @Published var lastSyncTime: Date?

    /// 是否在线
    @Published var isOnline: Bool = true

    /// 待处理操作数量
    @Published var pendingOperationCount: Int = 0

    // MARK: - Initialization

    init(
        syncService: SyncServiceProtocol,
        noteStorage: NoteStorageProtocol,
        networkMonitor: NetworkMonitorProtocol
    ) {
        self.syncService = syncService
        self.noteStorage = noteStorage
        self.networkMonitor = networkMonitor
        super.init()
    }

    // MARK: - Setup

    override func setupBindings() {
        // 监听同步状态
        syncService.isSyncing
            .assign(to: &$isSyncing)

        // 监听同步进度
        syncService.syncProgress
            .assign(to: &$syncProgress)

        // 监听网络状态（通过 connectionType）
        networkMonitor.connectionType
            .map { $0 != .none }
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected

                // 网络恢复时自动同步
                if isConnected {
                    Task { await self?.syncIfNeeded() }
                }
            }
            .store(in: &cancellables)

        // 更新最后同步时间
        lastSyncTime = syncService.lastSyncTime
    }

    // MARK: - Public Methods

    /// 开始同步
    func startSync() async {
        guard isOnline else {
            error = NSError(domain: "Sync", code: -1, userInfo: [NSLocalizedDescriptionKey: "No network connection"])
            return
        }

        await withLoadingSafe { [syncService] in
            try await syncService.startSync()
            self.lastSyncTime = Date()
            await self.updatePendingOperationCount()
        }
    }

    /// 停止同步
    func stopSync() {
        syncService.stopSync()
    }

    /// 强制全量同步
    func forceFullSync() async {
        guard isOnline else {
            error = NSError(domain: "Sync", code: -1, userInfo: [NSLocalizedDescriptionKey: "No network connection"])
            return
        }

        await withLoadingSafe { [syncService] in
            try await syncService.forceFullSync()
            self.lastSyncTime = Date()
        }
    }

    /// 同步指定笔记
    /// - Parameter noteId: 笔记ID
    func syncNote(_ noteId: String) async {
        guard isOnline else { return }

        await withLoadingSafe { [syncService] in
            try await syncService.syncNote(id: noteId)
        }
    }

    /// 如果需要则同步
    func syncIfNeeded() async {
        // 检查是否需要同步
        guard isOnline else { return }
        guard !isSyncing else { return }

        // 如果有待处理操作，执行同步
        await updatePendingOperationCount()
        if pendingOperationCount > 0 {
            await startSync()
        }
    }

    /// 添加操作到离线队列
    /// - Parameter operation: 同步操作
    func queueOperation(_ operation: SyncOperation) async {
        await withLoadingSafe {
            try syncService.queueOperation(operation)
            await self.updatePendingOperationCount()
        }
    }

    /// 处理待处理操作
    func processPendingOperations() async {
        guard isOnline else { return }

        await withLoadingSafe { [syncService] in
            try await syncService.processPendingOperations()
            await self.updatePendingOperationCount()
        }
    }

    /// 清空待处理操作
    func clearPendingOperations() async {
        await withLoadingSafe {
            try syncService.clearPendingOperations()
            self.pendingOperationCount = 0
        }
    }

    // MARK: - Private Methods

    /// 更新待处理操作数量
    private func updatePendingOperationCount() async {
        do {
            pendingOperationCount = try syncService.getPendingOperationCount()
        } catch {
            self.error = error
        }
    }
}
