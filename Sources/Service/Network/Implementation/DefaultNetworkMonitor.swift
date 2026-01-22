import Foundation
import Network
import Combine

/// 默认网络监控实现
final class DefaultNetworkMonitor: NetworkMonitorProtocol {
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
        stopMonitoring()
    }

    // MARK: - Public Methods
    func startMonitoring() {
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - Private Methods
    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let isConnected = path.status == .satisfied
            self.isConnectedSubject.send(isConnected)

            let connectionType = self.determineConnectionType(from: path)
            self.connectionTypeSubject.send(connectionType)
        }

        startMonitoring()
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.status == .satisfied {
            return .other
        } else {
            return .none
        }
    }
}
