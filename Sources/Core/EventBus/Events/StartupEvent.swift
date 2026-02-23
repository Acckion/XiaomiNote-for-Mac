import Foundation

/// 启动序列事件
public enum StartupEvent: AppEvent {
    case startupCompleted(success: Bool, errors: [String], duration: TimeInterval)

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
