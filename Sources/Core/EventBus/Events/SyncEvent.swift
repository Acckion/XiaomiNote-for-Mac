import Foundation

/// 全量同步模式
public enum FullSyncMode: Sendable {
    case normal
    case forceRedownload
    case simulatedIncremental
}

/// 同步模式
public enum SyncMode: Sendable {
    case incremental
    case full(FullSyncMode)
}

/// 同步事件结果
public struct SyncEventResult: Sendable {
    public let downloadedCount: Int
    public let uploadedCount: Int
    public let deletedCount: Int
    public let duration: TimeInterval

    public init(downloadedCount: Int, uploadedCount: Int, deletedCount: Int, duration: TimeInterval) {
        self.downloadedCount = downloadedCount
        self.uploadedCount = uploadedCount
        self.deletedCount = deletedCount
        self.duration = duration
    }
}

/// 同步事件
public enum SyncEvent: AppEvent {
    case requested(mode: SyncMode)
    case started
    case progress(message: String, percent: Double)
    case noteDownloaded(Note)
    case completed(result: SyncEventResult)
    case failed(errorMessage: String)
    case tagUpdated(noteId: String, newTag: String)

    // MARK: - AppEvent

    public var id: UUID {
        UUID()
    }

    public var timestamp: Date {
        Date()
    }

    public var source: EventSource {
        .sync
    }
}
