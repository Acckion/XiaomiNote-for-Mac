import Foundation
import Network
import Combine

/// 网络状态监控服务
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isOnline: Bool = true
    @Published var isConnected: Bool = true
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOnline = self?.isOnline ?? false
                self?.isConnected = path.status == .satisfied
                // 只有在有网络连接且已认证时才认为在线
                self?.isOnline = path.status == .satisfied && MiNoteService.shared.isAuthenticated()
                
                if let isOnline = self?.isOnline, isOnline != wasOnline {
                    print("[NetworkMonitor] 网络状态变化: \(isOnline ? "在线" : "离线")")
                    if isOnline {
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
        isOnline = currentPath.status == .satisfied && MiNoteService.shared.isAuthenticated()
    }
    
    deinit {
        monitor.cancel()
    }
}

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("networkDidBecomeAvailable")
}

