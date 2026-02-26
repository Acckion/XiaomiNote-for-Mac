import Foundation

/// ID 映射事件
public enum IdMappingEvent: AppEvent {
    case mappingCompleted(localId: String, serverId: String, entityType: String)

    // MARK: - AppEvent

    public var id: UUID {
        UUID()
    }

    public var timestamp: Date {
        Date()
    }

    public var source: EventSource {
        .sync
    }
}
