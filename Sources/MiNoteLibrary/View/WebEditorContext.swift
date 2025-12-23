import SwiftUI
import Combine

/// Web编辑器上下文，管理编辑器状态和格式操作
class WebEditorContext: ObservableObject {
    @Published var content: String = ""
    @Published var isEditorReady: Bool = false
    @Published var hasSelection: Bool = false
    @Published var selectedText: String = ""
    
    // 格式状态（参考 CKEditor 5：状态由编辑器同步，不手动管理）
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var isStrikethrough: Bool = false
    @Published var isHighlighted: Bool = false
    @Published var textAlignment: TextAlignment = .leading
    @Published var headingLevel: Int? = nil
    @Published var listType: String? = nil  // 'bullet' 或 'order' 或 nil
    @Published var isInQuote: Bool = false  // 是否在引用块中
    
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
    
    // 格式操作（参考 CKEditor 5：不手动切换状态，状态由编辑器同步）
    func toggleBold() {
        executeFormatActionClosure?("bold", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleItalic() {
        executeFormatActionClosure?("italic", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleUnderline() {
        executeFormatActionClosure?("underline", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleStrikethrough() {
        executeFormatActionClosure?("strikethrough", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
    }
    
    func toggleHighlight() {
        executeFormatActionClosure?("highlight", nil)
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动切换
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
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动设置
    }
    
    func setHeadingLevel(_ level: Int?) {
        if let level = level {
            executeFormatActionClosure?("heading", "\(level)")
        } else {
            // 清除标题格式
            executeFormatActionClosure?("heading", "0")
        }
        // 状态由编辑器通过 formatStateChanged 消息同步，不在这里手动设置
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
