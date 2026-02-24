//
//  SettingsWindowController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/3.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    /// 设置窗口控制器
    /// 负责管理设置窗口，使用 macOS 26 样式（大圆角、导航栏）
    public class SettingsWindowController: NSWindowController, NSToolbarDelegate {

        // MARK: - 属性

        /// AppCoordinator 引用
        private var coordinator: AppCoordinator?

        /// 工具栏标识符
        private static let toolbarIdentifier = NSToolbar.Identifier("SettingsToolbar")

        // MARK: - 初始化

        /// 使用指定的 AppCoordinator 初始化窗口控制器
        public init(coordinator: AppCoordinator? = nil) {
            self.coordinator = coordinator

            // 创建窗口 - 使用 macOS 26 样式（大圆角、材质背景）
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 650, height: 600),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            super.init(window: window)

            // 配置窗口外观 - macOS 26 样式
            configureWindowAppearance(window)

            // 配置工具栏 - 触发大圆角样式
            configureToolbar(window)

            // 设置窗口内容
            setupWindowContent()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - 窗口配置

        /// 配置窗口外观以支持 macOS 26 样式
        private func configureWindowAppearance(_ window: NSWindow) {
            // 基本窗口设置
            window.title = "设置"
            window.setFrameAutosaveName("SettingsWindow")

            // macOS 26 样式关键配置
            window.titleVisibility = .visible

            // 窗口尺寸约束
            window.minSize = NSSize(width: 550, height: 500)
            window.maxSize = NSSize(width: 800, height: 900)

            // 居中显示
            window.center()
        }

        /// 配置工具栏以触发 macOS 26 大圆角样式
        private func configureToolbar(_ window: NSWindow) {
            let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = false

            window.toolbar = toolbar
            window.toolbarStyle = .unified // 统一工具栏样式，触发大圆角
        }

        // MARK: - NSToolbarDelegate

        public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            // 返回空数组，只需要工具栏存在即可触发大圆角样式
            []
        }

        public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            []
        }

        // MARK: - 设置方法

        /// 设置窗口内容
        private func setupWindowContent() {
            guard let window else { return }

            guard let coordinator else {
                LogService.shared.error(.window, "coordinator 为 nil，无法创建设置视图")
                return
            }

            // 创建 SwiftUI 设置视图
            let settingsView = SettingsView(
                syncState: coordinator.syncState,
                authState: coordinator.authState,
                noteStore: coordinator.noteStore,
                apiClient: coordinator.networkModule.apiClient
            )
            .frame(minWidth: 550, minHeight: 500)

            // 使用 NSHostingController 包装 SwiftUI 视图
            let hostingController = NSHostingController(rootView: settingsView)

            // 配置 hosting controller 以支持透明背景
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

            // 设置窗口内容
            window.contentViewController = hostingController
        }
    }

#endif
