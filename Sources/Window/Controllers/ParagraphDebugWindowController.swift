import AppKit
import SwiftUI

/// 段落管理器调试窗口控制器
public class ParagraphDebugWindowController: NSWindowController {

    public convenience init() {
        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "段落管理器调试工具"
        window.center()
        window.setFrameAutosaveName("ParagraphDebugWindow")

        // 设置内容视图
        let contentView = ParagraphManagerDebugView()
        window.contentView = NSHostingView(rootView: contentView)

        self.init(window: window)
    }

    /// 显示窗口
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
