import AppKit
import MiNoteLibrary

/// AppDelegate 启动装配器
///
/// 负责 App 层对象创建与启动接线，减轻 AppDelegate 负担。
@MainActor
enum AppLaunchAssembler {
    struct Shell {
        let windowManager: WindowManager
        let menuManager: MenuManager
        let appStateManager: AppStateManager
        let menuActionHandler: MenuActionHandler
    }

    static func buildShell() -> Shell {
        let windowManager = WindowManager()
        let menuManager = MenuManager(appDelegate: nil, mainWindowController: windowManager.mainWindowController)
        let appStateManager = AppStateManager(windowManager: windowManager, menuManager: menuManager)
        let menuActionHandler = MenuActionHandler(
            mainWindowController: windowManager.mainWindowController,
            windowManager: windowManager
        )

        return Shell(
            windowManager: windowManager,
            menuManager: menuManager,
            appStateManager: appStateManager,
            menuActionHandler: menuActionHandler
        )
    }

    static func bindShell(_ shell: Shell, appDelegate: AppDelegate) {
        shell.menuManager.updateReferences(
            appDelegate: appDelegate,
            mainWindowController: shell.windowManager.mainWindowController
        )
    }

    static func buildRuntime(shell: Shell) -> AppCoordinator {
        let coordinator = AppCoordinatorAssembler.assemble(windowManager: shell.windowManager)

        shell.appStateManager.configure(
            errorRecoveryService: coordinator.errorRecoveryService,
            networkRecoveryHandler: coordinator.networkRecoveryHandler,
            onlineStateManager: coordinator.onlineStateManager
        )
        shell.windowManager.setAppCoordinator(coordinator)
        shell.menuActionHandler.updateMainWindowController(shell.windowManager.mainWindowController)
        shell.menuActionHandler.setFormatStateManager(coordinator.editorModule.formatStateManager)
        shell.menuActionHandler.setCommandDispatcher(coordinator.commandDispatcher)

        return coordinator
    }
}
