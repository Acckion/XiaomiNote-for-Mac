//
//  EditorChangeTracker.swift
//  MiNoteMac
//
//  编辑器变化追踪器 - 使用版本号机制追踪内容变化
//

import Foundation

/// 编辑器变化追踪器
///
/// 使用版本号机制追踪内容变化，避免内容比较的性能开销和误判问题
///
/// **核心思想**：
/// - 不比较内容差异，而是追踪用户操作
/// - 每次用户编辑时递增版本号
/// - 通过版本号差异判断是否需要保存
///
/// **优势**：
/// 1. 简单直观：一个整数表示状态
/// 2. 性能优越：O(1) 时间复杂度
/// 3. 准确追踪：只追踪用户操作，不受格式化影响
/// 4. 避免误判：程序化修改不增加版本号
/// 5. 支持并发：可以检测保存期间的新编辑
///
/// **使用示例**：
/// ```swift
/// let tracker = EditorChangeTracker()
///
/// // 用户编辑
/// tracker.textDidChange()  // 版本号 0 -> 1
///
/// // 检查是否需要保存
/// if tracker.needsSave {
///     // 执行保存
///     await saveToServer()
///     tracker.didSaveSuccessfully()
/// }
///
/// // 加载笔记（不触发版本号变化）
/// tracker.performProgrammaticChange {
///     loadContent()
/// }
/// ```
///
@MainActor
public class EditorChangeTracker: ObservableObject {
    // MARK: - 版本号

    /// 当前内容版本号
    ///
    /// 每次用户编辑时递增，用于追踪内容变化
    ///
    @Published private(set) var contentVersion = 0

    /// 最后保存的版本号
    ///
    /// 保存成功后更新为 contentVersion，用于判断是否需要保存
    ///
    private var lastSavedVersion = 0

    // MARK: - 状态标记

    /// 是否是程序化修改
    ///
    /// 程序化修改（如加载笔记）不会增加版本号
    ///
    private var isProgrammaticChange = false

    /// 是否正在进行程序化修改（公开只读）
    ///
    /// 用于外部检查当前是否在程序化修改中
    ///
    public var isInProgrammaticChange: Bool {
        isProgrammaticChange
    }

    /// 是否有用户编辑
    ///
    /// 用于区分用户编辑和程序化修改
    ///
    private var hasUserEdits = false

    // MARK: - 计算属性

    /// 是否需要保存
    ///
    /// 当内容版本号大于最后保存版本号，且有用户编辑时返回 true
    ///
    public var needsSave: Bool {
        contentVersion > lastSavedVersion && hasUserEdits
    }

    /// 版本号差异
    ///
    /// 返回当前版本号与最后保存版本号的差值
    public var versionDelta: Int {
        contentVersion - lastSavedVersion
    }

    // MARK: - 初始化

    public init() {}

    // MARK: - 编辑追踪

    /// 文本内容变化
    ///
    /// 当用户输入、删除或粘贴文本时调用
    ///
    public func textDidChange() {
        guard !isProgrammaticChange else {
            return
        }

        contentVersion += 1
        hasUserEdits = true

    }

    /// 格式变化
    ///
    /// 当用户应用或移除格式时调用
    ///
    public func formatDidChange() {
        guard !isProgrammaticChange else {
            return
        }

        contentVersion += 1
        hasUserEdits = true

    }

    /// 附件变化
    ///
    /// 当用户插入或删除附件（图片、音频等）时调用
    ///
    public func attachmentDidChange() {
        guard !isProgrammaticChange else {
            return
        }

        contentVersion += 1
        hasUserEdits = true

    }

    // MARK: - 程序化修改

    /// 执行程序化修改
    ///
    /// 在闭包内的所有修改都不会增加版本号
    /// 用于加载笔记、同步内容等场景
    ///
    /// **使用示例**：
    /// ```swift
    /// tracker.performProgrammaticChange {
    ///     loadFromXML(xml)
    /// }
    /// ```
    ///
    public func performProgrammaticChange(_ block: () -> Void) {
        let wasProgrammaticChange = isProgrammaticChange
        isProgrammaticChange = true
        defer { isProgrammaticChange = wasProgrammaticChange }

        block()
    }

    /// 异步执行程序化修改
    ///
    /// 异步版本的 performProgrammaticChange
    ///
    public func performProgrammaticChange(_ block: @escaping () async -> Void) async {
        let wasProgrammaticChange = isProgrammaticChange
        isProgrammaticChange = true
        defer { isProgrammaticChange = wasProgrammaticChange }

        await block()
    }

    // MARK: - 保存管理

    /// 保存成功
    ///
    /// 同步版本号，重置编辑标记
    ///
    public func didSaveSuccessfully() {
        lastSavedVersion = contentVersion
        hasUserEdits = false

    }

    /// 保存失败
    ///
    /// 版本号保持不变，保留编辑标记
    ///
    public func didSaveFail() {}

    /// 检查是否有新编辑（在保存期间）
    ///
    /// 用于检测保存操作期间用户是否继续编辑
    ///
    /// - Parameter savingVersion: 正在保存的版本号
    /// - Returns: 是否有新编辑
    ///
    public func hasNewEditsSince(savingVersion: Int) -> Bool {
        let hasNew = contentVersion > savingVersion
        if hasNew {}
        return hasNew
    }

    /// 重置追踪器
    ///
    /// 用于切换笔记或清空编辑器
    ///
    public func reset() {
        contentVersion = 0
        lastSavedVersion = 0
        hasUserEdits = false
        isProgrammaticChange = false

    }

    // MARK: - 调试信息

    /// 获取调试信息
    ///
    /// 返回当前追踪器的完整状态信息
    ///
    /// - Returns: 格式化的调试信息字符串
    public func getDebugInfo() -> String {
        """
        EditorChangeTracker 状态:
        - contentVersion: \(contentVersion)
        - lastSavedVersion: \(lastSavedVersion)
        - versionDelta: \(versionDelta)
        - needsSave: \(needsSave)
        - hasUserEdits: \(hasUserEdits)
        - isProgrammaticChange: \(isProgrammaticChange)
        """
    }

    /// 打印调试信息
    public func printDebugInfo() {}
}
