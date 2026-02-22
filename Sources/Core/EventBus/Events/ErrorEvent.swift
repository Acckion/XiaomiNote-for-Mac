import Foundation

/// 错误事件
enum ErrorEvent: AppEvent {
    case storageFailed(operation: String, errorMessage: String)
    case syncFailed(errorMessage: String, retryable: Bool)
    case authRequired(reason: String)

    // MARK: - AppEvent

    var id: UUID {
        UUID()
    }

    var timestamp: Date {
        Date()
    }

    var source: EventSource {
        .system
    }
}
