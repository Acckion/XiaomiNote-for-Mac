import AppKit
import Combine

/// 详情视图控制器
/// 显示选中的笔记内容
class DetailViewController: NSViewController {
    
    private var viewModel: NotesViewModel
    private var textView: NSTextView!
    private var titleField: NSTextField!
    
    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        // 创建主视图
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // 创建标题字段
        titleField = NSTextField()
        titleField.isEditable = true
        titleField.isBordered = false
        titleField.font = NSFont.boldSystemFont(ofSize: 18)
        titleField.placeholderString = "笔记标题"
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.focusRingType = .none
        view.addSubview(titleField)
        
        // 创建分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)
        
        // 创建滚动视图和文本视图
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView
        
        // 设置约束
        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            separator.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 监听选中的笔记变化
        viewModel.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.updateContent(with: note)
            }
            .store(in: &cancellables)
        
        // 设置文本变化监听
        titleField.delegate = self
        textView.delegate = self
    }
    
    private func updateContent(with note: Note?) {
        if let note = note {
            titleField.stringValue = note.title
            textView.string = note.content
            titleField.isEnabled = true
            textView.isEditable = true
        } else {
            titleField.stringValue = ""
            textView.string = "请从左侧选择一篇笔记"
            titleField.isEnabled = false
            textView.isEditable = false
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - NSTextFieldDelegate

extension DetailViewController: NSTextFieldDelegate {
    
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let note = viewModel.selectedNote else { return }
        
        // 更新笔记标题
        let newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty && newTitle != note.title {
            print("更新笔记标题: \(newTitle)")
            // 在实际应用中，这里会调用viewModel更新笔记
        }
    }
}

// MARK: - NSTextViewDelegate

extension DetailViewController: NSTextViewDelegate {
    
    func textDidEndEditing(_ notification: Notification) {
        guard let note = viewModel.selectedNote else { return }
        
        // 更新笔记内容
        let newContent = textView.string
        if newContent != note.content {
            print("更新笔记内容")
            // 在实际应用中，这里会调用viewModel更新笔记
        }
    }
}
