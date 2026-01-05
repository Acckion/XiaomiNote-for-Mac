import AppKit

// MARK: - 简单的窗口状态管理器

/// 简单的窗口状态管理器，用于在 AppDelegate 中管理窗口状态
class MiNoteWindowStateManager {
    
    private let userDefaults = UserDefaults.standard
    
    /// 保存窗口 frame
    func saveWindowFrame(_ frame: CGRect, forWindowId windowId: String = "main") {
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
        ]
        
        var savedFrames = userDefaults.dictionary(forKey: "MiNoteWindowFrames") ?? [:]
        savedFrames[windowId] = frameDict
        
        userDefaults.set(savedFrames, forKey: "MiNoteWindowFrames")
        print("窗口 frame 保存成功: \(windowId)")
    }
    
    /// 获取保存的窗口 frame
    func getWindowFrame(forWindowId windowId: String = "main") -> CGRect? {
        guard let savedFrames = userDefaults.dictionary(forKey: "MiNoteWindowFrames"),
              let frameDict = savedFrames[windowId] as? [String: CGFloat],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"] else {
            return nil
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    /// 迁移旧版窗口状态
    func migrateLegacyWindowState() {
        // 检查是否有旧版窗口状态
        let legacyX = userDefaults.float(forKey: "LastWindowX")
        let legacyY = userDefaults.float(forKey: "LastWindowY")
        let legacyWidth = userDefaults.float(forKey: "LastWindowWidth")
        let legacyHeight = userDefaults.float(forKey: "LastWindowHeight")
        
        if legacyX != 0 || legacyY != 0 || legacyWidth != 0 || legacyHeight != 0 {
            // 创建新的窗口状态
            let frame = CGRect(x: CGFloat(legacyX), y: CGFloat(legacyY), 
                             width: CGFloat(legacyWidth), height: CGFloat(legacyHeight))
            saveWindowFrame(frame)
            
            // 清除旧版数据
            userDefaults.removeObject(forKey: "LastWindowX")
            userDefaults.removeObject(forKey: "LastWindowY")
            userDefaults.removeObject(forKey: "LastWindowWidth")
            userDefaults.removeObject(forKey: "LastWindowHeight")
            
            print("旧版窗口状态迁移完成")
        }
    }
    
    // 为了兼容性，提供空的方法
    func saveWindowState(_ windowState: Any, forWindowId windowId: String = "main") {
        print("保存窗口状态（简化版）: \(windowId)")
    }
    
    func getWindowState(forWindowId windowId: String = "main") -> Any? {
        return nil
    }
}
