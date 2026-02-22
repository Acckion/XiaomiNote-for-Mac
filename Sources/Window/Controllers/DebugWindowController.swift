//
//  DebugWindowController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/3.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    /// 调试窗口控制器
    /// 负责管理调试设置窗口
    public class DebugWindowController: NSWindowController {

        // MARK: - 初始化

        public init() {

            // 创建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            super.init(window: window)

            // 设置窗口
            window.title = "调试设置"
            window.titleVisibility = .visible
            window.setFrameAutosaveName("DebugWindow")

            // 设置窗口内容
            setupWindowContent()

            // 设置窗口最小尺寸 (确保内容可见)
            window.minSize = NSSize(width: 800, height: 600)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - 设置方法

        /// 设置窗口内容
        private func setupWindowContent() {
            guard let window else { return }

            // 创建SwiftUI调试设置视图
            let debugSettingsView = DebugSettingsView()

            // 使用NSHostingController包装SwiftUI视图
            let hostingController = NSHostingController(rootView: debugSettingsView)

            // 设置窗口内容
            window.contentViewController = hostingController
        }
    }

#endif
