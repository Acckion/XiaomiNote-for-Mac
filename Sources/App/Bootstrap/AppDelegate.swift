import AppKit

/// 应用程序委托
/// 替代SwiftUI的App结构，采用纯AppKit架构
/// 使用模块化设计，将功能分解到专门的类中
@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    // MARK: - 属性

    /// 窗口管理器
    private let windowManager: WindowManager

    /// 菜单管理器
    private let menuManager: MenuManager

    /// 应用程序状态管理器
    private let appStateManager: AppStateManager

    /// 命令调度器（coordinator 就绪后初始化）
    private var commandDispatcher: CommandDispatcher?

    /// 菜单状态管理器（coordinator 就绪后初始化）
    private var menuStateManager: MenuStateManager?

    // MARK: - 架构

    /// 应用协调器（对外只读访问）
    private(set) var appCoordinator: AppCoordinator?

    // MARK: - 初始化

    override init() {
        let shell = AppLaunchAssembler.buildShell()
        self.windowManager = shell.windowManager
        self.menuManager = shell.menuManager
        self.appStateManager = shell.appStateManager

        super.init()

        AppLaunchAssembler.bindShell(shell, appDelegate: self)

        LogService.shared.info(.app, "应用程序委托初始化完成")
    }

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_: Notification) {
        LogService.shared.info(.app, "应用启动")

        let shell = AppLaunchAssembler.Shell(
            windowManager: windowManager,
            menuManager: menuManager,
            appStateManager: appStateManager
        )
        let coordinator = AppLaunchAssembler.buildRuntime(shell: shell)
        appCoordinator = coordinator

        // 初始化命令调度器和菜单状态管理器
        commandDispatcher = coordinator.commandDispatcher
        menuStateManager = MenuStateManager(mainWindowController: windowManager.mainWindowController)

        Task { @MainActor in
            await coordinator.start()
        }

        appStateManager.handleApplicationDidFinishLaunching()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        appStateManager.shouldTerminateAfterLastWindowClosed()
    }

    public func applicationWillTerminate(_: Notification) {
        appStateManager.handleApplicationWillTerminate()
    }

    public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appStateManager.handleApplicationReopen(hasVisibleWindows: flag)
    }

    // MARK: - 公共属性

    /// 主窗口控制器（对外暴露）
    var mainWindowController: MainWindowController? {
        windowManager.mainWindowController
    }

    /// 应用协调器（对外暴露）
    var coordinator: AppCoordinator? {
        appCoordinator
    }

    // MARK: - 窗口管理方法（对外暴露）

    /// 创建新窗口
    func createNewWindow() {
        _ = windowManager.createNewWindow()
        menuStateManager?.updateMainWindowController(windowManager.mainWindowController)
    }

    /// 创建新窗口并打开指定笔记
    ///
    /// 注意：此方法为多窗口支持预留，当前实现将在任务 5 完成后启用
    ///
    /// - Parameter note: 要在新窗口中打开的笔记
    public func createNewWindow(withNote note: Note?) {
        if let controller = windowManager.createNewWindow(withNote: note) {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 移除窗口控制器
    /// - Parameter windowController: 要移除的窗口控制器
    func removeWindowController(_ windowController: MainWindowController) {
        windowManager.removeWindowController(windowController)
    }

    // MARK: - 格式菜单动作

    @objc func toggleBold(_: Any?) {
        commandDispatcher?.dispatch(ToggleBoldCommand())
    }

    @objc func toggleItalic(_: Any?) {
        commandDispatcher?.dispatch(ToggleItalicCommand())
    }

    @objc func toggleUnderline(_: Any?) {
        commandDispatcher?.dispatch(ToggleUnderlineCommand())
    }

    @objc func toggleStrikethrough(_: Any?) {
        commandDispatcher?.dispatch(ToggleStrikethroughCommand())
    }

    @objc func increaseFontSize(_: Any?) {
        commandDispatcher?.dispatch(IncreaseFontSizeCommand())
    }

    @objc func decreaseFontSize(_: Any?) {
        commandDispatcher?.dispatch(DecreaseFontSizeCommand())
    }

    @objc func setHeading(_: Any?) {
        commandDispatcher?.dispatch(SetHeadingCommand())
    }

    @objc func setSubheading(_: Any?) {
        commandDispatcher?.dispatch(SetSubheadingCommand())
    }

    @objc func setSubtitle(_: Any?) {
        commandDispatcher?.dispatch(SetSubtitleCommand())
    }

    @objc func setBodyText(_: Any?) {
        commandDispatcher?.dispatch(SetBodyTextCommand())
    }

    // 旧版格式方法（向后兼容）

    @objc func setHeading1(_: Any?) {
        commandDispatcher?.dispatch(SetHeadingCommand())
    }

    @objc func setHeading2(_: Any?) {
        commandDispatcher?.dispatch(SetSubheadingCommand())
    }

    @objc func setHeading3(_: Any?) {
        commandDispatcher?.dispatch(SetSubtitleCommand())
    }

    @objc func toggleOrderedList(_: Any?) {
        commandDispatcher?.dispatch(ToggleOrderedListCommand())
    }

    @objc func toggleUnorderedList(_: Any?) {
        commandDispatcher?.dispatch(ToggleUnorderedListCommand())
    }

    @objc func toggleBulletList(_: Any?) {
        commandDispatcher?.dispatch(ToggleUnorderedListCommand())
    }

    @objc func toggleNumberedList(_: Any?) {
        commandDispatcher?.dispatch(ToggleOrderedListCommand())
    }

    @objc func toggleCheckboxList(_: Any?) {
        commandDispatcher?.dispatch(ToggleCheckboxListCommand())
    }

    @objc func toggleBlockQuote(_: Any?) {
        commandDispatcher?.dispatch(ToggleBlockQuoteCommand())
    }

    @objc func increaseIndent(_: Any?) {
        commandDispatcher?.dispatch(IncreaseIndentCommand())
    }

    @objc func decreaseIndent(_: Any?) {
        commandDispatcher?.dispatch(DecreaseIndentCommand())
    }

    @objc func alignLeft(_: Any?) {
        commandDispatcher?.dispatch(AlignLeftCommand())
    }

    @objc func alignCenter(_: Any?) {
        commandDispatcher?.dispatch(AlignCenterCommand())
    }

    @objc func alignRight(_: Any?) {
        commandDispatcher?.dispatch(AlignRightCommand())
    }

    // MARK: - 核对清单动作

    @objc func toggleChecklist(_: Any?) {
        commandDispatcher?.dispatch(ToggleCheckboxListCommand())
    }

    @objc func markAsChecked(_: Any?) {
        commandDispatcher?.dispatch(MarkAsCheckedCommand())
    }

    @objc func checkAll(_: Any?) {
        commandDispatcher?.dispatch(CheckAllCommand())
    }

    @objc func uncheckAll(_: Any?) {
        commandDispatcher?.dispatch(UncheckAllCommand())
    }

    @objc func moveCheckedToBottom(_: Any?) {
        commandDispatcher?.dispatch(MoveCheckedToBottomCommand())
    }

    @objc func deleteCheckedItems(_: Any?) {
        commandDispatcher?.dispatch(DeleteCheckedItemsCommand())
    }

    @objc func moveItemUp(_: Any?) {
        commandDispatcher?.dispatch(MoveItemUpCommand())
    }

    @objc func moveItemDown(_: Any?) {
        commandDispatcher?.dispatch(MoveItemDownCommand())
    }

    // MARK: - 外观动作

    @objc func toggleLightBackground(_: Any?) {
        commandDispatcher?.dispatch(ToggleLightBackgroundCommand())
    }

    @objc func toggleHighlight(_: Any?) {
        commandDispatcher?.dispatch(ToggleHighlightCommand())
    }

    // MARK: - 文件菜单动作

    @objc func createNewNote(_: Any?) {
        commandDispatcher?.dispatch(CreateNoteCommand(folderId: appCoordinator?.folderState.selectedFolderId))
    }

    @objc func createNewFolder(_: Any?) {
        commandDispatcher?.dispatch(CreateFolderCommand())
    }

    @objc func shareNote(_: Any?) {
        commandDispatcher?.dispatch(ShareNoteCommand(window: mainWindowController?.window))
    }

    @objc func importNotes(_: Any?) {
        commandDispatcher?.dispatch(ImportNotesCommand())
    }

    @objc func importMarkdown(_: Any?) {
        commandDispatcher?.dispatch(ImportMarkdownCommand())
    }

    @objc func exportNote(_: Any?) {
        commandDispatcher?.dispatch(ExportNoteCommand())
    }

    @objc func exportAsPDF(_: Any?) {
        commandDispatcher?.dispatch(ExportAsPDFCommand())
    }

    @objc func exportAsMarkdown(_: Any?) {
        commandDispatcher?.dispatch(ExportAsMarkdownCommand())
    }

    @objc func exportAsPlainText(_: Any?) {
        commandDispatcher?.dispatch(ExportAsPlainTextCommand())
    }

    @objc func copyNote(_: Any?) {
        commandDispatcher?.dispatch(CopyNoteCommand())
    }

    @objc func duplicateNote(_: Any?) {
        commandDispatcher?.dispatch(DuplicateNoteCommand())
    }

    @objc func toggleStarNote(_: Any?) {
        commandDispatcher?.dispatch(ToggleStarCommand())
    }

    @objc func createSmartFolder(_: Any?) {
        commandDispatcher?.dispatch(CreateSmartFolderCommand())
    }

    @objc func addToPrivateNotes(_: Any?) {
        commandDispatcher?.dispatch(AddToPrivateNotesCommand())
    }

    // MARK: - 窗口菜单动作

    @objc func createNewWindow(_: Any?) {
        commandDispatcher?.dispatch(CreateNewWindowCommand())
    }

    @objc func fillWindow(_: Any?) {
        commandDispatcher?.dispatch(FillWindowCommand())
    }

    @objc func centerWindow(_: Any?) {
        commandDispatcher?.dispatch(CenterWindowCommand())
    }

    @objc func moveWindowToLeftHalf(_: Any?) {
        commandDispatcher?.dispatch(MoveWindowToLeftHalfCommand())
    }

    @objc func moveWindowToRightHalf(_: Any?) {
        commandDispatcher?.dispatch(MoveWindowToRightHalfCommand())
    }

    @objc func moveWindowToTopHalf(_: Any?) {
        commandDispatcher?.dispatch(MoveWindowToTopHalfCommand())
    }

    @objc func moveWindowToBottomHalf(_: Any?) {
        commandDispatcher?.dispatch(MoveWindowToBottomHalfCommand())
    }

    @objc func maximizeWindow(_: Any?) {
        commandDispatcher?.dispatch(MaximizeWindowCommand())
    }

    @objc func restoreWindow(_: Any?) {
        commandDispatcher?.dispatch(RestoreWindowCommand())
    }

    @objc func tileWindowToLeft(_: Any?) {
        commandDispatcher?.dispatch(TileWindowToLeftCommand())
    }

    @objc func tileWindowToRight(_: Any?) {
        commandDispatcher?.dispatch(TileWindowToRightCommand())
    }

    @objc func openNoteInNewWindow(_: Any?) {
        commandDispatcher?.dispatch(OpenNoteInNewWindowCommand())
    }

    // MARK: - 视图菜单动作

    @objc func setListView(_: Any?) {
        commandDispatcher?.dispatch(SetListViewCommand())
    }

    @objc func setGalleryView(_: Any?) {
        commandDispatcher?.dispatch(SetGalleryViewCommand())
    }

    @objc func toggleFolderVisibility(_: Any?) {
        commandDispatcher?.dispatch(ToggleFolderVisibilityCommand())
    }

    @objc func toggleNoteCount(_: Any?) {
        commandDispatcher?.dispatch(ToggleNoteCountCommand())
    }

    @objc func zoomIn(_: Any?) {
        commandDispatcher?.dispatch(ZoomInCommand())
    }

    @objc func zoomOut(_: Any?) {
        commandDispatcher?.dispatch(ZoomOutCommand())
    }

    @objc func actualSize(_: Any?) {
        commandDispatcher?.dispatch(ActualSizeCommand())
    }

    @objc func expandSection(_: Any?) {
        commandDispatcher?.dispatch(ExpandSectionCommand())
    }

    @objc func expandAllSections(_: Any?) {
        commandDispatcher?.dispatch(ExpandAllSectionsCommand())
    }

    @objc func collapseSection(_: Any?) {
        commandDispatcher?.dispatch(CollapseSectionCommand())
    }

    @objc func collapseAllSections(_: Any?) {
        commandDispatcher?.dispatch(CollapseAllSectionsCommand())
    }

    // MARK: - 杂项菜单动作

    @objc func showAboutPanel(_: Any?) {
        commandDispatcher?.dispatch(ShowAboutPanelCommand())
    }

    @objc func showSettings(_: Any?) {
        commandDispatcher?.dispatch(ShowSettingsCommand())
    }

    @objc func showHelp(_: Any?) {
        commandDispatcher?.dispatch(ShowHelpCommand())
    }

    @objc func showLogin(_: Any?) {
        commandDispatcher?.dispatch(ShowLoginCommand())
    }

    @objc func showDebugSettings(_: Any?) {
        commandDispatcher?.dispatch(ShowDebugSettingsCommand())
    }

    @objc func testAudioFileAPI(_: Any?) {
        commandDispatcher?.dispatch(TestAudioFileAPICommand())
    }

    @objc func showOfflineOperations(_: Any?) {
        commandDispatcher?.dispatch(ShowOfflineOperationsCommand())
    }

    @objc func showFindPanel(_: Any?) {
        commandDispatcher?.dispatch(ShowFindPanelCommand())
    }

    @objc func showFindAndReplacePanel(_: Any?) {
        commandDispatcher?.dispatch(ShowFindAndReplacePanelCommand())
    }

    @objc func findNext(_: Any?) {
        commandDispatcher?.dispatch(FindNextCommand())
    }

    @objc func findPrevious(_: Any?) {
        commandDispatcher?.dispatch(FindPreviousCommand())
    }

    @objc func attachFile(_: Any?) {
        commandDispatcher?.dispatch(AttachFileCommand())
    }

    @objc func addLink(_: Any?) {
        commandDispatcher?.dispatch(AddLinkCommand())
    }

    // MARK: - NSMenuItemValidation

    /// 验证菜单项是否应该启用
    /// 将验证委托给 MenuStateManager
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuStateManager?.validateMenuItem(menuItem) ?? true
    }

}

// MARK: - 应用程序启动器

/// 应用程序启动器
/// 确保应用程序正确启动
class ApplicationLauncher {
    @MainActor
    static func launch() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
