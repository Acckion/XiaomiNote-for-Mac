import Foundation

/// 操作队列事件
public enum OperationEvent: AppEvent {
    case operationCompleted
    case queueProcessingCompleted(successCount: Int, failedCount: Int)
    case authFailed

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
