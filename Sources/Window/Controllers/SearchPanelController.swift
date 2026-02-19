//
//  SearchPanelController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/7.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Combine
    import os
    import SwiftUI

    /// 查找面板控制器
    /// 负责管理查找面板的显示、隐藏和查找逻辑
    public class SearchPanelController: NSObject {
        private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "SearchPanelController")

        // MARK: - 属性

        /// 主窗口控制器引用
        private weak var mainWindowController: MainWindowController?

        /// 查找面板窗口
        private var searchPanelWindow: NSWindow?

        /// 查找面板的托管控制器
        private var searchPanelHostingController: NSHostingController<SearchPanelView>?

        /// 当前搜索文本
        @Published var searchText = ""

        /// 当前替换文本
        @Published var replaceText = ""

        /// 是否区分大小写
        @Published var isCaseSensitive = false

        /// 是否全字匹配
        @Published var isWholeWord = false

        /// 是否使用正则表达式
        @Published var isRegex = false

        /// Combine订阅集合
        private var cancellables = Set<AnyCancellable>()

        // MARK: - 初始化

        /// 初始化查找面板控制器
        /// - Parameter mainWindowController: 主窗口控制器
        public init(mainWindowController: MainWindowController) {
            self.mainWindowController = mainWindowController
            super.init()

            setupKeyboardShortcuts()
        }

        // MARK: - 公共方法

        /// 显示查找面板
        @MainActor
        public func showSearchPanel() {
            NSApp.activate(ignoringOtherApps: true)

            if searchPanelWindow == nil {
                createSearchPanel()
            }

            guard let window = searchPanelWindow else {
                LogService.shared.error(.window, "查找面板窗口创建失败")
                return
            }

            // 如果窗口已经显示，只需要激活它
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return
            }

            // 设置窗口的父窗口为应用程序的主窗口
            if let mainWindow = mainWindowController?.window {
                window.parent = mainWindow
            }

            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        /// 隐藏查找面板
        @MainActor
        public func hideSearchPanel() {
            guard let window = searchPanelWindow else { return }

            // 隐藏前清除所有查找高亮和选择
            clearAllSearchHighlights()

            window.orderOut(nil)
        }

        /// 切换查找面板的显示/隐藏状态
        @MainActor
        public func toggleSearchPanel() {
            if searchPanelWindow?.isVisible == true {
                hideSearchPanel()
            } else {
                showSearchPanel()
            }
        }

        // MARK: - 私有方法

        /// 创建查找面板
        @MainActor
        private func createSearchPanel() {
            // 创建SwiftUI视图，创建StateObject来管理状态
            let viewModel = SearchPanelViewModel(
                searchText: searchText,
                replaceText: replaceText,
                isCaseSensitive: isCaseSensitive,
                isWholeWord: isWholeWord,
                isRegex: isRegex,
                onFindNext: { [weak self] in Task { @MainActor in self?.findNext() } },
                onFindPrevious: { [weak self] in Task { @MainActor in self?.findPrevious() } },
                onReplace: { [weak self] in Task { @MainActor in self?.replace() } },
                onReplaceAll: { [weak self] in Task { @MainActor in self?.replaceAll() } },
                onClose: { [weak self] in Task { @MainActor in self?.hideSearchPanel() } }
            )

            // 设置单向绑定：当ViewModel的属性改变时，同步更新Controller的属性
            // 注意：只设置单向绑定，避免无限递归
            viewModel.$searchText
                .dropFirst() // 跳过初始值，避免不必要的更新
                .sink { [weak self] newValue in
                    self?.searchText = newValue
                }
                .store(in: &cancellables)

            viewModel.$replaceText
                .dropFirst() // 跳过初始值，避免不必要的更新
                .sink { [weak self] newValue in
                    self?.replaceText = newValue
                }
                .store(in: &cancellables)

            viewModel.$isCaseSensitive
                .dropFirst() // 跳过初始值，避免不必要的更新
                .sink { [weak self] newValue in
                    self?.isCaseSensitive = newValue
                }
                .store(in: &cancellables)

            viewModel.$isWholeWord
                .dropFirst() // 跳过初始值，避免不必要的更新
                .sink { [weak self] newValue in
                    self?.isWholeWord = newValue
                }
                .store(in: &cancellables)

            viewModel.$isRegex
                .dropFirst() // 跳过初始值，避免不必要的更新
                .sink { [weak self] newValue in
                    self?.isRegex = newValue
                }
                .store(in: &cancellables)

            let searchPanelView = SearchPanelView(viewModel: viewModel)

            // 创建托管控制器
            let hostingController = NSHostingController(rootView: searchPanelView)
            searchPanelHostingController = hostingController

            // 创建窗口
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            window.contentViewController = hostingController
            window.title = "查找和替换"
            window.isFloatingPanel = true
            window.level = .floating
            window.hidesOnDeactivate = false // 确保窗口在失去焦点时不隐藏
            window.isReleasedWhenClosed = false // 确保窗口关闭时不被释放
            window.worksWhenModal = true // 在模态状态下工作
            window.delegate = self

            // 设置窗口相对于主窗口的位置
            if let mainWindow = mainWindowController?.window {
                let mainFrame = mainWindow.frame
                let panelWidth: CGFloat = 320
                let panelHeight: CGFloat = 240

                // 定位在主窗口右侧
                var panelX = mainFrame.maxX + 20
                var panelY = mainFrame.maxY - panelHeight

                // 确保不超出屏幕边界
                let screenFrame = NSScreen.main?.visibleFrame ?? mainFrame
                if panelX + panelWidth > screenFrame.maxX {
                    panelX = mainFrame.minX - panelWidth - 20
                }
                if panelY < screenFrame.minY {
                    panelY = screenFrame.minY
                }

                window.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: false)
            }

            searchPanelWindow = window
        }

        /// 设置键盘快捷键
        private func setupKeyboardShortcuts() {
            // 键盘快捷键会在菜单管理器中设置，这里不需要处理
            logger.debug("查找面板控制器初始化完成")
        }

        /// 查找下一个匹配项
        @MainActor
        public func findNext() {
            guard !searchText.isEmpty else { return }
            findInEditor(direction: "next")
        }

        /// 查找上一个匹配项
        @MainActor
        public func findPrevious() {
            guard !searchText.isEmpty else { return }
            findInEditor(direction: "previous")
        }

        /// 替换当前匹配项
        @MainActor
        private func replace() {
            guard !searchText.isEmpty else { return }

            logger.debug("替换: \(searchText) -> \(replaceText)")

            // 调用编辑器的替换功能
            replaceInEditor(replaceAll: false)
        }

        /// 替换所有匹配项
        @MainActor
        private func replaceAll() {
            guard !searchText.isEmpty else { return }

            logger.debug("替换所有: \(searchText) -> \(replaceText)")

            // 调用编辑器的替换所有功能
            replaceInEditor(replaceAll: true)
        }

        /// 在编辑器中查找
        @MainActor
        private func findInEditor(direction _: String) {
            // TODO: 实现原生编辑器的查找功能
            logger.warning("原生编辑器的查找功能尚未实现")
        }

        /// 在编辑器中替换
        @MainActor
        private func replaceInEditor(replaceAll _: Bool) {
            // TODO: 实现原生编辑器的替换功能
            logger.warning("原生编辑器的替换功能尚未实现")
        }

        /// 清除所有查找高亮和选择
        @MainActor
        private func clearAllSearchHighlights() {
            // TODO: 实现原生编辑器的高亮清除功能
        }
    }

    // MARK: - NSWindowDelegate

    extension SearchPanelController: NSWindowDelegate {
        public func windowWillClose(_: Notification) {
            // 窗口关闭时清理引用
            searchPanelHostingController = nil
            searchPanelWindow = nil

            logger.debug("查找面板窗口已关闭")
        }

        public func windowDidBecomeKey(_: Notification) {
            // 窗口成为活动窗口时的处理
            logger.debug("查找面板成为活动窗口")
        }
    }
#endif
