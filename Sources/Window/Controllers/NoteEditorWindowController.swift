#if os(macOS)
    import AppKit
    import Combine
    import SwiftUI

    /// 独立笔记编辑器窗口控制器
    ///
    /// 只显示编辑器区域和工具栏，用于在新窗口中编辑特定笔记
    @MainActor
    public class NoteEditorWindowController: NSWindowController, NSWindowDelegate {

        // MARK: - 属性

        private let coordinator: AppCoordinator
        private let windowState: WindowState
        private let note: Note
        private var cancellables = Set<AnyCancellable>()

        /// 笔记 ID，用于防止重复打开
        public var noteId: String {
            note.id
        }

        // MARK: - 初始化

        public init(coordinator: AppCoordinator, note: Note) {
            self.coordinator = coordinator
            self.note = note

            // 独立模式的 WindowState，不同步主窗口的 selectedNote
            let windowState = WindowState(coordinator: coordinator, standalone: true)
            self.windowState = windowState

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            super.init(window: window)

            window.delegate = self
            configureWindow(window)
            setupContent()

            // 预设选中笔记
            windowState.selectedNote = note
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - 窗口配置

        private func configureWindow(_ window: NSWindow) {
            window.title = note.title.isEmpty ? "未命名笔记" : note.title
            window.titleVisibility = .visible
            window.minSize = NSSize(width: 500, height: 400)
            window.center()

            // 配置工具栏触发 unified 样式
            let toolbar = NSToolbar(identifier: NSToolbar.Identifier("NoteEditorToolbar"))
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified

            // 监听笔记标题变化更新窗口标题
            windowState.$selectedNote
                .compactMap(\.self)
                .receive(on: DispatchQueue.main)
                .sink { [weak window] note in
                    window?.title = note.title.isEmpty ? "未命名笔记" : note.title
                }
                .store(in: &cancellables)
        }

        private func setupContent() {
            guard let window else { return }

            let noteDetailView = NoteDetailView(coordinator: coordinator, windowState: windowState)
                .frame(minWidth: 500, minHeight: 400)

            let hostingController = NSHostingController(rootView: noteDetailView)
            window.contentViewController = hostingController
        }

        // MARK: - NSWindowDelegate

        public func windowWillClose(_: Notification) {
            coordinator.removeEditorWindow(self)
            LogService.shared.info(.window, "编辑器窗口关闭: \(note.title)")
        }
    }

#endif
