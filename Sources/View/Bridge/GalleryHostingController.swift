//
//  GalleryHostingController.swift
//  MiNoteMac
//
//  画廊视图托管控制器 - 托管 GalleryView 和 ExpandedNoteView
//

import AppKit
import Combine
import SwiftUI

/// 画廊视图托管控制器
///
/// 使用 NSHostingView 托管 SwiftUI 的画廊视图
/// 包含 GalleryView 和 ExpandedNoteView 的切换逻辑
@available(macOS 14.0, *)
class GalleryHostingController: NSViewController {

    // MARK: - 属性

    /// 笔记视图模型
    private var viewModel: NotesViewModel

    /// 应用协调器（用于新架构视图）
    private var coordinator: AppCoordinator?

    /// 窗口状态（用于新架构视图）
    private var windowState: WindowState?

    /// 视图选项管理器
    private var optionsManager: ViewOptionsManager

    /// 托管视图
    private var hostingView: NSHostingView<GalleryContainerView>?

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    /// 初始化方法（旧架构）
    /// - Parameters:
    ///   - viewModel: 笔记视图模型
    ///   - optionsManager: 视图选项管理器，默认使用共享实例
    init(viewModel: NotesViewModel, optionsManager: ViewOptionsManager = .shared) {
        self.viewModel = viewModel
        self.optionsManager = optionsManager
        super.init(nibName: nil, bundle: nil)
    }

    /// 初始化方法（新架构）
    /// - Parameters:
    ///   - coordinator: 应用协调器
    ///   - windowState: 窗口状态
    ///   - optionsManager: 视图选项管理器，默认使用共享实例
    init(coordinator: AppCoordinator, windowState: WindowState, optionsManager: ViewOptionsManager = .shared) {
        self.coordinator = coordinator
        self.windowState = windowState
        self.viewModel = coordinator.notesViewModel
        self.optionsManager = optionsManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 视图生命周期

    override func loadView() {
        // 创建 SwiftUI 视图
        let galleryContainerView = GalleryContainerView(
            viewModel: viewModel,
            coordinator: coordinator,
            windowState: windowState,
            optionsManager: optionsManager
        )

        // 创建 NSHostingView
        let hostingView = NSHostingView(rootView: galleryContainerView)
        self.hostingView = hostingView

        // 设置视图
        view = hostingView
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
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)
    }

    /// 设置搜索监听
    private func setupSearchObserver() {
        viewModel.$searchText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)
    }

    // MARK: - 公共方法

    /// 刷新 SwiftUI 视图
    func refreshView() {
        hostingView?.rootView = GalleryContainerView(
            viewModel: viewModel,
            coordinator: coordinator,
            windowState: windowState,
            optionsManager: optionsManager
        )
    }
}

// MARK: - GalleryContainerView

/// 画廊容器视图
///
/// 包含 GalleryView 和 ExpandedNoteView 的切换逻辑
@available(macOS 14.0, *)
struct GalleryContainerView: View {

    // MARK: - 属性

    /// 笔记视图模型
    @ObservedObject var viewModel: NotesViewModel

    /// 应用协调器（可选，用于新架构）
    var coordinator: AppCoordinator?

    /// 窗口状态（可选，用于新架构）
    var windowState: WindowState?

    /// 视图选项管理器
    @ObservedObject var optionsManager: ViewOptionsManager

    // MARK: - 状态

    /// 展开的笔记（用于画廊视图的展开模式）
    @State private var expandedNote: Note?

    /// 动画命名空间（用于 matchedGeometryEffect）
    @Namespace private var animation

    // MARK: - 视图

    var body: some View {
        contentView
            .animation(.easeInOut(duration: 0.35), value: expandedNote?.id)
            .background(Color(NSColor.windowBackgroundColor))
            .onChange(of: expandedNote?.id) { _, newValue in
                DispatchQueue.main.async {
                    viewModel.isGalleryExpanded = (newValue != nil)
                }
            }
            .onChange(of: optionsManager.viewMode) { _, newMode in
                handleViewModeChange(newMode)
            }
            .onReceive(NotificationCenter.default.publisher(for: .backToGalleryRequested)) { _ in
                handleBackToGallery()
            }
    }

    /// 将内容视图提取为单独的计算属性
    private var contentView: some View {
        ZStack {
            if let _ = expandedNote {
                // 展开模式：显示笔记编辑器
                if let coordinator, let windowState {
                    // 新架构：使用 coordinator 和 windowState
                    ExpandedNoteView(
                        coordinator: coordinator,
                        windowState: windowState,
                        animation: animation
                    )
                    .transition(expandedTransition)
                } else {
                    // 旧架构：显示错误提示
                    Text("展开视图不可用")
                        .foregroundColor(.secondary)
                }
            } else {
                // 画廊模式：显示笔记卡片网格
                if let coordinator, let windowState {
                    // 新架构：使用 coordinator 和 windowState
                    GalleryView(
                        coordinator: coordinator,
                        windowState: windowState,
                        optionsManager: optionsManager,
                        animation: animation
                    )
                    .transition(.opacity)
                } else {
                    // 旧架构：显示错误提示
                    Text("画廊视图不可用")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 处理视图模式变化
    private func handleViewModeChange(_ newMode: ViewMode) {
        if newMode == .list {
            expandedNote = nil
            DispatchQueue.main.async {
                viewModel.isGalleryExpanded = false
            }
        }
    }

    /// 处理返回画廊视图
    private func handleBackToGallery() {
        withAnimation(.easeInOut(duration: 0.35)) {
            expandedNote = nil
        }
    }

    /// 展开视图的过渡动画
    private var expandedTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        )
    }
}
