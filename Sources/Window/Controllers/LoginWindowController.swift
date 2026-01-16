//
//  LoginWindowController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/3.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit
import SwiftUI

/// 登录窗口控制器
/// 负责管理登录窗口
public class LoginWindowController: NSWindowController {
    
    // MARK: - 属性
    
    /// 视图模型
    private var viewModel: NotesViewModel?
    
    /// 工具栏代理
    private var toolbarDelegate: BaseSheetToolbarDelegate?
    
    // MARK: - 初始化
    
    /// 使用指定的视图模型初始化窗口控制器
    /// - Parameter viewModel: 笔记视图模型
    public init(viewModel: NotesViewModel? = nil) {
        self.viewModel = viewModel
        
        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        // 设置窗口
        window.title = "登录小米账号"
        window.titleVisibility = .visible
        window.setFrameAutosaveName("LoginWindow")
        
        // 设置窗口内容
        setupWindowContent()
        
        // 设置工具栏
        setupToolbar()
        
        // 设置窗口最小尺寸
        window.minSize = NSSize(width: 600, height: 400)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 窗口生命周期
    
    public override func windowDidLoad() {
        super.windowDidLoad()
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
        
        let toolbar = NSToolbar(identifier: "LoginWindowToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    
    /// 设置窗口内容
    private func setupWindowContent() {
        guard let window = window else { return }
        
        // 创建SwiftUI登录视图
        let loginView = LoginView(viewModel: viewModel ?? NotesViewModel())
        
        // 使用NSHostingController包装SwiftUI视图
        let hostingController = NSHostingController(rootView: loginView)
        
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
