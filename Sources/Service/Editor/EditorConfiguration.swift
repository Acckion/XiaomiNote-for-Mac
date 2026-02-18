//
//  EditorConfiguration.swift
//  MiNoteMac
//
//  编辑器配置模型 - 定义编辑器的配置选项和设置
//

import Foundation

/// 编辑器配置
struct EditorConfiguration: Codable, Equatable {

    // MARK: - Properties

    /// 是否启用自动保存
    var autoSaveEnabled: Bool

    /// 自动保存间隔（秒）
    var autoSaveInterval: TimeInterval

    /// 是否启用拼写检查
    var spellCheckEnabled: Bool

    /// 是否启用语法高亮
    var syntaxHighlightEnabled: Bool

    /// 字体大小
    var fontSize: CGFloat

    /// 字体名称
    var fontName: String

    /// 行间距
    var lineSpacing: CGFloat

    /// 是否启用暗色模式适配
    var darkModeEnabled: Bool

    /// 是否显示行号
    var showLineNumbers: Bool

    /// 是否启用代码折叠
    var codeFoldingEnabled: Bool

    /// 缩进大小
    var indentSize: Int

    /// 是否使用制表符缩进
    var useTabsForIndentation: Bool

    // MARK: - Initialization

    /// 初始化编辑器配置
    init() {
        // 设置默认值（原生编辑器）
        autoSaveEnabled = true
        autoSaveInterval = 5.0
        spellCheckEnabled = true
        syntaxHighlightEnabled = true
        fontSize = 14.0
        fontName = "SF Pro Text"
        lineSpacing = 1.2
        darkModeEnabled = true
        showLineNumbers = false
        codeFoldingEnabled = false
        indentSize = 4
        useTabsForIndentation = false
    }

    // MARK: - Static Methods

    /// 获取默认配置
    /// - Returns: 默认配置
    static func defaultConfiguration() -> EditorConfiguration {
        EditorConfiguration()
    }
}

/// 编辑器配置管理器
@MainActor
class EditorConfigurationManager: ObservableObject {

    // MARK: - Singleton

    static let shared = EditorConfigurationManager()

    // MARK: - Published Properties

    /// 当前配置
    @Published var currentConfiguration: EditorConfiguration

    // MARK: - Private Properties

    private let userDefaults: UserDefaults
    private let configurationKey = "editorConfiguration"

    // MARK: - Initialization

    /// 初始化配置管理器
    /// - Parameter userDefaults: UserDefaults 实例
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // 加载保存的配置
        if let data = userDefaults.data(forKey: configurationKey),
           let configuration = try? JSONDecoder().decode(EditorConfiguration.self, from: data)
        {
            currentConfiguration = configuration
        } else {
            // 使用默认配置
            currentConfiguration = EditorConfiguration.defaultConfiguration()
        }
    }

    // MARK: - Public Methods

    /// 更新配置
    /// - Parameter configuration: 新的配置
    func updateConfiguration(_ configuration: EditorConfiguration) {
        currentConfiguration = configuration
        saveConfiguration()
    }

    /// 重置为默认配置
    func resetToDefault() {
        let defaultConfig = EditorConfiguration.defaultConfiguration()
        updateConfiguration(defaultConfig)
    }

    /// 更新字体设置
    /// - Parameters:
    ///   - name: 字体名称
    ///   - size: 字体大小
    func updateFont(name: String, size: CGFloat) {
        var config = currentConfiguration
        config.fontName = name
        config.fontSize = size
        updateConfiguration(config)
    }

    /// 更新自动保存设置
    /// - Parameters:
    ///   - enabled: 是否启用
    ///   - interval: 保存间隔
    func updateAutoSave(enabled: Bool, interval: TimeInterval) {
        var config = currentConfiguration
        config.autoSaveEnabled = enabled
        config.autoSaveInterval = interval
        updateConfiguration(config)
    }

    /// 切换拼写检查
    func toggleSpellCheck() {
        var config = currentConfiguration
        config.spellCheckEnabled.toggle()
        updateConfiguration(config)
    }

    /// 切换语法高亮
    func toggleSyntaxHighlight() {
        var config = currentConfiguration
        config.syntaxHighlightEnabled.toggle()
        updateConfiguration(config)
    }

    /// 切换暗色模式适配
    func toggleDarkMode() {
        var config = currentConfiguration
        config.darkModeEnabled.toggle()
        updateConfiguration(config)
    }

    // MARK: - Private Methods

    /// 保存配置到 UserDefaults
    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(currentConfiguration) {
            userDefaults.set(data, forKey: configurationKey)
        }
    }
}

/// UserDefaults 扩展 - 编辑器配置相关
extension UserDefaults {

    /// 编辑器配置
    var editorConfiguration: EditorConfiguration? {
        get {
            guard let data = data(forKey: "editorConfiguration") else { return nil }
            return try? JSONDecoder().decode(EditorConfiguration.self, from: data)
        }
        set {
            if let configuration = newValue,
               let data = try? JSONEncoder().encode(configuration)
            {
                set(data, forKey: "editorConfiguration")
            } else {
                removeObject(forKey: "editorConfiguration")
            }
        }
    }
}
