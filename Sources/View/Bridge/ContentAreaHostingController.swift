//
//  ContentAreaHostingController.swift
//  MiNoteMac
//
//  内容区域托管控制器 - 托管 ContentAreaView
//

import AppKit
import SwiftUI
import Combine

/// 内容区域托管控制器
/// 
/// 使用 NSHostingView 托管 SwiftUI 的 ContentAreaView
/// 根据视图模式（列表/画廊）显示不同的内容
/// _Requirements: 4.3, 4.4, 4.5_
@available(macOS 14.0, *)
public class ContentAreaHostingController: NSViewController {
    
    // MARK: - 属性
    
    /// 笔记视图模型
    private var viewModel: NotesViewModel
    
    /// 视图选项管理器
    private var optionsManager: ViewOptionsManager
    
    /// 托管视图
    private var hostingView: NSHostingView<ContentAreaView>?
    
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    /// 初始化方法
    /// - Parameters:
    ///   - viewModel: 笔记视图模型
    ///   - optionsManager: 视图选项管理器，默认使用共享实例
    public init(viewModel: NotesViewModel, optionsManager: ViewOptionsManager = .shared) {
        self.viewModel = viewModel
        self.optionsManager = optionsManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 视图生命周期
    
    override public func loadView() {
        // 创建 SwiftUI 视图
        let contentAreaView = ContentAreaView(
            viewModel: viewModel,
            optionsManager: optionsManager
        )
        
        // 创建 NSHostingView
        let hostingView = NSHostingView(rootView: contentAreaView)
        self.hostingView = hostingView
        
        // 设置视图
        self.view = hostingView
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        // 监听视图模式变化
        // _Requirements: 4.3, 4.4_
        setupViewModeObserver()
        
        // 监听文件夹变化
        setupFolderObserver()
        
        // 监听搜索文本变化
        setupSearchObserver()
    }
    
    override public func viewDidLayout() {
        super.viewDidLayout()
        
        // 确保 hostingView 填充整个视图
        hostingView?.frame = view.bounds
    }
    
    // MARK: - 私有方法
    
    /// 设置视图模式监听
    /// _Requirements: 4.3, 4.4_
    private func setupViewModeObserver() {
        optionsManager.$state
            .map(\.viewMode)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] viewMode in
                print("[ContentAreaHostingController] 视图模式变化: \(viewMode)")
                self?.refreshView()
            }
            .store(in: &cancellables)
    }
    
    /// 设置文件夹监听
    private func setupFolderObserver() {
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folder in
                print("[ContentAreaHostingController] 文件夹变化: \(folder?.name ?? "nil")")
                self?.refreshView()
            }
            .store(in: &cancellables)
    }
    
    /// 设置搜索监听
    private func setupSearchObserver() {
        viewModel.$searchText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] searchText in
                if !searchText.isEmpty {
                    print("[ContentAreaHostingController] 搜索文本变化: \(searchText)")
                }
                self?.refreshView()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 刷新 SwiftUI 视图
    public func refreshView() {
        hostingView?.rootView = ContentAreaView(
            viewModel: viewModel,
            optionsManager: optionsManager
        )
    }
}
