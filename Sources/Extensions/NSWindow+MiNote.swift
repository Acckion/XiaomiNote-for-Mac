import AppKit

extension NSWindow {

    /// 设置窗口的位置和大小，并确保适应屏幕
    /// - Parameters:
    ///   - point: 窗口的左上角坐标
    ///   - size: 窗口的大小
    ///   - minimumSize: 窗口的最小大小，默认为系统默认值
    func setPointAndSizeAdjustingForScreen(point: NSPoint, size: NSSize, minimumSize: NSSize? = nil) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        var newFrame = NSRect(origin: point, size: size)

        // 确保窗口不会超出屏幕顶部
        if newFrame.maxY > screenFrame.maxY {
            newFrame.origin.y = screenFrame.maxY - newFrame.height
        }

        // 确保窗口不会超出屏幕左侧
        if newFrame.minX < screenFrame.minX {
            newFrame.origin.x = screenFrame.minX
        }

        // 确保窗口不会超出屏幕右侧
        if newFrame.maxX > screenFrame.maxX {
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        }

        // 确保窗口不会超出屏幕底部
        if newFrame.minY < screenFrame.minY {
            newFrame.origin.y = screenFrame.minY
        }

        // 确保窗口大小不小于最小大小
        if let minimumSize {
            if newFrame.width < minimumSize.width {
                newFrame.size.width = minimumSize.width
            }
            if newFrame.height < minimumSize.height {
                newFrame.size.height = minimumSize.height
            }
        }

        // 确保窗口大小不超过屏幕大小
        if newFrame.width > screenFrame.width {
            newFrame.size.width = screenFrame.width
        }
        if newFrame.height > screenFrame.height {
            newFrame.size.height = screenFrame.height
        }

        // 应用调整后的 frame
        setFrame(newFrame, display: true)
    }

    /// 将窗口居中显示在屏幕上
    /// - Parameter size: 窗口的大小，如果为 nil 则保持当前大小
    func centerOnScreen(size: NSSize? = nil) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        var newFrame = frame

        if let size {
            newFrame.size = size
        }

        newFrame.origin.x = screenFrame.midX - newFrame.width / 2
        newFrame.origin.y = screenFrame.midY - newFrame.height / 2

        setFrame(newFrame, display: true)
    }

    /// 检查窗口是否完全在屏幕内
    var isFullyOnScreen: Bool {
        guard let screen = NSScreen.main else { return false }

        let screenFrame = screen.visibleFrame
        let windowFrame = frame

        return screenFrame.contains(windowFrame)
    }

    /// 将窗口调整到屏幕内，确保窗口完全可见
    func adjustToFitScreen() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        var windowFrame = frame

        // 如果窗口宽度超过屏幕宽度，调整宽度
        if windowFrame.width > screenFrame.width {
            windowFrame.size.width = screenFrame.width
        }

        // 如果窗口高度超过屏幕高度，调整高度
        if windowFrame.height > screenFrame.height {
            windowFrame.size.height = screenFrame.height
        }

        // 如果窗口右侧超出屏幕，向左移动
        if windowFrame.maxX > screenFrame.maxX {
            windowFrame.origin.x = screenFrame.maxX - windowFrame.width
        }

        // 如果窗口左侧超出屏幕，向右移动
        if windowFrame.minX < screenFrame.minX {
            windowFrame.origin.x = screenFrame.minX
        }

        // 如果窗口顶部超出屏幕，向下移动
        if windowFrame.maxY > screenFrame.maxY {
            windowFrame.origin.y = screenFrame.maxY - windowFrame.height
        }

        // 如果窗口底部超出屏幕，向上移动
        if windowFrame.minY < screenFrame.minY {
            windowFrame.origin.y = screenFrame.minY
        }

        setFrame(windowFrame, display: true)
    }

    /// 获取窗口的保存状态
    var savableState: [String: Any] {
        let frame = frame
        return [
            "frame": [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height,
            ],
            "isFullScreen": styleMask.contains(.fullScreen),
            "isMiniaturized": isMiniaturized,
            "isVisible": isVisible,
        ]
    }

    /// 从保存的状态恢复窗口
    /// - Parameter state: 保存的状态字典
    func restoreState(from state: [String: Any]) -> Bool {
        guard let frameDict = state["frame"] as? [String: CGFloat],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"]
        else {
            return false
        }

        let frame = NSRect(x: x, y: y, width: width, height: height)
        setFrame(frame, display: true)

        if let isFullScreen = state["isFullScreen"] as? Bool, isFullScreen {
            toggleFullScreen(nil)
        }

        return true
    }
}
