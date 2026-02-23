import Foundation

/// 操作队列事件
enum OperationEvent: AppEvent {
    case operationCompleted
    case queueProcessingCompleted(successCount: Int, failedCount: Int)
    case authFailed

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
