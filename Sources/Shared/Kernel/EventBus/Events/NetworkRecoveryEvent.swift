import Foundation

/// 网络恢复事件
public enum NetworkRecoveryEvent: AppEvent {
    case recoveryStarted
    case recoveryCompleted(successCount: Int, failedCount: Int)

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
