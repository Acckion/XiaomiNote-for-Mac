import Foundation

/// 窗口状态管理器，负责保存和恢复窗口状态
public class WindowStateManager {

    // MARK: - Initialization

    public init() {}

    // MARK: - Type Aliases

    // 这些类型别名确保我们可以引用状态类
    // 注意：实际类型在 MiNoteLibrary 模块中定义

    // MARK: - Properties

    private let userDefaults = UserDefaults.standard
    private let windowStateKey = "MiNoteWindowStates"

    // MARK: - Public Methods

    /// 保存窗口状态
    /// - Parameters:
    ///   - windowState: 窗口状态
    ///   - windowId: 窗口标识符
    public func saveWindowState(_ windowState: MainWindowState, forWindowId windowId: String = "main") {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: windowState, requiringSecureCoding: true)

            var savedStates = getSavedWindowStates()
            savedStates[windowId] = data

            userDefaults.set(try? JSONSerialization.data(withJSONObject: savedStates), forKey: windowStateKey)
            print("窗口状态保存成功: \(windowId)")
        } catch {
            print("保存窗口状态失败: \(error)")
        }
    }

    /// 获取保存的窗口状态
    /// - Parameter windowId: 窗口标识符
    /// - Returns: 窗口状态，如果不存在则返回 nil
    public func getWindowState(forWindowId windowId: String = "main") -> MainWindowState? {
        let savedStates = getSavedWindowStates()

        guard let data = savedStates[windowId] as? Data else {
            return nil
        }

        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: MainWindowState.self, from: data)
        } catch {
            print("恢复窗口状态失败: \(error)")
            return nil
        }
    }

    /// 删除窗口状态
    /// - Parameter windowId: 窗口标识符
    public func removeWindowState(forWindowId windowId: String = "main") {
        var savedStates = getSavedWindowStates()
        savedStates.removeValue(forKey: windowId)

        if let data = try? JSONSerialization.data(withJSONObject: savedStates) {
            userDefaults.set(data, forKey: windowStateKey)
        }
    }

    /// 清除所有窗口状态
    public func clearAllWindowStates() {
        userDefaults.removeObject(forKey: windowStateKey)
    }

    /// 获取所有保存的窗口状态
    /// - Returns: 窗口状态字典
    public func getAllWindowStates() -> [String: MainWindowState] {
        let savedStates = getSavedWindowStates()

        var result: [String: MainWindowState] = [:]

        for (windowId, data) in savedStates {
            if let data = data as? Data,
               let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MainWindowState.self, from: data)
            {
                result[windowId] = state
            }
        }

        return result
    }

    /// 保存窗口 frame
    /// - Parameters:
    ///   - frame: 窗口 frame
    ///   - windowId: 窗口标识符
    public func saveWindowFrame(_ frame: CGRect, forWindowId windowId: String = "main") {
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
        ]

        var savedFrames = getSavedWindowFrames()
        savedFrames[windowId] = frameDict

        userDefaults.set(savedFrames, forKey: "MiNoteWindowFrames")
    }

    /// 获取保存的窗口 frame
    /// - Parameter windowId: 窗口标识符
    /// - Returns: 窗口 frame，如果不存在则返回 nil
    public func getWindowFrame(forWindowId windowId: String = "main") -> CGRect? {
        let savedFrames = getSavedWindowFrames()

        guard let frameDict = savedFrames[windowId] as? [String: CGFloat],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"]
        else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Private Methods

    private func getSavedWindowStates() -> [String: Any] {
        guard let data = userDefaults.data(forKey: windowStateKey) else {
            return [:]
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return jsonObject
    }

    private func getSavedWindowFrames() -> [String: Any] {
        userDefaults.dictionary(forKey: "MiNoteWindowFrames") ?? [:]
    }

    // MARK: - Convenience Methods

    /// 创建默认窗口状态
    /// - Returns: 默认窗口状态
    public static func createDefaultWindowState() -> MainWindowState {
        MainWindowState.defaultState()
    }

    /// 检查是否有保存的窗口状态
    /// - Parameter windowId: 窗口标识符
    /// - Returns: 是否有保存的状态
    public func hasSavedState(forWindowId windowId: String = "main") -> Bool {
        getWindowState(forWindowId: windowId) != nil
    }

    /// 迁移旧版窗口状态
    public func migrateLegacyWindowState() {
        // 检查是否有旧版窗口状态
        let legacyX = userDefaults.float(forKey: "LastWindowX")
        let legacyY = userDefaults.float(forKey: "LastWindowY")
        let legacyWidth = userDefaults.float(forKey: "LastWindowWidth")
        let legacyHeight = userDefaults.float(forKey: "LastWindowHeight")

        if legacyX != 0 || legacyY != 0 || legacyWidth != 0 || legacyHeight != 0 {
            // 创建新的窗口状态
            let frame = CGRect(
                x: CGFloat(legacyX),
                y: CGFloat(legacyY),
                width: CGFloat(legacyWidth),
                height: CGFloat(legacyHeight)
            )
            saveWindowFrame(frame)

            // 清除旧版数据
            userDefaults.removeObject(forKey: "LastWindowX")
            userDefaults.removeObject(forKey: "LastWindowY")
            userDefaults.removeObject(forKey: "LastWindowWidth")
            userDefaults.removeObject(forKey: "LastWindowHeight")

            print("旧版窗口状态迁移完成")
        }
    }
}
