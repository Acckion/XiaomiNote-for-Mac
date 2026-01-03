import AppKit
import SwiftUI
import Combine

/// 侧边栏托管控制器
/// 使用NSHostingView托管SwiftUI的SidebarView
public class SidebarHostingController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var hostingView: NSHostingView<SidebarView>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 视图生命周期
    
    override public func loadView() {
        // 创建SwiftUI视图
        let sidebarView = SidebarView(viewModel: viewModel)
        
        // 创建NSHostingView
        let hostingView = NSHostingView(rootView: sidebarView)
        self.hostingView = hostingView
        
        // 设置视图
        self.view = hostingView
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        // 监听视图模型变化，确保SwiftUI视图更新
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 强制刷新SwiftUI视图
                self?.hostingView?.rootView = SidebarView(viewModel: self?.viewModel ?? NotesViewModel())
            }
            .store(in: &cancellables)
        
        // 监听文件夹列表变化
        viewModel.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 强制刷新SwiftUI视图
                self?.hostingView?.rootView = SidebarView(viewModel: self?.viewModel ?? NotesViewModel())
            }
            .store(in: &cancellables)
    }
    
    override public func viewDidLayout() {
        super.viewDidLayout()
        
        // 确保hostingView填充整个视图
        hostingView?.frame = view.bounds
    }
    
    // MARK: - 公共方法
    
    /// 刷新SwiftUI视图
    func refreshView() {
        hostingView?.rootView = SidebarView(viewModel: viewModel)
    }
}
