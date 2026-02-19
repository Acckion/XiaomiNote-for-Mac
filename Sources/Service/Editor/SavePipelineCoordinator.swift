//
//  SavePipelineCoordinator.swift
//  MiNoteMac
//
//  保存流程协调器
//  负责协调内容处理和保存操作的完整流程
//

import Foundation

/// 保存流程协调器
@MainActor
public final class SavePipelineCoordinator: ObservableObject {

    // MARK: - 依赖服务

    /// 当前保存状态
    @Published public private(set) var currentState: SavePipelineState = .notStarted

    /// 当前执行步骤
    @Published public private(set) var currentStep: SaveStep?

    /// 保存进度（0.0 - 1.0）
    @Published public private(set) var progress = 0.0

    /// 最后的错误信息
    @Published public private(set) var lastError: TitleIntegrationError?

    /// 保存开始时间
    private var saveStartTime: Date?

    /// 保存超时时间（秒）
    private let saveTimeout: TimeInterval = 30.0

    /// 取消标记
    private var isCancelled = false

    // MARK: - 初始化

    /// 初始化保存流程协调器
    public init() {}

    // MARK: - 公共接口

    /// 执行完整的保存流程
    ///
    /// 按照正确的顺序执行保存操作：
    /// 1. 开始保存 -> 2. 构建笔记对象 -> 3. 调用 API -> 4. 更新状态 -> 5. 完成保存
    ///
    /// - Parameters:
    ///   - xmlContent: 编辑器的 XML 内容
    ///   - noteId: 笔记 ID
    ///   - apiSaveHandler: API 保存处理器
    /// - Returns: 保存结果
    ///
    public func executeSavePipeline(
        xmlContent: String,
        noteId: String,
        apiSaveHandler: @escaping (String, String, String) async throws -> Void
    ) async throws -> SavePipelineResult {

        // 重置状态
        await resetPipelineState()

        do {
            // 步骤 1: 开始保存
            try await executeStep(.startSave) {
                LogService.shared.info(.editor, "开始保存流程，笔记 ID: \(noteId)")
                self.saveStartTime = Date()
                self.updateState(.preparing)
            }

            // 步骤 2: 构建笔记对象（标题从数据库读取，不再从 XML/编辑器提取）
            let finalContent: String = try await executeStep(.buildNote) {
                LogService.shared.debug(.editor, "构建笔记对象...")
                return xmlContent
            }

            // 更新状态为执行中
            updateState(.executing)

            // 步骤 3: 调用 API
            try await executeStep(.callAPI) {
                LogService.shared.debug(.editor, "调用保存 API...")
                // 标题由 apiSaveHandler 内部从数据库获取
                try await apiSaveHandler(noteId, "", finalContent)
            }

            // 步骤 4: 更新状态
            try await executeStep(.updateState) {
                LogService.shared.debug(.editor, "更新本地状态...")
            }

            // 步骤 5: 完成保存
            try await executeStep(.completeSave) {
                LogService.shared.debug(.editor, "保存流程完成")
                self.updateState(.completed)
            }

            // 构建保存结果
            let result = SavePipelineResult(
                processedContent: finalContent,
                executionTime: Date().timeIntervalSince(saveStartTime ?? Date()),
                stepsExecuted: [.startSave, .buildNote, .callAPI, .updateState, .completeSave]
            )

            LogService.shared.info(.editor, "保存流程完成，耗时: \(String(format: "%.2f", result.executionTime))秒")
            return result
        } catch {
            // 处理错误
            let titleError = TitleIntegrationError.wrap(error)
            await handlePipelineError(titleError)
            throw titleError
        }
    }

    /// 取消保存流程
    ///
    public func cancelSavePipeline() {
        LogService.shared.info(.editor, "取消保存流程")
        isCancelled = true
        updateState(.cancelled)
        lastError = .saveCancelled
    }

    /// 重置流程状态
    ///
    /// 将协调器重置为初始状态，准备执行新的保存操作
    public func resetPipelineState() async {
        currentState = .notStarted
        currentStep = nil
        progress = 0.0
        lastError = nil
        saveStartTime = nil
        isCancelled = false
    }

    // MARK: - 私有方法

    /// 执行单个保存步骤
    ///
    /// 提供统一的步骤执行框架，包含错误处理、超时检查和进度更新
    ///
    /// - Parameters:
    ///   - step: 要执行的步骤
    ///   - operation: 步骤的具体操作
    /// - Returns: 操作的返回值
    private func executeStep<T>(_ step: SaveStep, operation: () async throws -> T) async throws -> T {
        // 检查是否已取消
        guard !isCancelled else {
            throw TitleIntegrationError.saveCancelled
        }

        // 检查超时
        if let startTime = saveStartTime,
           Date().timeIntervalSince(startTime) > saveTimeout
        {
            throw TitleIntegrationError.saveTimeout(saveTimeout)
        }

        // 更新当前步骤
        currentStep = step

        // 更新进度
        let stepProgress = Double(step.order) / Double(SaveStep.allCases.count)
        progress = stepProgress

        LogService.shared.debug(.editor, "执行步骤: \(step.displayName) (\(Int(stepProgress * 100))%)")

        do {
            return try await operation()
        } catch {
            LogService.shared.error(.editor, "步骤失败: \(step.displayName) - \(error)")
            throw TitleIntegrationError.saveStepFailed(step, reason: error.localizedDescription)
        }
    }

    /// 更新保存状态
    ///
    /// - Parameter newState: 新的保存状态
    private func updateState(_ newState: SavePipelineState) {
        currentState = newState
    }

    /// 处理流程错误
    ///
    /// - Parameter error: 发生的错误
    private func handlePipelineError(_ error: TitleIntegrationError) async {
        lastError = error
        updateState(.failed)

        LogService.shared.error(.editor, "保存流程错误: \(error.errorDescription ?? error.localizedDescription)")

        if let suggestion = error.recoverySuggestion {
            LogService.shared.debug(.editor, "恢复建议: \(suggestion)")
        }
    }
}

// MARK: - 保存流程结果

/// 保存流程结果
public struct SavePipelineResult {
    /// 处理后的内容
    public let processedContent: String

    /// 执行时间（秒）
    public let executionTime: TimeInterval

    /// 已执行的步骤列表
    public let stepsExecuted: [SaveStep]

    public init(
        processedContent: String,
        executionTime: TimeInterval,
        stepsExecuted: [SaveStep]
    ) {
        self.processedContent = processedContent
        self.executionTime = executionTime
        self.stepsExecuted = stepsExecuted
    }
}

// MARK: - 扩展：CustomStringConvertible

extension SavePipelineResult: CustomStringConvertible {
    public var description: String {
        "SavePipelineResult(耗时: \(String(format: "%.2f", executionTime))秒, 步骤: \(stepsExecuted.count))"
    }
}

// MARK: - 扩展：便利方法

public extension SavePipelineCoordinator {
    /// 获取当前进度百分比
    var progressPercentage: Int {
        Int(progress * 100)
    }

    /// 是否正在执行保存
    var isSaving: Bool {
        currentState == .preparing || currentState == .executing
    }

    /// 是否已完成（成功或失败）
    var isCompleted: Bool {
        currentState.isTerminal
    }

    /// 获取执行时间
    var elapsedTime: TimeInterval {
        guard let startTime = saveStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}
