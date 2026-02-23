import Foundation

/// 在线状态事件
enum OnlineEvent: AppEvent {
    case onlineStatusChanged(isOnline: Bool)

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
