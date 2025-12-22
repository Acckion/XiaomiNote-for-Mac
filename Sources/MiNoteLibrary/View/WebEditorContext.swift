import SwiftUI
import Combine

/// Web编辑器上下文，管理编辑器状态和格式操作
class WebEditorContext: ObservableObject {
    @Published var content: String = ""
    @Published var isEditorReady: Bool = false
    @Published var hasSelection: Bool = false
    @Published var selectedText: String = ""
    
    // 格式状态
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var isStrikethrough: Bool = false
    @Published var isHighlighted: Bool = false
    @Published var textAlignment: TextAlignment = .leading
    @Published var headingLevel: Int? = nil
    
    // 操作闭包，用于执行编辑器操作
    var executeFormatActionClosure: ((String, String?) -> Void)?
    var insertImageClosure: ((String, String) -> Void)?
    var getCurrentContentClosure: ((@escaping (String) -> Void) -> Void)?
    var forceSaveContentClosure: ((@escaping () -> Void) -> Void)?
    var undoClosure: (() -> Void)?
    var redoClosure: (() -> Void)?
    var openWebInspectorClosure: (() -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 监听内容变化
        $content
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newContent in
                self?.handleContentChanged(newContent)
            }
            .store(in: &cancellables)
    }
    
    // 处理内容变化
    private func handleContentChanged(_ content: String) {
        // 这里可以添加内容变化后的处理逻辑
        // 例如自动保存、同步等
        print("内容已更新，长度: \(content.count)")
    }
    
    // 格式操作
    func toggleBold() {
        executeFormatActionClosure?("bold", nil)
        isBold.toggle()
    }
    
    func toggleItalic() {
        executeFormatActionClosure?("italic", nil)
        isItalic.toggle()
    }
    
    func toggleUnderline() {
        executeFormatActionClosure?("underline", nil)
        isUnderline.toggle()
    }
    
    func toggleStrikethrough() {
        executeFormatActionClosure?("strikethrough", nil)
        isStrikethrough.toggle()
    }
    
    func toggleHighlight() {
        executeFormatActionClosure?("highlight", nil)
        isHighlighted.toggle()
    }
    
    func setTextAlignment(_ alignment: TextAlignment) {
        let alignmentValue: String
        switch alignment {
        case .leading:
            alignmentValue = "left"
        case .center:
            alignmentValue = "center"
        case .trailing:
            alignmentValue = "right"
        default:
            alignmentValue = "left"
        }
        
        executeFormatActionClosure?("textAlignment", alignmentValue)
        textAlignment = alignment
    }
    
    func setHeadingLevel(_ level: Int?) {
        if let level = level {
            executeFormatActionClosure?("heading", "\(level)")
            headingLevel = level
        } else {
            // 清除标题格式
            executeFormatActionClosure?("heading", "0")
            headingLevel = nil
        }
    }
    
    // 列表操作
    func toggleBulletList() {
        executeFormatActionClosure?("bulletList", nil)
    }
    
    func toggleOrderList() {
        executeFormatActionClosure?("orderList", nil)
    }
    
    func insertCheckbox() {
        executeFormatActionClosure?("checkbox", nil)
    }
    
    func insertHorizontalRule() {
        executeFormatActionClosure?("horizontalRule", nil)
    }
    
    func toggleQuote() {
        executeFormatActionClosure?("quote", nil)
    }
    
    // 缩进操作
    func increaseIndent() {
        executeFormatActionClosure?("indent", "increase")
    }
    
    func decreaseIndent() {
        executeFormatActionClosure?("indent", "decrease")
    }
    
    // 图片操作
    func insertImage(_ imageUrl: String, altText: String = "图片") {
        insertImageClosure?(imageUrl, altText)
    }
    
    // 获取当前内容
    func getCurrentContent(completion: @escaping (String) -> Void) {
        getCurrentContentClosure?(completion)
    }
    
    // 强制保存当前内容（用于切换笔记前）
    func forceSaveContent(completion: @escaping () -> Void) {
        forceSaveContentClosure?(completion)
    }
    
    // 撤销操作
    func undo() {
        undoClosure?()
    }
    
    // 重做操作
    func redo() {
        redoClosure?()
    }
    
    // 编辑器准备就绪
    func editorReady() {
        isEditorReady = true
        print("Web编辑器上下文：编辑器已准备就绪")
    }
    
    // 更新选择状态
    func updateSelection(hasSelection: Bool, selectedText: String = "") {
        self.hasSelection = hasSelection
        self.selectedText = selectedText
    }
    
    // 打开Web Inspector
    func openWebInspector() {
        openWebInspectorClosure?()
    }
}

// 扩展TextAlignment以便与字符串转换
extension TextAlignment {
    var stringValue: String {
        switch self {
        case .leading:
            return "left"
        case .center:
            return "center"
        case .trailing:
            return "right"
        default:
            return "left"
        }
    }
    
    static func fromString(_ value: String) -> TextAlignment {
        switch value.lowercased() {
        case "center":
            return .center
        case "right":
            return .trailing
        default:
            return .leading
        }
    }
}
