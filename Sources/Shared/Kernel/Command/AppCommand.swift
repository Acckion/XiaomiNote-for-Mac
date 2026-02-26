//
//  AppCommand.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 应用命令协议
    /// 菜单、工具栏、快捷键统一通过 Command 调度业务操作
    @MainActor
    public protocol AppCommand {
        init()
        func execute(with context: CommandContext)
    }

    /// 命令执行上下文
    @MainActor
    public struct CommandContext {
        let coordinator: AppCoordinator

        public init(coordinator: AppCoordinator) {
            self.coordinator = coordinator
        }
    }

    /// 命令调度器
    @MainActor
    public final class CommandDispatcher {
        private weak var coordinator: AppCoordinator?

        public init(coordinator: AppCoordinator) {
            self.coordinator = coordinator
        }

        public func dispatch(_ command: AppCommand) {
            guard let coordinator else {
                LogService.shared.warning(.app, "CommandDispatcher 未找到有效的 AppCoordinator，忽略命令")
                return
            }
            let context = CommandContext(coordinator: coordinator)
            command.execute(with: context)
        }
    }
#endif
