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

    // MARK: - Properties

    /// 自定义渲染器
    private let customRenderer: CustomRenderer

    /// 格式转换器
    private let formatConverter: XiaoMiFormatConverter

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

    /// EditorModule 使用的构造器
    init(customRenderer: CustomRenderer, formatConverter: XiaoMiFormatConverter) {
        self.customRenderer = customRenderer
        self.formatConverter = formatConverter
    }

    // MARK: - Public Methods

    /// 初始化原生编辑器
    /// - Returns: 初始化结果
    func initializeNativeEditor() -> EditorInitializationResult {
        LogService.shared.info(.editor, "开始初始化原生编辑器")

        // 1. 检查系统兼容性
        let compatibilityResult = checkSystemCompatibility()
        if !compatibilityResult.isCompatible {
            let error = NativeEditorError.systemVersionNotSupported(
                required: compatibilityResult.requiredVersion,
                current: compatibilityResult.macOSVersion
            )

            lastInitializationResult = .failure(error)
            return .failure(error)
        }

        // 2. 检查必需框架
        if !compatibilityResult.missingFrameworks.isEmpty {
            let error = NativeEditorError.frameworkNotAvailable(
                framework: compatibilityResult.missingFrameworks.joined(separator: ", ")
            )

            lastInitializationResult = .failure(error)
            return .failure(error)
        }

        // 3. 尝试创建编辑器上下文
        do {
            let context = try createEditorContext()

            LogService.shared.info(.editor, "原生编辑器初始化成功")

            lastInitializationResult = .success(context)
            return .success(context)
        } catch let error as NativeEditorError {
            lastInitializationResult = .failure(error)
            return .failure(error)
        } catch {
            let editorError = NativeEditorError.initializationFailed(reason: error.localizedDescription)

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

        LogService.shared.info(.editor, "系统兼容性检查完成: \(result.summary)")

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
        LogService.shared.info(.editor, "初始化状态已重置")
    }

    // MARK: - Private Methods

    /// 创建编辑器上下文
    private func createEditorContext() throws -> NativeEditorContext {
        // 预热渲染器缓存
        customRenderer.warmUpCache()

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
            _ = try formatConverter.xmlToNSAttributedString(testXML)
        } catch {
            throw NativeEditorError.initializationFailed(reason: "格式转换器验证失败: \(error.localizedDescription)")
        }

        // 验证渲染器
        let renderer = customRenderer
        _ = renderer.createCheckboxAttachment(checked: false, level: 3, indent: 1)
        _ = renderer.createHorizontalRuleAttachment()
        _ = renderer.createBulletAttachment(indent: 1)
        _ = renderer.createOrderAttachment(number: 1, indent: 1)

        LogService.shared.debug(.editor, "编辑器上下文验证通过")
    }
}

// MARK: - 编辑器恢复管理器

/// 编辑器恢复管理器
/// 处理编辑器崩溃后的数据恢复
@MainActor
final class EditorRecoveryManager {

    // MARK: - Singleton

    // MARK: - Properties

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

    init() {
        setupRecoveryDirectory()
    }

    // MARK: - Setup

    private func setupRecoveryDirectory() {
        guard let directory = recoveryDirectory else { return }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                LogService.shared.info(.editor, "恢复目录已创建: \(directory.path)")
            } catch {
                LogService.shared.error(.editor, "创建恢复目录失败: \(error.localizedDescription)")
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

        LogService.shared.info(.editor, "自动保存已启动，间隔: \(autoSaveInterval)秒")
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

            LogService.shared.debug(.editor, "恢复数据已保存: \(fileName)")
        } catch {
            LogService.shared.error(.editor, "保存恢复数据失败: \(error.localizedDescription)")
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

            LogService.shared.info(.editor, "数据已恢复: \(latestFile.lastPathComponent)")

            return content
        } catch {
            LogService.shared.error(.editor, "恢复数据失败: \(error.localizedDescription)")
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

            LogService.shared.info(.editor, "恢复数据已清除: \(noteId)")
        } catch {
            LogService.shared.error(.editor, "清除恢复数据失败: \(error.localizedDescription)")
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

                LogService.shared.debug(.editor, "已清理 \(filesToDelete.count) 个旧恢复文件")
            }
        } catch {
            LogService.shared.error(.editor, "清理旧恢复文件失败: \(error.localizedDescription)")
        }
    }
}
