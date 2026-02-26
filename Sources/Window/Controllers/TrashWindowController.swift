//
//  TrashWindowController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/4.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    /// 回收站窗口控制器
    /// 负责管理回收站窗口
    public class TrashWindowController: NSWindowController {

        // MARK: - 属性

        /// 笔记列表状态
        private var noteListState: NoteListState

        /// 格式转换器
        private var formatConverter: XiaoMiFormatConverter?

        /// 工具栏代理
        private var toolbarDelegate: BaseSheetToolbarDelegate?

        // MARK: - 初始化

        /// 使用指定的 NoteListState 初始化窗口控制器
        init(noteListState: NoteListState, formatConverter: XiaoMiFormatConverter? = nil) {
            self.noteListState = noteListState
            self.formatConverter = formatConverter

            // 创建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            super.init(window: window)

            // 设置窗口
            window.title = "回收站"
            window.titleVisibility = .visible
            window.setFrameAutosaveName("TrashWindow")

            // 设置窗口内容
            setupWindowContent()

            // 设置工具栏
            setupToolbar()

            // 设置窗口最小尺寸
            window.minSize = NSSize(width: 800, height: 600)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - 设置方法

        /// 设置工具栏
        private func setupToolbar() {
            guard let window else { return }

            // 创建工具栏代理
            toolbarDelegate = BaseSheetToolbarDelegate()
            toolbarDelegate?.onClose = { [weak self] in
                self?.closeWindow()
            }

            let toolbar = NSToolbar(identifier: "TrashWindowToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.delegate = toolbarDelegate
            window.toolbar = toolbar
            window.toolbarStyle = .unified
        }

        /// 设置窗口内容
        private func setupWindowContent() {
            guard let window else { return }

            // 创建SwiftUI回收站视图
            let trashView = TrashView(noteListState: noteListState, formatConverter: formatConverter)

            // 使用NSHostingController包装SwiftUI视图
            let hostingController = NSHostingController(rootView: trashView)

            // 设置窗口内容
            window.contentViewController = hostingController

            // 确保窗口正确显示
            window.center()
        }

        // MARK: - 窗口操作

        /// 关闭窗口
        private func closeWindow() {
            window?.close()
        }
    }

#endif
