import Foundation

/// 事件总线
///
/// 全局事件分发中心，支持发布-订阅模式。
/// 使用 actor 保证并发安全。
public actor EventBus {
    static let shared = EventBus()

    /// 事件历史最大容量
    private let maxHistoryCount = 200

    /// 类型擦除的订阅者字典：[事件类型标识: [订阅者ID: continuation]]
    private var subscribers: [ObjectIdentifier: [UUID: Any]] = [:]

    /// 事件历史记录
    private var eventHistory: [any AppEvent] = []

    private init() {}

    // MARK: - 发布

    /// 发布事件给所有订阅者
    func publish<E: AppEvent>(_ event: E) {
        recordEvent(event)

        let typeId = ObjectIdentifier(E.self)
        guard let typedSubscribers = subscribers[typeId] else { return }

        for (_, continuation) in typedSubscribers {
            if let cont = continuation as? AsyncStream<E>.Continuation {
                cont.yield(event)
            }
        }
    }

    // MARK: - 订阅

    /// 订阅特定类型的事件
    func subscribe<E: AppEvent>(to _: E.Type) -> AsyncStream<E> {
        let subscriberId = UUID()
        let typeId = ObjectIdentifier(E.self)

        return AsyncStream<E> { continuation in
            if self.subscribers[typeId] == nil {
                self.subscribers[typeId] = [:]
            }
            self.subscribers[typeId]?[subscriberId] = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscriber(subscriberId, for: typeId) }
            }
        }
    }

    // MARK: - 调试

    /// 获取最近的事件历史
    func recentEvents(limit: Int) -> [any AppEvent] {
        let count = min(limit, eventHistory.count)
        return Array(eventHistory.suffix(count))
    }

    // MARK: - 内部方法

    /// 记录事件到历史
    private func recordEvent(_ event: any AppEvent) {
        eventHistory.append(event)
        if eventHistory.count > maxHistoryCount {
            eventHistory.removeFirst(eventHistory.count - maxHistoryCount)
        }
    }

    /// 移除订阅者
    private func removeSubscriber(_ subscriberId: UUID, for typeId: ObjectIdentifier) {
        subscribers[typeId]?.removeValue(forKey: subscriberId)
        if subscribers[typeId]?.isEmpty == true {
            subscribers.removeValue(forKey: typeId)
        }
    }
}
