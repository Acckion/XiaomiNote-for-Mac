import Foundation

/// 网络恢复事件
enum NetworkRecoveryEvent: AppEvent {
    case recoveryStarted
    case recoveryCompleted(successCount: Int, failedCount: Int)

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
