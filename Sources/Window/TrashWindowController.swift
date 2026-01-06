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
    
    /// 视图模型
    private var viewModel: NotesViewModel
    
    /// 工具栏代理
    private var toolbarDelegate: BaseSheetToolbarDelegate?
    
    // MARK: - 初始化
    
    /// 使用指定的视图模型初始化窗口控制器
    /// - Parameter viewModel: 笔记视图模型
    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        
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
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 窗口生命周期
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        print("回收站窗口控制器已加载")
    }
    
    // MARK: - 设置方法
    
    /// 设置工具栏
    private func setupToolbar() {
        guard let window = window else { return }
        
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
        guard let window = window else { return }
        
        // 创建SwiftUI回收站视图
        let trashView = TrashView(viewModel: viewModel)
        
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
