import AppKit
import Combine
import SwiftUI

/// 笔记详情视图控制器
/// 显示和编辑选中的笔记
class NoteDetailViewController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var hostingController: NSHostingController<NoteDetailView>?
    
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
        // 创建主视图
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 创建SwiftUI视图
        let noteDetailView = NoteDetailView(viewModel: viewModel)
        
        // 创建托管控制器
        hostingController = NSHostingController(rootView: noteDetailView)
        
        guard let hostingView = hostingController?.view else { return }
        
        // 添加托管视图
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        
        // 设置约束
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 监听选中的笔记变化
        viewModel.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.updateTitle(with: note)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 私有方法
    
    private func updateTitle(with note: Note?) {
        if let note = note {
            self.title = note.title
        } else {
            self.title = "无选中笔记"
        }
    }
}
