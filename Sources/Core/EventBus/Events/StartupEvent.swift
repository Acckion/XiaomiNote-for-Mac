import Foundation

/// 启动序列事件
enum StartupEvent: AppEvent {
    case startupCompleted(success: Bool, errors: [String], duration: TimeInterval)

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
