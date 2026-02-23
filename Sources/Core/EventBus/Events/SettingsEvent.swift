import Foundation

/// 设置事件
public enum SettingsEvent: AppEvent {
    case showLoginRequested
    case editorSettingsChanged

    // MARK: - AppEvent

    public var id: UUID {
        UUID()
    }

    public var timestamp: Date {
        Date()
    }

    public var source: EventSource {
        .user
    }
}
