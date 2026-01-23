import AppKit
import Combine
import SwiftUI

/// 笔记详情视图控制器
/// 显示和编辑选中的笔记
class NoteDetailViewController: NSViewController {
    
    // MARK: - 属性
    
    private let coordinator: AppCoordinator
    private let windowState: WindowState
    private var hostingController: NSHostingController<NoteDetailView>?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
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
        // 创建主视图
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 创建SwiftUI视图
        let noteDetailView = NoteDetailView(coordinator: coordinator, windowState: windowState)
        
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
        windowState.$selectedNote
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
    
    // MARK: - 窗口状态管理
    
    /// 获取可保存的窗口状态
    /// - Returns: 笔记详情窗口状态对象
    public func savableWindowState() -> NoteDetailWindowState {
        // 获取编辑器内容（从原生编辑器导出）
        let editorContent = coordinator.notesViewModel.nativeEditorContext.exportToXML()
        
        // 滚动位置和光标位置暂时设为0
        let scrollPosition = 0.0
        let cursorPosition = 0
        
        let state = NoteDetailWindowState(
            editorContent: editorContent,
            scrollPosition: scrollPosition,
            cursorPosition: cursorPosition
        )
        
        print("[NoteDetailViewController] 笔记详情状态已保存: \(state)")
        return state
    }
    
    /// 恢复窗口状态
    /// - Parameter state: 要恢复的笔记详情窗口状态
    public func restoreWindowState(_ state: NoteDetailWindowState) {
        print("[NoteDetailViewController] 恢复笔记详情状态: \(state)")
        
        // 恢复编辑器内容
        if let editorContent = state.editorContent {
            coordinator.notesViewModel.nativeEditorContext.loadFromXML(editorContent)
        }
        
        print("[NoteDetailViewController] 笔记详情状态恢复完成")
    }
}
