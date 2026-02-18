import AppKit
@preconcurrency import Combine

/// 自定义搜索字段，简化版本 - 不再显示筛选标签
@MainActor
class CustomSearchField: NSSearchField {

    // MARK: - 属性

    /// 视图模型
    weak var viewModel: NotesViewModel?

    /// Combine订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 设置搜索框属性
        sendsSearchStringImmediately = false
        sendsWholeSearchString = true
        bezelStyle = .roundedBezel
        controlSize = .regular

        // 监听文本变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: self
        )
    }

    /// 设置视图模型
    func setViewModel(_ viewModel: NotesViewModel) {
        self.viewModel = viewModel

        // 监听搜索文本变化
        viewModel.$searchText
            .receive(on: RunLoop.main)
            .sink { [weak self] searchText in
                // 直接更新搜索框文本
                if self?.stringValue != searchText {
                    self?.stringValue = searchText
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 事件处理

    /// 文本变化通知
    @objc override func textDidChange(_: Notification) {
        // 获取当前文本
        let currentText = stringValue

        // 更新视图模型的搜索文本
        viewModel?.searchText = currentText

        print("[CustomSearchField] 文本变化: '\(currentText)'")
    }

    // MARK: - 焦点处理

    /// 当搜索框成为第一响应者时调用
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            print("[CustomSearchField] 搜索框成为第一响应者")
            // 通知委托搜索框开始编辑
            // 使用异步确保UI更新完成后再通知
            DispatchQueue.main.async {
                self.delegate?.controlTextDidBeginEditing?(Notification(name: NSText.didBeginEditingNotification, object: self))
            }
        }
        return result
    }

    // MARK: - 鼠标事件处理

    /// 处理鼠标点击事件
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        print("[CustomSearchField] 鼠标点击搜索框")
    }

    // MARK: - 清理

    deinit {
        NotificationCenter.default.removeObserver(self)
        // 注意：在@MainActor类的deinit中不能访问隔离的属性
        // cancellables会在对象销毁时自动清理
    }
}
