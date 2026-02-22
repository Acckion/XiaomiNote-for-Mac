import Combine
import Foundation
import Network

/// 默认网络监控实现
final class DefaultNetworkMonitor: NetworkMonitorProtocol, @unchecked Sendable {
    // MARK: - Properties

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.minote.networkmonitor")
    private let connectionTypeSubject = CurrentValueSubject<ConnectionType, Never>(.none)
    private let isConnectedSubject = CurrentValueSubject<Bool, Never>(false)

    var connectionType: AnyPublisher<ConnectionType, Never> {
        connectionTypeSubject.eraseToAnyPublisher()
    }

    var isConnected: Bool {
        isConnectedSubject.value
    }

    // MARK: - Initialization

    init() {
        setupMonitoring()
    }

    deinit {
        // 直接取消监控，不需要通过 stopMonitoring()
        monitor.cancel()
    }

    // MARK: - Public Methods

    func startMonitoring() {
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - Private Methods

    private nonisolated func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let isConnected = path.status == .satisfied
            let connectionType = determineConnectionType(from: path)

            // 在主线程更新 Subject，避免 Sendable 警告
            Task { @MainActor in
                self.isConnectedSubject.send(isConnected)
                self.connectionTypeSubject.send(connectionType)
            }
        }

        Task { @MainActor in
            self.startMonitoring()
        }
    }

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
