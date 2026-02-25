//
//  UtilityCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    // MARK: - 应用程序命令

    /// 显示关于面板
    public struct ShowAboutPanelCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            let alert = NSAlert()
            alert.messageText = "小米笔记"
            alert.informativeText = "版本 2.1.0\n\n一个简洁的笔记应用程序，支持小米笔记同步。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    /// 显示帮助
    public struct ShowHelpCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {}
    }

    // MARK: - 认证命令

    /// 显示登录
    public struct ShowLoginCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.showLogin(nil)
        }
    }

    // MARK: - 调试命令

    /// 显示调试设置窗口
    public struct ShowDebugSettingsCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            let debugWindowController = DebugWindowController()
            debugWindowController.showWindow(nil)
            debugWindowController.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 测试音频文件 API
    public struct TestAudioFileAPICommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {}
    }

    /// 显示离线操作
    public struct ShowOfflineOperationsCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {}
    }

    // MARK: - 查找命令

    /// 显示查找面板
    public struct ShowFindPanelCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.showFindPanel(nil)
        }
    }

    /// 显示查找和替换面板
    public struct ShowFindAndReplacePanelCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.showFindAndReplacePanel(nil)
        }
    }

    /// 查找下一个
    public struct FindNextCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.findNext(nil)
        }
    }

    /// 查找上一个
    public struct FindPreviousCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.findPrevious(nil)
        }
    }

    // MARK: - 附件命令

    /// 附加文件
    public struct AttachFileCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.insertAttachment(nil)
        }
    }

    /// 添加链接
    public struct AddLinkCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            let alert = NSAlert()
            alert.messageText = "添加链接"
            alert.informativeText = "请输入链接地址："
            alert.alertStyle = .informational
            alert.addButton(withTitle: "添加")
            alert.addButton(withTitle: "取消")

            let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            inputField.placeholderString = "https://example.com"
            alert.accessoryView = inputField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let urlString = inputField.stringValue
                if !urlString.isEmpty {
                    context.coordinator.mainWindowController?.addLink(urlString)
                }
            }
        }
    }
#endif
