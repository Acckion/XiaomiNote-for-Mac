//
//  SyncServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  同步服务协议 - 定义笔记同步操作接口
//

import Foundation
import Combine

/// 同步服务协议
///
/// 定义了笔记同步相关的操作接口，包括：
/// - 同步状态管理
/// - 同步操作
/// - 离线队列管理
protocol SyncServiceProtocol {
    // MARK: - 同步状态

    /// 是否正在同步
    var isSyncing: AnyPublisher<Bool, Never> { get }

    /// 最后同步时间
    var lastSyncTime: Date? { get }

    /// 同步进度（0.0 - 1.0）
    var syncProgress: AnyPublisher<Double, Never> { get }

    // MARK: - 同步操作

    /// 开始同步
    func startSync() async throws

    /// 停止同步
    func stopSync()

    /// 同步指定笔记
    /// - Parameter id: 笔记ID
    func syncNote(id: String) async throws

    /// 同步指定文件夹
    /// - Parameter id: 文件夹ID
    func syncFolder(id: String) async throws

    /// 强制全量同步
    func forceFullSync() async throws

    // MARK: - 离线队列

    /// 添加操作到队列
    /// - Parameter operation: 同步操作
    func queueOperation(_ operation: SyncOperation) throws

    /// 处理待处理的操作
    func processPendingOperations() async throws

    /// 获取待处理操作数量
    /// - Returns: 待处理操作数量
    func getPendingOperationCount() throws -> Int

    /// 清空待处理操作
    func clearPendingOperations() throws

    // MARK: - 冲突处理

    /// 解决同步冲突
    /// - Parameters:
    ///   - localNote: 本地笔记
    ///   - remoteNote: 远程笔记
    ///   - strategy: 冲突解决策略
    /// - Returns: 解决后的笔记
    func resolveConflict(
        localNote: Note,
        remoteNote: Note,
        strategy: ConflictResolutionStrategy
    ) async throws -> Note
}

// MARK: - Supporting Types

/// 同步操作
struct SyncOperation: Codable, Identifiable {
    /// 操作ID
    let id: String

    /// 操作类型
    let type: OperationType

    /// 笔记ID
    let noteId: String

    /// 笔记数据（创建和更新时需要）
    let noteData: Data?

    /// 时间戳
    let timestamp: Date

    /// 重试次数
    var retryCount: Int = 0

    enum OperationType: String, Codable {
        case create
        case update
        case delete
    }

    init(id: String = UUID().uuidString, type: OperationType, noteId: String, noteData: Data? = nil, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.noteId = noteId
        self.noteData = noteData
        self.timestamp = timestamp
        self.retryCount = 0
    }
}

/// 冲突解决策略
enum ConflictResolutionStrategy {
    /// 使用本地版本
    case useLocal

    /// 使用远程版本
    case useRemote

    /// 使用最新版本（根据时间戳）
    case useNewest

    /// 手动解决
    case manual
}
