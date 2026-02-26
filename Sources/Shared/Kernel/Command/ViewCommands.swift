//
//  ViewCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    // MARK: - 视图切换命令

    /// 设置列表视图
    public struct SetListViewCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            ViewOptionsManager.shared.setViewMode(.list)
        }
    }

    /// 设置画廊视图
    public struct SetGalleryViewCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            ViewOptionsManager.shared.setViewMode(.gallery)
        }
    }

    // MARK: - 显示切换命令

    /// 切换文件夹侧边栏可见性
    public struct ToggleFolderVisibilityCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            guard let window = NSApp.mainWindow,
                  let splitViewController = window.contentViewController as? NSSplitViewController,
                  !splitViewController.splitViewItems.isEmpty
            else { return }

            let sidebarItem = splitViewController.splitViewItems[0]
            let newCollapsedState = !sidebarItem.isCollapsed

            sidebarItem.animator().isCollapsed = newCollapsedState

            NotificationCenter.default.post(
                name: .folderVisibilityDidChange,
                object: nil,
                userInfo: ["isFolderHidden": newCollapsedState]
            )
        }
    }

    /// 切换笔记数量显示
    public struct ToggleNoteCountCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            ViewOptionsManager.shared.toggleNoteCount()
        }
    }

    // MARK: - 缩放命令

    /// 放大
    public struct ZoomInCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.zoomIn(nil)
        }
    }

    /// 缩小
    public struct ZoomOutCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.zoomOut(nil)
        }
    }

    /// 实际大小
    public struct ActualSizeCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.actualSize(nil)
        }
    }

#endif
