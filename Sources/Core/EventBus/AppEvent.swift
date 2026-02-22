import Foundation

/// 事件来源
enum EventSource: String, Sendable {
    case editor
    case sync
    case user
    case system
}

/// 应用事件协议
///
/// 所有事件类型必须遵循此协议，确保事件具有唯一标识、时间戳和来源信息。
protocol AppEvent: Sendable {
    var id: UUID { get }
    var timestamp: Date { get }
    var source: EventSource { get }
}
