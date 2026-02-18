//
//  SyncService+SyncServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  SyncService 协议适配 - 实现 SyncServiceProtocol
//

import Combine
import Foundation

extension SyncService: SyncServiceProtocol {
    // MARK: - 同步状态

    /// 同步状态 Publisher
    var syncState: AnyPublisher<SyncState, Never> {
        // 使用 CurrentValueSubject 来发布同步状态
        // 注意：这里需要在 SyncService 中添加一个 private 的 subject
        // 暂时返回一个简单的实现
        Just(isSyncingNow ? .syncing : .idle)
            .eraseToAnyPublisher()
    }

    /// 同步进度 Publisher
    var syncProgress: AnyPublisher<Double, Never> {
        Just(currentProgress)
            .eraseToAnyPublisher()
    }

    /// 是否正在同步 Publisher
    var isSyncing: AnyPublisher<Bool, Never> {
        Just(isSyncingNow)
            .eraseToAnyPublisher()
    }

    // MARK: - 同步操作

    /// 开始同步
    /// 使用智能同步策略（自动选择完整同步或增量同步）
    func startSync() async throws {
        _ = try await performSmartSync()
    }

    /// 停止同步
    func stopSync() {
        cancelSync()
    }

    /// 同步指定笔记（使用 Note 对象）
    /// - Parameter note: 笔记对象
    func syncNote(_ note: Note) async throws {
        _ = try await syncSingleNote(noteId: note.id)
    }

    /// 同步指定笔记（使用笔记 ID）
    /// - Parameter id: 笔记ID
    func syncNote(id: String) async throws {
        _ = try await syncSingleNote(noteId: id)
    }

    // MARK: - 冲突处理

    /// 解决同步冲突
    /// - Parameters:
    ///   - operation: 同步操作
    ///   - strategy: 冲突解决策略
    func resolveConflict(_ operation: SyncOperation, strategy: ConflictResolutionStrategy) async throws {
        // SyncService 目前使用自动冲突解决策略（基于时间戳）
        // 这里提供一个手动冲突解决的接口

        switch strategy {
        case .useLocal:
            // 使用本地版本：将本地笔记上传到云端
            if operation.type == .upload {
                // 操作已经是上传，直接执行
                try unifiedQueue.enqueue(convertToNoteOperation(operation))
            }

        case .useRemote:
            // 使用远程版本：从云端下载笔记
            if operation.type == .download {
                // 操作已经是下载，直接执行
                _ = try await syncSingleNote(noteId: operation.change.noteId)
            }

        case .merge:
            // 合并版本：目前不支持，使用远程版本
            print("[SYNC] 合并策略暂不支持，使用远程版本")
            _ = try await syncSingleNote(noteId: operation.change.noteId)
        }
    }

    /// 获取待处理操作
    /// - Returns: 待处理操作列表
    func getPendingOperations() async throws -> [SyncOperation] {
        let noteOperations = unifiedQueue.getPendingOperations()
        return noteOperations.map { convertToSyncOperation($0) }
    }

    // MARK: - 离线队列管理

    /// 获取待处理操作数量
    /// - Returns: 待处理操作数量
    func getPendingOperationCount() throws -> Int {
        unifiedQueue.getPendingOperations().count
    }

    /// 清空待处理操作
    func clearPendingOperations() throws {
        try unifiedQueue.clearAll()
    }

    /// 处理待处理操作
    func processPendingOperations() async throws {
        // 使用 UnifiedOperationQueue 的处理逻辑
        // 注意：这里需要确保 UnifiedOperationQueue 有处理方法
        // 暂时使用同步来触发操作处理
        _ = try await performSmartSync()
    }

    /// 添加操作到队列
    /// - Parameter operation: 同步操作
    func queueOperation(_ operation: SyncOperation) throws {
        let noteOperation = convertToNoteOperation(operation)
        try unifiedQueue.enqueue(noteOperation)
    }

    // MARK: - 同步控制

    /// 强制全量同步
    func forceFullSync() async throws {
        _ = try await performFullSync()
    }

    // MARK: - 辅助方法

    /// 将 SyncOperation 转换为 NoteOperation
    private func convertToNoteOperation(_ syncOp: SyncOperation) -> NoteOperation {
        // SyncService 主要处理上传操作
        // 下载操作通常由同步流程自动处理
        let type: OperationType = .cloudUpload

        // 将 NoteChange 转换为 JSON 数据
        let opData: [String: Any] = [
            "noteId": syncOp.change.noteId,
        ]

        let data = (try? JSONSerialization.data(withJSONObject: opData)) ?? Data()

        return NoteOperation(
            type: type,
            noteId: syncOp.change.noteId,
            data: data,
            status: .pending,
            priority: NoteOperation.calculatePriority(for: type)
        )
    }

    /// 将 NoteOperation 转换为 SyncOperation
    private func convertToSyncOperation(_ noteOp: NoteOperation) -> SyncOperation {
        let type: SyncOperation.OperationType = switch noteOp.type {
        case .cloudUpload, .noteCreate:
            .upload
        default:
            // 其他操作类型默认为上传
            .upload
        }

        // 创建 NoteChange
        let changeType: NoteChange.ChangeType = switch noteOp.type {
        case .noteCreate:
            .create
        case .cloudUpload:
            .update
        case .cloudDelete:
            .delete
        default:
            .update
        }

        let change = NoteChange(
            id: noteOp.id,
            type: changeType,
            noteId: noteOp.noteId,
            note: nil,
            timestamp: noteOp.createdAt
        )

        return SyncOperation(
            id: noteOp.id,
            type: type,
            change: change,
            timestamp: noteOp.createdAt
        )
    }
}
