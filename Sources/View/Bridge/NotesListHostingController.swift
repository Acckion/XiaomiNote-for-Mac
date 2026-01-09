import AppKit
import SwiftUI
import Combine

/// 笔记列表托管控制器
/// 使用NSHostingView托管SwiftUI的NotesListView
///
/// ## 刷新策略优化
/// 
/// 本控制器采用优化的刷新策略，依赖 SwiftUI 的自动更新机制来处理大部分状态变化，
/// 只在必要时才进行强制刷新。
///
/// ### 不需要强制刷新的情况（SwiftUI 自动处理）
/// - `selectedNote` 变化：SwiftUI 通过 `@ObservedObject` 自动更新选择状态
/// - `notes` 数组变化：SwiftUI 通过 `@Published` 自动更新列表内容
///
/// ### 需要强制刷新的情况
/// - `selectedFolder` 变化：需要重新过滤笔记列表，确保显示正确的文件夹内容
/// - `searchText` 变化：需要重新过滤笔记列表，确保搜索结果正确
///
/// _Requirements: 5.2, 3.1_
class NotesListHostingController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var hostingView: NSHostingView<NotesListView>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 视图生命周期
    
    override func loadView() {
        // 创建SwiftUI视图
        let notesListView = NotesListView(viewModel: viewModel)
        
        // 创建NSHostingView
        let hostingView = NSHostingView(rootView: notesListView)
        self.hostingView = hostingView
        
        // 设置视图
        self.view = hostingView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 设置必要的刷新监听
        // 注意：selectedNote 和 notes 的变化由 SwiftUI 自动处理，不需要强制刷新
        // _Requirements: 5.2_
        setupNecessaryRefreshListeners()
    }
    
    /// 设置必要的刷新监听
    /// 
    /// 只监听需要强制刷新的状态变化：
    /// - selectedFolder：文件夹切换需要重新过滤笔记列表
    /// - searchText：搜索文本变化需要重新过滤笔记列表
    ///
    /// _Requirements: 3.1_
    private func setupNecessaryRefreshListeners() {
        // 监听文件夹变化 - 需要强制刷新以确保笔记列表正确过滤
        // _Requirements: 3.1_
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)
        
        // 监听搜索文本变化 - 需要强制刷新以确保搜索结果正确
        // _Requirements: 3.1_
        viewModel.$searchText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        
        // 确保hostingView填充整个视图
        hostingView?.frame = view.bounds
    }
    
    // MARK: - 公共方法
    
    /// 刷新SwiftUI视图
    /// 
    /// 通过重新创建 rootView 来强制刷新视图。
    /// 注意：只在必要时调用此方法，大部分情况下 SwiftUI 会自动处理更新。
    func refreshView() {
        hostingView?.rootView = NotesListView(viewModel: viewModel)
    }
}
