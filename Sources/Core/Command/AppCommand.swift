//
//  AppCommand.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 应用命令协议
    /// 菜单、工具栏、快捷键统一通过 Command 调度业务操作
    @MainActor
    protocol AppCommand: Sendable {
        func execute(with context: CommandContext)
    }

    /// 命令执行上下文
    @MainActor
    struct CommandContext: Sendable {
        let coordinator: AppCoordinator
    }

    /// 命令调度器
    @MainActor
    final class CommandDispatcher: Sendable {
        private let context: CommandContext

        init(coordinator: AppCoordinator) {
            self.context = CommandContext(coordinator: coordinator)
        }

        func dispatch(_ command: AppCommand) {
            command.execute(with: context)
        }
    }
#endif
