import Foundation

/// 错误事件
public enum ErrorEvent: AppEvent {
    case storageFailed(operation: String, errorMessage: String)
    case syncFailed(errorMessage: String, retryable: Bool)
    case authRequired(reason: String)

    // MARK: - AppEvent

    public var id: UUID {
        UUID()
    }

    public var timestamp: Date {
        Date()
    }

    public var source: EventSource {
        .system
    }
}
