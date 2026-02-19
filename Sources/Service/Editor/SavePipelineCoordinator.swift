//
//  SavePipelineCoordinator.swift
//  MiNoteMac
//
//  保存流程协调器
//  负责协调标题提取、内容处理和保存操作的完整流程
//
//  Created by Title Content Integration Fix
//

import AppKit
import Foundation

/// 保存流程协调器
///
/// 核心职责：
/// 1. 协调完整的保存流程，确保正确的执行顺序
/// 2. 在移除标题标签之前提取标题
/// 3. 管理保存状态和错误处理
/// 4. 提供详细的日志记录和调试信息
///
/// 设计原则：
/// - 确保标题提取在标签移除之前执行
/// - 提供完善的错误处理和恢复机制
/// - 维护保存流程的状态一致性
/// - 支持异步操作和取消机制
///
/// _需求: 1.2, 3.1, 3.2_ - 实现完整的保存流程方法和状态管理
@MainActor
public final class SavePipelineCoordinator: ObservableObject {

    // MARK: - 依赖服务

    /// 标题提取服务
    private let titleExtractionService: TitleExtractionService

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
    /// - Parameter titleExtractionService: 标题提取服务实例
    public init(titleExtractionService: TitleExtractionService = .shared) {
        self.titleExtractionService = titleExtractionService
    }

    // MARK: - 公共接口

    /// 执行完整的保存流程
    ///
    /// 按照正确的顺序执行保存操作：
    /// 1. 开始保存 -> 2. 提取标题 -> 3. 验证标题 -> 4. 移除标题标签
    /// -> 5. 构建笔记对象 -> 6. 调用 API -> 7. 更新状态 -> 8. 完成保存
    ///
    /// - Parameters:
    ///   - xmlContent: 编辑器的 XML 内容
    ///   - textStorage: 原生编辑器的文本存储（可选）
    ///   - noteId: 笔记 ID
    ///   - apiSaveHandler: API 保存处理器
    /// - Returns: 保存结果，包含提取的标题和处理后的内容
    ///
    /// _需求: 1.2, 3.1_ - 确保正确的执行顺序
    public func executeSavePipeline(
        xmlContent: String,
        textStorage: NSTextStorage? = nil,
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

            // 步骤 2: 提取标题
            let titleResult = try await executeStep(.extractTitle) {
                LogService.shared.debug(.editor, "提取标题...")

                // 优先从原生编辑器提取标题
                if let textStorage {
                    return self.titleExtractionService.extractTitleFromEditor(textStorage)
                } else {
                    return self.titleExtractionService.extractTitleFromXML(xmlContent)
                }
            }

            // 步骤 3: 验证标题
            try await executeStep(.validateTitle) {
                LogService.shared.debug(.editor, "验证标题: '\(titleResult.title)'")

                let validation = self.titleExtractionService.validateTitle(titleResult.title)
                if !validation.isValid {
                    throw TitleIntegrationError.titleValidation(validation.error ?? "标题验证失败")
                }
            }

            // 步骤 4: 移除标题标签
            let processedContent = try await executeStep(.removeTitleTag) {
                LogService.shared.debug(.editor, "移除标题标签...")
                return self.removeTitleTagFromXML(xmlContent)
            }

            // 步骤 5: 构建笔记对象
            let (finalTitle, finalContent) = try await executeStep(.buildNote) {
                LogService.shared.debug(.editor, "构建笔记对象...")

                // 使用提取的标题，如果提取失败则使用后备方案
                let title = titleResult.isValid && !titleResult.title.isEmpty
                    ? titleResult.title
                    : self.extractFallbackTitle(from: processedContent)

                return (title, processedContent)
            }

            // 更新状态为执行中
            updateState(.executing)

            // 步骤 6: 调用 API
            try await executeStep(.callAPI) {
                LogService.shared.debug(.editor, "调用保存 API...")
                try await apiSaveHandler(noteId, finalTitle, finalContent)
            }

            // 步骤 7: 更新状态
            try await executeStep(.updateState) {
                LogService.shared.debug(.editor, "更新本地状态...")
                // 这里可以添加本地状态更新逻辑
            }

            // 步骤 8: 完成保存
            try await executeStep(.completeSave) {
                LogService.shared.debug(.editor, "保存流程完成")
                self.updateState(.completed)
            }

            // 构建保存结果
            let result = SavePipelineResult(
                extractedTitle: finalTitle,
                processedContent: finalContent,
                titleSource: titleResult.source,
                executionTime: Date().timeIntervalSince(saveStartTime ?? Date()),
                stepsExecuted: SaveStep.allCases.prefix(8).map(\.self)
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
    /// _需求: 3.3_ - 支持保存流程的取消操作
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

    /// 从 XML 内容中移除标题标签
    ///
    /// - Parameter xmlContent: 原始 XML 内容
    /// - Returns: 移除标题标签后的 XML 内容
    private func removeTitleTagFromXML(_ xmlContent: String) -> String {
        var result = xmlContent

        // 查找并移除 <title>...</title> 标签
        let titlePattern = "<title>.*?</title>"
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: .dotMatchesLineSeparators) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // 清理多余的空白行
        result = result.replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// 提取后备标题
    ///
    /// 当主要标题提取失败时，从内容中提取第一行作为标题
    ///
    /// - Parameter content: 内容文本
    /// - Returns: 后备标题
    private func extractFallbackTitle(from content: String) -> String {
        // 从内容的第一行提取标题
        let lines = content.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 限制标题长度
        let maxLength = 50
        if firstLine.count > maxLength {
            return String(firstLine.prefix(maxLength)) + "..."
        }

        return firstLine.isEmpty ? "无标题" : firstLine
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
///
/// 包含保存操作的完整结果信息
public struct SavePipelineResult {
    /// 提取的标题
    public let extractedTitle: String

    /// 处理后的内容
    public let processedContent: String

    /// 标题来源
    public let titleSource: TitleSource

    /// 执行时间（秒）
    public let executionTime: TimeInterval

    /// 已执行的步骤列表
    public let stepsExecuted: [SaveStep]

    /// 初始化方法
    public init(
        extractedTitle: String,
        processedContent: String,
        titleSource: TitleSource,
        executionTime: TimeInterval,
        stepsExecuted: [SaveStep]
    ) {
        self.extractedTitle = extractedTitle
        self.processedContent = processedContent
        self.titleSource = titleSource
        self.executionTime = executionTime
        self.stepsExecuted = stepsExecuted
    }
}

// MARK: - 扩展：CustomStringConvertible

extension SavePipelineResult: CustomStringConvertible {
    public var description: String {
        "SavePipelineResult(标题: '\(extractedTitle)', 来源: \(titleSource.displayName), 耗时: \(String(format: "%.2f", executionTime))秒, 步骤: \(stepsExecuted.count))"
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
