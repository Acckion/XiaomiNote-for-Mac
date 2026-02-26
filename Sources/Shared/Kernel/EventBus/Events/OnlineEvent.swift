import Foundation

/// 在线状态事件
public enum OnlineEvent: AppEvent {
    case onlineStatusChanged(isOnline: Bool)

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
