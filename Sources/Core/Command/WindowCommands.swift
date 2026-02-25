//
//  WindowCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 显示设置窗口命令
    struct ShowSettingsCommand: AppCommand {
        func execute(with context: CommandContext) {
            let settingsWindowController = SettingsWindowController(coordinator: context.coordinator)
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
        }
    }
#endif
