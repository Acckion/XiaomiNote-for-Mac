import AppKit
import SwiftUI

/// 笔记列表托管控制器
/// 
/// 负责将 SwiftUI 的 NotesListView 嵌入到 AppKit 的窗口系统中。
/// 
/// **布局说明**:
/// - 笔记列表内容不会延伸至工具栏区域
/// - 使用 `.safeAreaInset` 确保内容正确显示在工具栏下方
/// - 支持分组模式（固定分组标题）和平铺模式
class NotesListHostingController: NSHostingController<NotesListView> {
    
    private let coordinator: AppCoordinator
    private let windowState: WindowState
    
    init(coordinator: AppCoordinator, windowState: WindowState) {
        self.coordinator = coordinator
        self.windowState = windowState
        super.init(rootView: NotesListView(
            coordinator: coordinator,
            windowState: windowState,
            optionsManager: .shared
        ))
        
        // 禁止视图延伸到安全区域（工具栏下方）
        self.view.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 确保视图不会延伸到工具栏区域
        if let scrollView = findScrollView(in: view) {
            scrollView.automaticallyAdjustsContentInsets = true
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
    }
    
    /// 递归查找 NSScrollView
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}
