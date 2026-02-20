import Foundation

/// 全量同步模式
enum FullSyncMode: Sendable {
    case normal
    case forceRedownload
    case simulatedIncremental
}

/// 同步模式
enum SyncMode: Sendable {
    case incremental
    case full(FullSyncMode)
}

/// 同步事件结果
struct SyncEventResult: Sendable {
    let downloadedCount: Int
    let uploadedCount: Int
    let deletedCount: Int
    let duration: TimeInterval
}

/// 同步事件
enum SyncEvent: AppEvent {
    case requested(mode: SyncMode)
    case started
    case progress(message: String, percent: Double)
    case noteDownloaded(Note)
    case completed(result: SyncEventResult)
    case failed(errorMessage: String)
    case tagUpdated(noteId: String, newTag: String)

    // MARK: - AppEvent

    var id: UUID {
        UUID()
    }

    var timestamp: Date {
        Date()
    }

    var source: EventSource {
        .sync
    }
}
