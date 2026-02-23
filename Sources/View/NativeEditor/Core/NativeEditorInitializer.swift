//
//  NativeEditorInitializer.swift
//  MiNoteMac
//
//  原生编辑器初始化器 - 处理编辑器初始化和系统兼容性检查

import AppKit
import Foundation

// MARK: - 初始化结果

/// 编辑器初始化结果
enum EditorInitializationResult {
    case success(NativeEditorContext)
    case failure(NativeEditorError)
}

// MARK: - 系统兼容性检查结果

/// 系统兼容性检查结果
struct SystemCompatibilityResult {
    let isCompatible: Bool
    let macOSVersion: String
    let requiredVersion: String
    let missingFrameworks: [String]
    let warnings: [String]

    var summary: String {
        if isCompatible {
            return "系统兼容性检查通过 (macOS \(macOSVersion))"
        } else {
            var message = "系统兼容性检查失败"
            if !missingFrameworks.isEmpty {
                message += "\n缺少框架: \(missingFrameworks.joined(separator: ", "))"
            }
            message += "\n需要 macOS \(requiredVersion)，当前 \(macOSVersion)"
            return message
        }
    }
}

// MARK: - 原生编辑器初始化器

/// 原生编辑器初始化器
/// 负责编辑器的安全初始化和系统兼容性检查
@MainActor
final class NativeEditorInitializer {

    // MARK: - Singleton

    static let shared = NativeEditorInitializer()

    // MARK: - Properties

    /// 日志记录器
    private let logger = NativeEditorLogger.shared

    /// 错误处理器
    private let errorHandler = NativeEditorErrorHandler.shared

    /// 性能指标
    private let metrics = NativeEditorMetrics.shared

    /// 最低支持的 macOS 版本
    private let minimumMacOSVersion = "15.0"

    /// 必需的框架
    private let requiredFrameworks = [
        "AppKit",
        "SwiftUI",
        "Combine",
    ]

    /// 上次初始化结果缓存
    private var lastInitializationResult: EditorInitializationResult?

    /// 系统兼容性缓存
    private var cachedCompatibilityResult: SystemCompatibilityResult?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 初始化原生编辑器
    /// - Returns: 初始化结果
    func initializeNativeEditor() -> EditorInitializationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.logInfo("开始初始化原生编辑器", category: "Initialization")

        // 1. 检查系统兼容性
        let compatibilityResult = checkSystemCompatibility()
        if !compatibilityResult.isCompatible {
            let error = NativeEditorError.systemVersionNotSupported(
                required: compatibilityResult.requiredVersion,
                current: compatibilityResult.macOSVersion
            )

            errorHandler.handleError(error, context: "系统兼容性检查")

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordInitialization("nativeEditor", duration: duration)

            lastInitializationResult = .failure(error)
            return .failure(error)
        }

        // 2. 检查必需框架
        if !compatibilityResult.missingFrameworks.isEmpty {
            let error = NativeEditorError.frameworkNotAvailable(
                framework: compatibilityResult.missingFrameworks.joined(separator: ", ")
            )

            errorHandler.handleError(error, context: "框架检查")

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordInitialization("nativeEditor", duration: duration)

            lastInitializationResult = .failure(error)
            return .failure(error)
        }

