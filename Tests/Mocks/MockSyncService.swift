//
//  MockSyncService.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 同步服务 - 用于测试
//

import Combine
import Foundation
@testable import MiNoteLibrary

/// Mock 同步服务
///
/// 用于测试的同步服务实现，可以模拟各种同步场景
final class MockSyncService: SyncServiceProtocol, @unchecked Sendable {
    // MARK: - Mock 数据

    private let isSyncingSubject = CurrentValueSubject<Bool, Never>(false)
    private let syncProgressSubject = CurrentValueSubject<Double, Never>(0.0)
    private let syncStateSubject = CurrentValueSubject<SyncState, Never>(.idle)

    var mockLastSyncTime: Date?
    var mockError: Error?
    var mockPendingOperations: [SyncOperation] = []
    var mockConflictResolution: Note?

    // MARK: - 调用计数

    var startSyncCallCount = 0
    var stopSyncCallCount = 0
    var syncNoteCallCount = 0
    var syncFolderCallCount = 0
    var forceFullSyncCallCount = 0
    var queueOperationCallCount = 0
    var processPendingOperationsCallCount = 0
    var getPendingOperationCountCallCount = 0
    var clearPendingOperationsCallCount = 0
    var resolveConflictCallCount = 0
    var getPendingOperationsCallCount = 0

    // MARK: - SyncServiceProtocol - 同步状态

    var syncState: AnyPublisher<SyncState, Never> {
        syncStateSubject.eraseToAnyPublisher()
    }

    var isSyncing: AnyPublisher<Bool, Never> {
        isSyncingSubject.eraseToAnyPublisher()
    }

    var lastSyncTime: Date? {
        mockLastSyncTime
    }

    var syncProgress: AnyPublisher<Double, Never> {
        syncProgressSubject.eraseToAnyPublisher()
    }

    // MARK: - SyncServiceProtocol - 同步操作

    func startSync() async throws {
        startSyncCallCount += 1

        if let error = mockError {
            syncStateSubject.send(.failed(error))
            throw error
        }

        syncStateSubject.send(.syncing)
        isSyncingSubject.send(true)

        // 模拟同步进度
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            syncProgressSubject.send(progress)
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01秒
        }

        mockLastSyncTime = Date()
        syncStateSubject.send(.idle)
        isSyncingSubject.send(false)
        syncProgressSubject.send(0.0)
    }

    func stopSync() {
        stopSyncCallCount += 1
        syncStateSubject.send(.idle)
        isSyncingSubject.send(false)
        syncProgressSubject.send(0.0)
    }

    func syncNote(_: Note) async throws {
        syncNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        // 模拟同步单个笔记
    }

    func syncNote(id _: String) async throws {
        syncNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        // 模拟同步单个笔记
    }

    func syncFolder(id _: String) async throws {
        syncFolderCallCount += 1

        if let error = mockError {
            throw error
        }

        // 模拟同步文件夹
    }

    func forceFullSync() async throws {
        forceFullSyncCallCount += 1

        if let error = mockError {
            throw error
        }

        mockLastSyncTime = nil
        try await startSync()
    }

    // MARK: - SyncServiceProtocol - 离线队列

    func queueOperation(_ operation: SyncOperation) throws {
        queueOperationCallCount += 1

        if let error = mockError {
            throw error
        }

        mockPendingOperations.append(operation)
    }

    func processPendingOperations() async throws {
        processPendingOperationsCallCount += 1

        if let error = mockError {
            throw error
        }

        // 模拟处理待处理操作
        mockPendingOperations.removeAll()
    }

    func getPendingOperationCount() throws -> Int {
        getPendingOperationCountCallCount += 1

        if let error = mockError {
            throw error
        }

        return mockPendingOperations.count
    }

    func clearPendingOperations() throws {
        clearPendingOperationsCallCount += 1

        if let error = mockError {
            throw error
        }

        mockPendingOperations.removeAll()
    }

    func getPendingOperations() async throws -> [SyncOperation] {
        getPendingOperationsCallCount += 1

        if let error = mockError {
            throw error
        }

        return mockPendingOperations
    }

    // MARK: - SyncServiceProtocol - 冲突处理

    func resolveConflict(_: SyncOperation, strategy _: ConflictResolutionStrategy) async throws {
        resolveConflictCallCount += 1

        if let error = mockError {
            throw error
        }

        // 模拟冲突解决
    }

    // MARK: - Helper Methods

    /// 设置同步状态
    func setSyncing(_ syncing: Bool) {
        isSyncingSubject.send(syncing)
    }

    /// 设置同步进度
    func setSyncProgress(_ progress: Double) {
        syncProgressSubject.send(progress)
    }

    /// 重置所有状态
    func reset() {
        isSyncingSubject.send(false)
        syncProgressSubject.send(0.0)
        mockLastSyncTime = nil
        mockError = nil
        mockPendingOperations.removeAll()
        mockConflictResolution = nil
        resetCallCounts()
    }

    /// 重置调用计数
    func resetCallCounts() {
        startSyncCallCount = 0
        stopSyncCallCount = 0
        syncNoteCallCount = 0
        syncFolderCallCount = 0
        forceFullSyncCallCount = 0
        queueOperationCallCount = 0
        processPendingOperationsCallCount = 0
        getPendingOperationCountCallCount = 0
        clearPendingOperationsCallCount = 0
        resolveConflictCallCount = 0
    }
}
