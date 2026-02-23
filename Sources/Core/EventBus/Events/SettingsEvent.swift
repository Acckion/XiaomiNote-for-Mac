import Foundation

/// 设置事件
enum SettingsEvent: AppEvent {
    case showLoginRequested
    case editorSettingsChanged

    // MARK: - AppEvent

    var id: UUID {
        UUID()
    }

    var timestamp: Date {
        Date()
    }

    var source: EventSource {
        .user
    }
}
