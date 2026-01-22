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
enum SyncState {
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
protocol SyncServiceProtocol {
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
}

// MARK: - Supporting Types

/// 同步操作
struct SyncOperation: Codable, Identifiable {
    /// 操作ID
    let id: String

    /// 操作类型
    let type: OperationType

    /// 笔记变更
    let change: NoteChange

    /// 时间戳
    let timestamp: Date

    enum OperationType: String, Codable {
        case upload
        case download
    }

    init(id: String = UUID().uuidString, type: OperationType, change: NoteChange, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.change = change
        self.timestamp = timestamp
    }
}

/// 冲突解决策略
enum ConflictResolutionStrategy {
    /// 使用本地版本
    case useLocal

    /// 使用远程版本
    case useRemote

    /// 合并版本
    case merge
}
