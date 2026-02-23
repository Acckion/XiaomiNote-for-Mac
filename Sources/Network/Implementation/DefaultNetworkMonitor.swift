import Combine
import Foundation
import Network

/// 默认网络监控实现
actor DefaultNetworkMonitor: NetworkMonitorProtocol {
    // MARK: - Properties

    private let monitor = NWPathMonitor()
    /// NWPathMonitor 要求提供 DispatchQueue 用于回调
    private let queue = DispatchQueue(label: "com.minote.networkmonitor")
    // CurrentValueSubject 自身线程安全，标记 nonisolated 以支持协议的同步属性要求
    private nonisolated(unsafe) let connectionTypeSubject = CurrentValueSubject<ConnectionType, Never>(.none)
    private nonisolated(unsafe) let isConnectedSubject = CurrentValueSubject<Bool, Never>(false)

    nonisolated var connectionType: AnyPublisher<ConnectionType, Never> {
        connectionTypeSubject.eraseToAnyPublisher()
    }

    nonisolated var isConnected: Bool {
        isConnectedSubject.value
    }

    // MARK: - Initialization

    init() {
        setupMonitoring()
    }

    // MARK: - Public Methods

    nonisolated func startMonitoring() {
        monitor.start(queue: queue)
    }

    nonisolated func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - Private Methods

    /// 在 init 中调用，actor 的 init 是 nonisolated 的
    private nonisolated func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let isConnected = path.status == .satisfied
            let connectionType = determineConnectionType(from: path)

            isConnectedSubject.send(isConnected)
            connectionTypeSubject.send(connectionType)
        }

        startMonitoring()
    }

    /// 根据网络路径判断连接类型（纯函数）
    private nonisolated func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            .wifi
        } else if path.usesInterfaceType(.cellular) {
            .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            .ethernet
        } else if path.status == .satisfied {
            .other
        } else {
            .none
        }
    }
}
