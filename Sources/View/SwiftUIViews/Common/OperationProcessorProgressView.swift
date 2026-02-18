import Combine
import SwiftUI

/// 操作处理器进度视图
///
/// 基于新的 OperationProcessor 和 UnifiedOperationQueue 的进度显示
/// 替代旧的 OfflineOperationsProgressView
@available(macOS 14.0, *)
struct OperationProcessorProgressView: View {
    @StateObject private var viewModel: OperationProcessorProgressViewModel
    var onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: OperationProcessorProgressViewModel())
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 16) {
            Divider()

            // 进度信息
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    // 进度条
                    ProgressView(value: viewModel.progress) {
                        HStack {
                            Text("进度")
                                .font(.caption)
                            Spacer()
                            Text("\(viewModel.processedCount) / \(viewModel.totalCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 状态消息
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 当前操作
                    if let currentOperation = viewModel.currentOperationType {
                        HStack {
                            Text("正在处理:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currentOperation)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            } else {
                // 处理完成或未开始
                if viewModel.totalCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("处理完成")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text("成功: \(viewModel.successCount)")
                                .foregroundColor(.green)
                            if viewModel.failedCount > 0 {
                                Text("失败: \(viewModel.failedCount)")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    Text("没有待处理的操作")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // 失败操作列表
            if !viewModel.failedOperations.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("失败的操作")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.failedOperations, id: \.id) { operation in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(operation.type.rawValue)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        if let error = operation.lastError {
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }

            Divider()

            // 操作按钮
            HStack {
                if viewModel.isProcessing {
                    Button("取消") {
                        onClose?()
                    }
                } else {
                    if viewModel.failedCount > 0 {
                        Button("重试失败操作") {
                            Task {
                                await viewModel.retryFailedOperations()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding()
        .frame(width: 400, height: viewModel.failedOperations.isEmpty ? 200 : 400)
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
}

/// 操作处理器进度视图模型
@MainActor
class OperationProcessorProgressViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var progress = 0.0
    @Published var processedCount = 0
    @Published var totalCount = 0
    @Published var successCount = 0
    @Published var failedCount = 0
    @Published var statusMessage = ""
    @Published var currentOperationType: String?
    @Published var failedOperations: [NoteOperation] = []

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // 立即更新一次
        updateStatus()

        // 启动定时器，每秒更新一次
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }

    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Status Update

    private func updateStatus() {
        Task {
            // 获取队列统计信息
            let stats = UnifiedOperationQueue.shared.getStatistics()

            totalCount = stats["pending", default: 0] +
                stats["processing", default: 0] +
                stats["failed", default: 0]

            processedCount = stats["completed", default: 0]
            successCount = stats["completed", default: 0]
            failedCount = stats["failed", default: 0] +
                stats["authFailed", default: 0] +
                stats["maxRetryExceeded", default: 0]

            // 检查是否正在处理
            let processor = await OperationProcessor.shared
            isProcessing = await processor.isProcessing

            // 获取当前操作
            if let currentOpId = await processor.currentOperation,
               let operation = UnifiedOperationQueue.shared.getOperation(currentOpId)
            {
                currentOperationType = operation.type.rawValue
            } else {
                currentOperationType = nil
            }

            // 计算进度
            if totalCount > 0 {
                progress = Double(processedCount) / Double(totalCount + processedCount)
            } else {
                progress = 0.0
            }

            // 更新状态消息
            if isProcessing {
                statusMessage = "正在处理操作..."
            } else if totalCount > 0 {
                statusMessage = "等待处理"
            } else {
                statusMessage = ""
            }

            // 获取失败的操作
            failedOperations = UnifiedOperationQueue.shared.getPendingOperations()
                .filter { $0.status == .failed || $0.status == .authFailed || $0.status == .maxRetryExceeded }
        }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // 监听操作完成通知
        NotificationCenter.default.publisher(for: NSNotification.Name("OperationCompleted"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatus()
                }
            }
            .store(in: &cancellables)

        // 监听队列处理完成通知
        NotificationCenter.default.publisher(for: NSNotification.Name("OperationQueueProcessingCompleted"))
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.updateStatus()

                    if let userInfo = notification.userInfo,
                       let successCount = userInfo["successCount"] as? Int,
                       let failureCount = userInfo["failureCount"] as? Int
                    {
                        self?.statusMessage = "处理完成: 成功 \(successCount), 失败 \(failureCount)"
                    }
                }
            }
            .store(in: &cancellables)

        // 监听认证失败通知
        NotificationCenter.default.publisher(for: NSNotification.Name("OperationAuthFailed"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatus()
                    self?.statusMessage = "认证失败，请重新登录"
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func retryFailedOperations() async {
        // 重置所有失败操作的状态
        for operation in failedOperations {
            try? UnifiedOperationQueue.shared.resetToPending(operation.id)
        }

        // 触发处理
        await OperationProcessor.shared.processQueue()

        // 更新状态
        updateStatus()
    }
}
