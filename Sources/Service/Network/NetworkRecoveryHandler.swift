import Combine
import Foundation

/// 网络恢复处理器
///
/// 负责监听网络状态变化，并在网络恢复时自动处理离线队列
///
/// 遵循需求 8.6：网络恢复时自动处理离线队列中的待处理操作
@MainActor
public final class NetworkRecoveryHandler: ObservableObject {
    public static let shared = NetworkRecoveryHandler()

    // MARK: - 配置

    /// 网络恢复后的处理延迟（秒）
    ///
    /// 延迟一小段时间确保网络完全稳定
    public var recoveryDelay: TimeInterval = 2.0

    /// 是否启用自动处理
    public var autoProcessEnabled = true

    // MARK: - 依赖服务

    private let networkMonitor = NetworkMonitor.shared
    private let onlineStateManager = OnlineStateManager.shared
    /// 新的操作处理器（替代旧的 OfflineOperationProcessor）
    private let operationProcessor = OperationProcessor.shared
    /// 统一操作队列（替代旧的 OfflineOperationQueue）
    private let unifiedQueue = UnifiedOperationQueue.shared

    // MARK: - 状态

    /// 是否正在等待处理
    @Published public private(set) var isWaitingToProcess = false

    /// 上次网络恢复时间
    @Published public private(set) var lastRecoveryTime: Date?

    /// 上次处理结果
    @Published public private(set) var lastProcessingResult: ProcessingResult?

    /// 网络恢复次数（用于统计）
    @Published public private(set) var recoveryCount = 0

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    /// 网络恢复处理任务
    private var recoveryTask: Task<Void, Never>?

    // MARK: - 初始化

    private init() {
        setupNetworkMonitoring()
    }

    // MARK: - 网络监控设置

