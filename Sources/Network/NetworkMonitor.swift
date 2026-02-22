import Combine
import Foundation
import Network

/// 网络状态监控服务
///
/// 只负责监控网络连接状态，不涉及认证或Cookie有效性检查
/// 在线状态的计算由 OnlineStateManager 统一管理
@MainActor
final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    static let shared = NetworkMonitor()

    /// 网络是否连接（只检查网络连接，不检查认证）
    @Published var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied

                if wasConnected != self.isConnected {
                    LogService.shared.debug(.network, "网络连接状态变化: \(self.isConnected ? "已连接" : "已断开")")
                    if self.isConnected {
                        // 网络恢复，通知需要同步
                        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)
                    }
                }
            }
        }
        monitor.start(queue: queue)

        // 初始状态
        let currentPath = monitor.currentPath
        isConnected = currentPath.status == .satisfied
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - NetworkMonitorProtocol Conformance

extension NetworkMonitor: @MainActor NetworkMonitorProtocol {
    var connectionType: AnyPublisher<ConnectionType, Never> {
        // 将 isConnected 转换为 ConnectionType
        $isConnected
            .map { isConnected in
                isConnected ? .wifi : .none // 简化实现，假设连接时为 WiFi
            }
            .eraseToAnyPublisher()
    }

    func stopMonitoring() {
        monitor.cancel()
    }
}

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("networkDidBecomeAvailable")
}
