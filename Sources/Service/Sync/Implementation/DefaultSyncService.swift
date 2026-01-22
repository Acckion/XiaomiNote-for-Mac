import Foundation
import Combine

/// 默认同步服务实现
final class DefaultSyncService: SyncServiceProtocol, @unchecked Sendable {
    // MARK: - Properties
    private let networkClient: NetworkClient
    private let storage: NoteStorageProtocol
    private let syncStateSubject = CurrentValueSubject<SyncState, Never>(.idle)
    private let syncProgressSubject = PassthroughSubject<Double, Never>()
    private var syncTask: Task<Void, Never>?

    var syncState: AnyPublisher<SyncState, Never> {
        syncStateSubject.eraseToAnyPublisher()
    }

    var syncProgress: AnyPublisher<Double, Never> {
        syncProgressSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization
    init(networkClient: NetworkClient, storage: NoteStorageProtocol) {
        self.networkClient = networkClient
        self.storage = storage
    }

    // MARK: - Public Methods
    func startSync() async throws {
        syncStateSubject.send(.syncing)
        syncProgressSubject.send(0.0)

        do {
            // 获取本地更改
            let localChanges = try await storage.getPendingChanges()
            syncProgressSubject.send(0.2)

            // 上传本地更改
            if !localChanges.isEmpty {
                try await uploadChanges(localChanges)
            }
            syncProgressSubject.send(0.5)

            // 下载远程更改
            let remoteChanges: [NoteChange] = try await networkClient.request("/sync/changes")
            syncProgressSubject.send(0.8)

            // 应用远程更改
            for change in remoteChanges {
                try await applyChange(change)
            }

            syncProgressSubject.send(1.0)
            syncStateSubject.send(.idle)
        } catch {
            syncStateSubject.send(.failed(error))
            throw error
        }
    }

    func stopSync() {
        syncTask?.cancel()
        syncStateSubject.send(.idle)
    }

    func syncNote(_ note: Note) async throws {
        let parameters: [String: Any] = [
            "id": note.id,
            "title": note.title,
            "content": note.content,
            "folderId": note.folderId ?? ""
        ]

        let _: Note = try await networkClient.request(
            "/notes/\(note.id)/sync",
            method: .post,
            parameters: parameters
        )
    }

    func resolveConflict(_ operation: SyncOperation, strategy: ConflictResolutionStrategy) async throws {
        switch strategy {
        case .useLocal:
            try await uploadChanges([operation.change])
        case .useRemote:
            try await applyChange(operation.change)
        case .merge:
            // 简单合并策略：使用最新时间戳
            if let localNote = try? await storage.getNote(id: operation.change.noteId),
               let remoteNote = operation.change.note {
                let merged = localNote.updatedAt > remoteNote.updatedAt ? localNote : remoteNote
                try await storage.saveNote(merged)
            }
        }
    }

    func getPendingOperations() async throws -> [SyncOperation] {
        let changes = try await storage.getPendingChanges()
        return changes.map { change in
            SyncOperation(
                id: UUID().uuidString,
                type: .upload,
                change: change,
                timestamp: Date()
            )
        }
    }

    func getPendingOperationCount() throws -> Int {
        // 简化实现：返回 0
        // 实际应该从 storage 获取待处理操作数量
        return 0
    }

    func clearPendingOperations() throws {
        // 简化实现：暂不实现
        // 实际应该清除 storage 中的待处理操作
    }

    func processPendingOperations() async throws {
        // 简化实现：暂不实现
        // 实际应该处理 storage 中的待处理操作
    }

    func queueOperation(_ operation: SyncOperation) throws {
        // 简化实现：暂不实现
        // 实际应该将操作添加到 storage 的队列中
    }

    var isSyncing: AnyPublisher<Bool, Never> {
        syncStateSubject
            .map { state in
                if case .syncing = state {
                    return true
                }
                return false
            }
            .eraseToAnyPublisher()
    }

    var lastSyncTime: Date? {
        // 简化实现：返回 nil
        // 实际应该从 storage 获取最后同步时间
        return nil
    }

    func forceFullSync() async throws {
        // 简化实现：调用 startSync
        try await startSync()
    }

    func syncNote(id: String) async throws {
        // 简化实现：从 storage 获取笔记并同步
        if let note = try? await storage.getNote(id: id) {
            try await syncNote(note)
        }
    }

    // MARK: - Private Methods
    private func uploadChanges(_ changes: [NoteChange]) async throws {
        let parameters: [String: Any] = [
            "changes": changes.map { change in
                [
                    "noteId": change.noteId,
                    "type": change.type.rawValue,
                    "timestamp": change.timestamp.timeIntervalSince1970
                ]
            }
        ]

        try await networkClient.request(
            "/sync/upload",
            method: .post,
            parameters: parameters
        ) as EmptyResponse
    }

    private func applyChange(_ change: NoteChange) async throws {
        switch change.type {
        case .create, .update:
            if let note = change.note {
                try await storage.saveNote(note)
            }
        case .delete:
            try await storage.deleteNote(id: change.noteId)
        }
    }
}

// MARK: - Supporting Types
private struct EmptyResponse: Decodable {}