    /// 设置网络状态监控
    private func setupNetworkMonitoring() {
        // 监听网络连接状态变化
        networkMonitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    if isConnected {
                        await self?.handleNetworkRecovery()
                    } else {
                        self?.handleNetworkLost()
                    }
                }
            }
            .store(in: &cancellables)

        // 监听在线状态变化（包含 Cookie 有效性）
        onlineStateManager.$isOnline
            .removeDuplicates()
            .sink { [weak self] isOnline in
                Task { @MainActor in
                    if isOnline {
                        await self?.handleOnlineStateRecovery()
                    }
                }
            }
            .store(in: &cancellables)

        // 监听网络恢复通知
        NotificationCenter.default.publisher(for: .networkDidBecomeAvailable)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleNetworkRecovery()
                }
            }
            .store(in: &cancellables)

        // 监听 Cookie 刷新成功通知
        NotificationCenter.default.publisher(for: NSNotification.Name("CookieRefreshedSuccessfully"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    print("[NetworkRecoveryHandler] Cookie 刷新成功，检查是否需要处理离线队列")
                    await self?.handleOnlineStateRecovery()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 网络恢复处理

    /// 处理网络恢复事件
    ///
    /// 遵循需求 8.6
    private func handleNetworkRecovery() async {
        guard autoProcessEnabled else {
            print("[NetworkRecoveryHandler] 自动处理已禁用，跳过")
            return
        }

        print("[NetworkRecoveryHandler] 🌐 检测到网络恢复")
        recoveryCount += 1
        lastRecoveryTime = Date()

        // 取消之前的恢复任务（如果有）
        recoveryTask?.cancel()

        // 检查是否有待处理的操作（使用新的 UnifiedOperationQueue）
        let pendingCount = unifiedQueue.getPendingOperations().count
        if pendingCount == 0 {
            print("[NetworkRecoveryHandler] 离线队列为空，无需处理")
            return
        }

        print("[NetworkRecoveryHandler] 发现 \(pendingCount) 个待处理操作，将在 \(recoveryDelay) 秒后开始处理")
        isWaitingToProcess = true

        // 延迟处理，确保网络稳定
        recoveryTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(recoveryDelay * 1_000_000_000))

                // 检查任务是否被取消
                if Task.isCancelled {
                    print("[NetworkRecoveryHandler] 恢复任务被取消")
                    isWaitingToProcess = false
                    return
                }

                // 再次检查在线状态
                guard onlineStateManager.isOnline else {
                    print("[NetworkRecoveryHandler] 网络状态不稳定，取消处理")
                    isWaitingToProcess = false
                    lastProcessingResult = ProcessingResult(
                        success: false,
                        processedCount: 0,
                        failedCount: 0,
                        skippedReason: "网络状态不稳定"
                    )
                    return
                }

                await processOfflineQueue()
            } catch {
                print("[NetworkRecoveryHandler] 恢复任务出错: \(error)")
                isWaitingToProcess = false
            }
        }
    }

    /// 处理在线状态恢复（包含 Cookie 有效性）
    private func handleOnlineStateRecovery() async {
        guard autoProcessEnabled else {
            print("[NetworkRecoveryHandler] 自动处理已禁用，跳过")
            return
        }

        // 检查是否有待处理的操作（使用新的 UnifiedOperationQueue）
        let pendingCount = unifiedQueue.getPendingOperations().count
        if pendingCount == 0 {
            print("[NetworkRecoveryHandler] 离线队列为空，无需处理")
            return
        }

        print("[NetworkRecoveryHandler] ✅ 在线状态恢复，发现 \(pendingCount) 个待处理操作")

        // 如果已经在等待处理，不重复触发
        if isWaitingToProcess {
            print("[NetworkRecoveryHandler] 已在等待处理中，跳过")
            return
        }

        await processOfflineQueue()
    }

    /// 处理网络断开事件
    private func handleNetworkLost() {
        print("[NetworkRecoveryHandler] 📴 网络断开")

        // 取消正在等待的恢复任务
        recoveryTask?.cancel()
        isWaitingToProcess = false
    }

    /// 处理离线队列
    private func processOfflineQueue() async {
        isWaitingToProcess = false

        print("[NetworkRecoveryHandler] 🚀 开始处理离线队列")

        // 发送开始处理通知
        NotificationCenter.default.post(
            name: .networkRecoveryProcessingStarted,
            object: nil
        )

        // 获取处理前的统计
        let beforeStats = unifiedQueue.getStatistics()
        let beforePending = (beforeStats["pending"] ?? 0) + (beforeStats["failed"] ?? 0)

        // 调用新的 OperationProcessor 处理队列
        await operationProcessor.processQueue()

        // 获取处理后的统计
        let afterStats = unifiedQueue.getStatistics()
        let afterPending = (afterStats["pending"] ?? 0) + (afterStats["failed"] ?? 0)
        let failedCount = afterStats["failed"] ?? 0

        let successCount = max(0, beforePending - afterPending)

        lastProcessingResult = ProcessingResult(
            success: failedCount == 0,
            processedCount: successCount,
            failedCount: failedCount,
            skippedReason: nil
        )

        print("[NetworkRecoveryHandler] ✅ 离线队列处理完成，成功: \(successCount)，失败: \(failedCount)")

        // 发送处理完成通知
        NotificationCenter.default.post(
            name: .networkRecoveryProcessingCompleted,
            object: nil,
            userInfo: [
                "successCount": successCount,
                "failedCount": failedCount,
            ]
        )
    }

    // MARK: - 公共方法

    /// 手动触发离线队列处理
    ///
    /// - Returns: 处理结果
    public func triggerProcessing() async -> ProcessingResult {
        guard onlineStateManager.isOnline else {
            return ProcessingResult(
                success: false,
                processedCount: 0,
                failedCount: 0,
                skippedReason: "当前离线"
            )
        }

        await processOfflineQueue()
        return lastProcessingResult ?? ProcessingResult(
            success: false,
            processedCount: 0,
            failedCount: 0,
            skippedReason: "处理结果未知"
        )
    }

    /// 取消正在等待的处理
    public func cancelPendingProcessing() {
        recoveryTask?.cancel()
        isWaitingToProcess = false
        print("[NetworkRecoveryHandler] 已取消待处理的恢复任务")
    }

    /// 重置统计数据
    public func resetStatistics() {
        recoveryCount = 0
        lastRecoveryTime = nil
        lastProcessingResult = nil
    }
}

// MARK: - 处理结果

/// 离线队列处理结果
public struct ProcessingResult: Sendable {
    /// 是否成功（无失败操作）
    public let success: Bool

    /// 成功处理的操作数量
    public let processedCount: Int

    /// 失败的操作数量
    public let failedCount: Int

    /// 跳过原因（如果跳过处理）
    public let skippedReason: String?

    /// 处理时间戳
    public let timestamp: Date

    public init(
        success: Bool,
        processedCount: Int,
        failedCount: Int,
        skippedReason: String?
    ) {
        self.success = success
        self.processedCount = processedCount
        self.failedCount = failedCount
        self.skippedReason = skippedReason
        self.timestamp = Date()
    }
}

// MARK: - 通知扩展

public extension Notification.Name {
    /// 网络恢复处理开始通知
    static let networkRecoveryProcessingStarted = Notification.Name("networkRecoveryProcessingStarted")

    /// 网络恢复处理完成通知
    static let networkRecoveryProcessingCompleted = Notification.Name("networkRecoveryProcessingCompleted")
}