        // 3. 尝试创建编辑器上下文
        do {
            let context = try createEditorContext()

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordInitialization("nativeEditor", duration: duration)
            logger.logInfo("原生编辑器初始化成功，耗时: \(String(format: "%.2f", duration * 1000))ms", category: "Initialization")

            // 检查初始化时间是否超过阈值
            if duration > 0.1 { // 100ms
                logger.logWarning("初始化时间超过阈值: \(String(format: "%.2f", duration * 1000))ms", category: "Initialization")
            }

            lastInitializationResult = .success(context)
            return .success(context)
        } catch let error as NativeEditorError {
            errorHandler.handleError(error, context: "创建编辑器上下文")

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordInitialization("nativeEditor", duration: duration)

            lastInitializationResult = .failure(error)
            return .failure(error)
        } catch {
            let editorError = NativeEditorError.initializationFailed(reason: error.localizedDescription)
            errorHandler.handleError(editorError, context: "创建编辑器上下文")

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metrics.recordInitialization("nativeEditor", duration: duration)

            lastInitializationResult = .failure(editorError)
            return .failure(editorError)
        }
    }

    /// 检查系统兼容性
    /// - Returns: 兼容性检查结果
    func checkSystemCompatibility() -> SystemCompatibilityResult {
        // 使用缓存
        if let cached = cachedCompatibilityResult {
            return cached
        }

        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        let versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // macOS 15.0+ 始终满足版本要求
        let isVersionCompatible = true

        // 检查必需框架
        var missingFrameworks: [String] = []

        // 检查 NSTextView 可用性
        if NSClassFromString("NSTextView") == nil {
            missingFrameworks.append("AppKit.NSTextView")
        }

        // 检查 NSTextAttachment 可用性
        if NSClassFromString("NSTextAttachment") == nil {
            missingFrameworks.append("AppKit.NSTextAttachment")
        }

        // 检查 NSLayoutManager 可用性
        if NSClassFromString("NSLayoutManager") == nil {
            missingFrameworks.append("AppKit.NSLayoutManager")
        }

        // 收集警告
        var warnings: [String] = []

        // 检查内存
        let physicalMemory = processInfo.physicalMemory
        if physicalMemory < 4 * 1024 * 1024 * 1024 { // 4GB
            warnings.append("系统内存较低，可能影响编辑器性能")
        }

        // 检查处理器
        let processorCount = processInfo.processorCount
        if processorCount < 2 {
            warnings.append("处理器核心数较少，可能影响编辑器响应速度")
        }

        let result = SystemCompatibilityResult(
            isCompatible: isVersionCompatible && missingFrameworks.isEmpty,
            macOSVersion: versionString,
            requiredVersion: minimumMacOSVersion,
            missingFrameworks: missingFrameworks,
            warnings: warnings
        )

        cachedCompatibilityResult = result

        logger.logInfo("系统兼容性检查完成: \(result.summary)", category: "Initialization")

        return result
    }

    /// 检查是否支持原生编辑器
    /// - Returns: 是否支持
    func isNativeEditorSupported() -> Bool {
        checkSystemCompatibility().isCompatible
    }

    /// 获取不支持原因
    /// - Returns: 不支持的原因，如果支持则返回 nil
    func getUnsupportedReason() -> String? {
        let result = checkSystemCompatibility()
        if result.isCompatible {
            return nil
        }
        return result.summary
    }

    /// 重置初始化状态
    func resetInitializationState() {
        lastInitializationResult = nil
        cachedCompatibilityResult = nil
        errorHandler.resetErrorCount()
        logger.logInfo("初始化状态已重置", category: "Initialization")
    }

    // MARK: - Private Methods

    /// 创建编辑器上下文
    private func createEditorContext() throws -> NativeEditorContext {
        // 预热渲染器缓存
        CustomRenderer.shared.warmUpCache()

        // 创建上下文
        let context = NativeEditorContext()

        // 验证上下文
        try validateEditorContext(context)

        return context
    }

    /// 验证编辑器上下文
    private func validateEditorContext(_: NativeEditorContext) throws {
        // 验证格式转换器
        let testXML = "<text indent=\"1\">测试</text>"
        do {
            _ = try XiaoMiFormatConverter.shared.xmlToNSAttributedString(testXML)
        } catch {
            throw NativeEditorError.initializationFailed(reason: "格式转换器验证失败: \(error.localizedDescription)")
        }

        // 验证渲染器
        let renderer = CustomRenderer.shared
        _ = renderer.createCheckboxAttachment(checked: false, level: 3, indent: 1)
        _ = renderer.createHorizontalRuleAttachment()
        _ = renderer.createBulletAttachment(indent: 1)
        _ = renderer.createOrderAttachment(number: 1, indent: 1)

        logger.logDebug("编辑器上下文验证通过", category: "Initialization")
    }
}

// MARK: - 编辑器恢复管理器

/// 编辑器恢复管理器
/// 处理编辑器崩溃后的数据恢复
@MainActor
final class EditorRecoveryManager {

    // MARK: - Singleton

    static let shared = EditorRecoveryManager()

    // MARK: - Properties

    /// 日志记录器
    private let logger = NativeEditorLogger.shared

    /// 自动保存间隔（秒）
    var autoSaveInterval: TimeInterval = 30

    /// 最大恢复文件数
    private let maxRecoveryFiles = 10

