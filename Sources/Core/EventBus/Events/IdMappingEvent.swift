import Foundation

/// ID 映射事件
enum IdMappingEvent: AppEvent {
    case mappingCompleted(localId: String, serverId: String, entityType: String)

    // MARK: - AppEvent

    var id: UUID {
        UUID()
    }

    var timestamp: Date {
        Date()
    }

    var source: EventSource {
        .sync
    }
}
