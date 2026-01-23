//
//  NoteDetailHostingController.swift
//  MiNoteMac
//
//  笔记详情托管控制器 - 托管 NoteDetailView
//

import AppKit
import SwiftUI
import Combine

/// 笔记详情托管控制器
/// 
/// 使用 NSHostingView 托管 SwiftUI 的 NoteDetailView
/// 用于三栏布局中的第三栏（编辑器区域）
class NoteDetailHostingController: NSViewController {
    
    // MARK: - 属性
    
    /// 应用协调器
    private let coordinator: AppCoordinator
    
    /// 窗口状态
    private let windowState: WindowState
    
    /// 托管视图
    private var hostingView: NSHostingView<NoteDetailView>?
    
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    /// 初始化方法
    /// - Parameters:
    ///   - coordinator: 应用协调器
    ///   - windowState: 窗口状态
    init(coordinator: AppCoordinator, windowState: WindowState) {
        self.coordinator = coordinator
        self.windowState = windowState
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 视图生命周期
    
    override func loadView() {
        // 创建 SwiftUI 视图
        let noteDetailView = NoteDetailView(coordinator: coordinator, windowState: windowState)
        
        // 创建 NSHostingView
        let hostingView = NSHostingView(rootView: noteDetailView)
        self.hostingView = hostingView
        
        // 设置视图
        self.view = hostingView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 监听选中笔记变化
        setupSelectedNoteObserver()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        
        // 确保 hostingView 填充整个视图
        hostingView?.frame = view.bounds
    }
    
    // MARK: - 私有方法
    
    /// 设置选中笔记监听
    private func setupSelectedNoteObserver() {
        windowState.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 刷新 SwiftUI 视图
    func refreshView() {
        hostingView?.rootView = NoteDetailView(coordinator: coordinator, windowState: windowState)
    }
}