    /// 恢复文件目录
    private var recoveryDirectory: URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("MiNoteMac/Recovery", isDirectory: true)
    }

    /// 自动保存定时器
    private var autoSaveTimer: Timer?

    /// 当前编辑内容
    private var currentContent: NSAttributedString?

    /// 当前笔记 ID
    private var currentNoteId: String?

    // MARK: - Initialization

    private init() {
        setupRecoveryDirectory()
    }

    // MARK: - Setup

    private func setupRecoveryDirectory() {
        guard let directory = recoveryDirectory else { return }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                logger.logInfo("恢复目录已创建: \(directory.path)", category: "Recovery")
            } catch {
                logger.logError(error, context: "创建恢复目录失败", category: "Recovery")
            }
        }
    }

    // MARK: - Auto Save

    /// 开始自动保存
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - contentProvider: 内容提供者
    func startAutoSave(noteId: String, contentProvider: @escaping () -> NSAttributedString?) {
        currentNoteId = noteId

        stopAutoSave()

        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let content = contentProvider() {
                    self?.saveRecoveryData(content, noteId: noteId)
                }
            }
        }

        logger.logInfo("自动保存已启动，间隔: \(autoSaveInterval)秒", category: "Recovery")
    }

    /// 停止自动保存
    func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// 保存恢复数据
    /// - Parameters:
    ///   - content: 内容
    ///   - noteId: 笔记 ID
    func saveRecoveryData(_ content: NSAttributedString, noteId: String) {
        guard let directory = recoveryDirectory else { return }

        let fileName = "recovery_\(noteId)_\(Date().timeIntervalSince1970).rtfd"
        let fileURL = directory.appendingPathComponent(fileName)

        do {
            let data = try content.data(
                from: NSRange(location: 0, length: content.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            try data.write(to: fileURL)

            currentContent = content

            // 清理旧的恢复文件
            cleanupOldRecoveryFiles(noteId: noteId)

            logger.logDebug("恢复数据已保存: \(fileName)", category: "Recovery")
        } catch {
            logger.logError(error, context: "保存恢复数据失败", category: "Recovery")
        }
    }

    /// 恢复数据
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 恢复的内容
    func recoverData(noteId: String) -> NSAttributedString? {
        guard let directory = recoveryDirectory else { return nil }

        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])

            // 查找该笔记的最新恢复文件
            let recoveryFiles = files
                .filter { $0.lastPathComponent.hasPrefix("recovery_\(noteId)_") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }

            guard let latestFile = recoveryFiles.first else {
                return nil
            }

            let data = try Data(contentsOf: latestFile)
            let content = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )

            logger.logInfo("数据已恢复: \(latestFile.lastPathComponent)", category: "Recovery")

            return content
        } catch {
            logger.logError(error, context: "恢复数据失败", category: "Recovery")
            return nil
        }
    }

    /// 检查是否有可恢复的数据
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否有可恢复的数据
    func hasRecoverableData(noteId: String) -> Bool {
        guard let directory = recoveryDirectory else { return false }

        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            return files.contains { $0.lastPathComponent.hasPrefix("recovery_\(noteId)_") }
        } catch {
            return false
        }
    }

    /// 清除恢复数据
    /// - Parameter noteId: 笔记 ID
    func clearRecoveryData(noteId: String) {
        guard let directory = recoveryDirectory else { return }

        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let recoveryFiles = files.filter { $0.lastPathComponent.hasPrefix("recovery_\(noteId)_") }

            for file in recoveryFiles {
                try fileManager.removeItem(at: file)
            }

            logger.logInfo("恢复数据已清除: \(noteId)", category: "Recovery")
        } catch {
            logger.logError(error, context: "清除恢复数据失败", category: "Recovery")
        }
    }

    // MARK: - Private Methods

    /// 清理旧的恢复文件
    private func cleanupOldRecoveryFiles(noteId: String) {
        guard let directory = recoveryDirectory else { return }

        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])

            let recoveryFiles = files
                .filter { $0.lastPathComponent.hasPrefix("recovery_\(noteId)_") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }

            // 保留最新的几个文件
            if recoveryFiles.count > maxRecoveryFiles {
                let filesToDelete = recoveryFiles.suffix(from: maxRecoveryFiles)
                for file in filesToDelete {
                    try fileManager.removeItem(at: file)
                }

                logger.logDebug("已清理 \(filesToDelete.count) 个旧恢复文件", category: "Recovery")
            }
        } catch {
            logger.logError(error, context: "清理旧恢复文件失败", category: "Recovery")
        }
    }
}
