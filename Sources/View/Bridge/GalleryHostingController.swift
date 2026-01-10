//
//  GalleryHostingController.swift
//  MiNoteMac
//
//  画廊视图托管控制器 - 托管 GalleryView 和 ExpandedNoteView
//

import AppKit
import SwiftUI
import Combine

/// 画廊视图托管控制器
/// 
/// 使用 NSHostingView 托管 SwiftUI 的画廊视图
/// 包含 GalleryView 和 ExpandedNoteView 的切换逻辑
/// _Requirements: 4.4, 4.5, 5.1, 6.1_
@available(macOS 14.0, *)
class GalleryHostingController: NSViewController {
    
    // MARK: - 属性
    
    /// 笔记视图模型
    private var viewModel: NotesViewModel
    
    /// 视图选项管理器
    private var optionsManager: ViewOptionsManager
    
    /// 托管视图
    private var hostingView: NSHostingView<GalleryContainerView>?
    
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    /// 初始化方法
    /// - Parameters:
    ///   - viewModel: 笔记视图模型
    ///   - optionsManager: 视图选项管理器，默认使用共享实例
    init(viewModel: NotesViewModel, optionsManager: ViewOptionsManager = .shared) {
        self.viewModel = viewModel
        self.optionsManager = optionsManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 视图生命周期
    
    override func loadView() {
        // 创建 SwiftUI 视图
        let galleryContainerView = GalleryContainerView(
            viewModel: viewModel,
            optionsManager: optionsManager
        )
        
        // 创建 NSHostingView
        let hostingView = NSHostingView(rootView: galleryContainerView)
        self.hostingView = hostingView
        
        // 设置视图
        self.view = hostingView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 监听文件夹变化
        setupFolderObserver()
        
        // 监听搜索文本变化
        setupSearchObserver()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        
        // 确保 hostingView 填充整个视图
        hostingView?.frame = view.bounds
    }
    
    // MARK: - 私有方法
    
    /// 设置文件夹监听
    private func setupFolderObserver() {
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folder in
                print("[GalleryHostingController] 文件夹变化: \(folder?.name ?? "nil")")
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
                    print("[GalleryHostingController] 搜索文本变化: \(searchText)")
                }
                self?.refreshView()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 刷新 SwiftUI 视图
    func refreshView() {
        hostingView?.rootView = GalleryContainerView(
            viewModel: viewModel,
            optionsManager: optionsManager
        )
    }
}

// MARK: - GalleryContainerView

/// 画廊容器视图
/// 
/// 包含 GalleryView 和 ExpandedNoteView 的切换逻辑
/// _Requirements: 4.4, 4.5, 6.1_
@available(macOS 14.0, *)
struct GalleryContainerView: View {
    
    // MARK: - 属性
    
    /// 笔记视图模型
    @ObservedObject var viewModel: NotesViewModel
    
    /// 视图选项管理器
    @ObservedObject var optionsManager: ViewOptionsManager
    
    // MARK: - 状态
    
    /// 展开的笔记（用于画廊视图的展开模式）
    @State private var expandedNote: Note?
    
    /// 动画命名空间（用于 matchedGeometryEffect）
    @Namespace private var animation
    
    // MARK: - 视图
    
    var body: some View {
        ZStack {
            if let _ = expandedNote {
                // 展开模式：显示笔记编辑器
                // _Requirements: 6.1, 6.2_
                ExpandedNoteView(
                    viewModel: viewModel,
                    expandedNote: $expandedNote,
                    animation: animation
                )
                .transition(expandedTransition)
            } else {
                // 画廊模式：显示笔记卡片网格
                // _Requirements: 5.1_
                GalleryView(
                    viewModel: viewModel,
                    optionsManager: optionsManager,
                    expandedNote: $expandedNote,
                    animation: animation
                )
                .transition(.opacity)
            }
        }
        // 动画配置：easeInOut，时长 350ms
        // _Requirements: 6.5_
        .animation(.easeInOut(duration: 0.35), value: expandedNote?.id)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    /// 展开视图的过渡动画
    /// _Requirements: 6.4, 6.5_
    private var expandedTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        )
    }
}
