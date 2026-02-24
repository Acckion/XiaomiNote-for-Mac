import AppKit
import Combine
import SwiftUI

/// 侧边栏托管控制器
/// 使用NSHostingView托管SwiftUI的SidebarView
public class SidebarHostingController: NSViewController {

    // MARK: - 属性

    private let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 视图生命周期

    override public func loadView() {
        let sidebarView = SidebarView(coordinator: coordinator)
            .environmentObject(ViewOptionsManager.shared)
        view = NSHostingView(rootView: sidebarView)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        coordinator.folderState.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)

        coordinator.folderState.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshView()
            }
            .store(in: &cancellables)
    }

    // MARK: - 公共方法

    /// 刷新SwiftUI视图
    func refreshView() {
        let sidebarView = SidebarView(coordinator: coordinator)
            .environmentObject(ViewOptionsManager.shared)
        view = NSHostingView(rootView: sidebarView)
    }
}
