//
//  WindowCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 显示设置窗口命令
    public struct ShowSettingsCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            let settingsWindowController = SettingsWindowController(coordinator: context.coordinator)
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - 窗口布局命令

    /// 填充窗口到屏幕可用区域
    public struct FillWindowCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            window.setFrame(visibleFrame, display: true, animate: true)
        }
    }

    /// 居中窗口
    public struct CenterWindowCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow else { return }
            window.center()
        }
    }

    /// 移动窗口到屏幕左半边
    public struct MoveWindowToLeftHalfCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            let newFrame = NSRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    /// 移动窗口到屏幕右半边
    public struct MoveWindowToRightHalfCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            let newFrame = NSRect(
                x: visibleFrame.origin.x + visibleFrame.width / 2,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    /// 移动窗口到屏幕上半边
    public struct MoveWindowToTopHalfCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            let newFrame = NSRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y + visibleFrame.height / 2,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    /// 移动窗口到屏幕下半边
    public struct MoveWindowToBottomHalfCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            let newFrame = NSRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    /// 最大化窗口
    public struct MaximizeWindowCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow else { return }
            window.performZoom(nil)
        }
    }

    /// 恢复窗口大小
    public struct RestoreWindowCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow else { return }
            if window.isZoomed {
                window.performZoom(nil)
            }
        }
    }

    /// 平铺窗口到屏幕左侧
    public struct TileWindowToLeftCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            let newFrame = NSRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    /// 平铺窗口到屏幕右侧
    public struct TileWindowToRightCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            let newFrame = NSRect(
                x: visibleFrame.origin.x + visibleFrame.width / 2,
                y: visibleFrame.origin.y,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    // MARK: - 窗口管理命令

    /// 创建新窗口
    public struct CreateNewWindowCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.createNewWindow()
        }
    }

    /// 在新窗口中打开笔记
    public struct OpenNoteInNewWindowCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else {
                let alert = NSAlert()
                alert.messageText = "操作失败"
                alert.informativeText = "请先选择一个笔记"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
                return
            }
            context.coordinator.openNoteEditorWindow(note: note)
        }
    }
#endif
