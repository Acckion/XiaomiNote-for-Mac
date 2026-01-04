import AppKit
import SwiftUI
import Combine

/// 笔记列表托管控制器
/// 使用NSHostingView托管SwiftUI的NotesListView
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
        
        // 监听视图模型变化，确保SwiftUI视图更新
        viewModel.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 强制刷新SwiftUI视图
                self?.hostingView?.rootView = NotesListView(viewModel: self?.viewModel ?? NotesViewModel())
            }
            .store(in: &cancellables)
        
        viewModel.$searchText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 强制刷新SwiftUI视图
                self?.hostingView?.rootView = NotesListView(viewModel: self?.viewModel ?? NotesViewModel())
            }
            .store(in: &cancellables)
        
        // 监听笔记列表变化
        viewModel.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 强制刷新SwiftUI视图
                self?.hostingView?.rootView = NotesListView(viewModel: self?.viewModel ?? NotesViewModel())
            }
            .store(in: &cancellables)
        
        // 监听文件夹变化
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 强制刷新SwiftUI视图
                self?.hostingView?.rootView = NotesListView(viewModel: self?.viewModel ?? NotesViewModel())
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
    func refreshView() {
        hostingView?.rootView = NotesListView(viewModel: viewModel)
    }
}
