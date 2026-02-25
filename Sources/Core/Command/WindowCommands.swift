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
#endif
