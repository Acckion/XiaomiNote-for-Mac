//
//  SyncServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  同步服务协议 - 定义笔记同步操作接口
//

import Foundation
import Combine

/// 同步状态
public enum SyncState {
    case idle
    case syncing
    case failed(Error)
}

/// 同步服务协议
///
/// 定义了笔记同步相关的操作接口，包括：
/// - 同步状态管理
/// - 同步操作
/// - 离线队列管理
@preconcurrency
public protocol SyncServiceProtocol: Sendable {
    // MARK: - 同步状态

    /// 同步状态
    var syncState: AnyPublisher<SyncState, Never> { get }

    /// 同步进度（0.0 - 1.0）
    var syncProgress: AnyPublisher<Double, Never> { get }

    // MARK: - 同步操作

    /// 开始同步
    func startSync() async throws

    /// 停止同步
    func stopSync()

    /// 同步指定笔记
    /// - Parameter note: 笔记对象
    func syncNote(_ note: Note) async throws

    // MARK: - 冲突处理

    /// 解决同步冲突
    /// - Parameters:
    ///   - operation: 同步操作
    ///   - strategy: 冲突解决策略
    func resolveConflict(_ operation: SyncOperation, strategy: ConflictResolutionStrategy) async throws

    /// 获取待处理操作
    /// - Returns: 待处理操作列表
    func getPendingOperations() async throws -> [SyncOperation]
    
    // MARK: - 离线队列管理
    
    /// 获取待处理操作数量
    /// - Returns: 待处理操作数量
    func getPendingOperationCount() throws -> Int
    
    /// 清空待处理操作
    func clearPendingOperations() throws
    
    /// 处理待处理操作
    func processPendingOperations() async throws
    
    /// 添加操作到队列
    /// - Parameter operation: 同步操作
    func queueOperation(_ operation: SyncOperation) throws
    
    // MARK: - 同步控制
    
    /// 是否正在同步
    var isSyncing: AnyPublisher<Bool, Never> { get }
    
    /// 最后同步时间
    var lastSyncTime: Date? { get }
    
    /// 强制全量同步
    func forceFullSync() async throws
    
    /// 同步指定笔记
    /// - Parameter id: 笔记ID
    func syncNote(id: String) async throws
}

// MARK: - Supporting Types

/// 同步操作
public struct SyncOperation: Codable, Identifiable {
    /// 操作ID
    public let id: String

    /// 操作类型
    public let type: OperationType

    /// 笔记变更
    public let change: NoteChange

    /// 时间戳
    public let timestamp: Date

    public enum OperationType: String, Codable {
        case upload
        case download
    }

    public init(id: String = UUID().uuidString, type: OperationType, change: NoteChange, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.change = change
        self.timestamp = timestamp
    }
}

/// 冲突解决策略
public enum ConflictResolutionStrategy {
    /// 使用本地版本
    case useLocal

    /// 使用远程版本
    case useRemote

    /// 合并版本
    case merge
}
