import AppKit

/// 段落样式枚举
/// 用于表示当前段落的样式类型
enum ParagraphStyle: String, CaseIterable {
    case heading = "heading"
    case subheading = "subheading"
    case subtitle = "subtitle"
    case body = "body"
    case orderedList = "orderedList"
    case unorderedList = "unorderedList"
    case blockQuote = "blockQuote"
    
    /// 获取对应的菜单项标签
    var menuItemTag: MenuItemTag {
        switch self {
        case .heading: return .heading
        case .subheading: return .subheading
        case .subtitle: return .subtitle
        case .body: return .bodyText
        case .orderedList: return .orderedList
        case .unorderedList: return .unorderedList
        case .blockQuote: return .blockQuote
        }
    }
    
    /// 从菜单项标签创建段落样式
    static func from(tag: MenuItemTag) -> ParagraphStyle? {
        switch tag {
        case .heading: return .heading
        case .subheading: return .subheading
        case .subtitle: return .subtitle
        case .bodyText: return .body
        case .orderedList: return .orderedList
        case .unorderedList: return .unorderedList
        case .blockQuote: return .blockQuote
        default: return nil
        }
    }
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .heading: return "大标题"
        case .subheading: return "二级标题"
        case .subtitle: return "三级标题"
        case .body: return "正文"
        case .orderedList: return "有序列表"
        case .unorderedList: return "无序列表"
        case .blockQuote: return "块引用"
        }
    }
}

/// 菜单视图模式枚举
/// 用于表示笔记列表的显示模式（菜单状态专用）
enum MenuViewMode: String, CaseIterable {
    case list = "list"
    case gallery = "gallery"
    
    /// 获取对应的菜单项标签
    var menuItemTag: MenuItemTag {
        switch self {
        case .list: return .listView
        case .gallery: return .galleryView
        }
    }
    
    /// 从菜单项标签创建视图模式
    static func from(tag: MenuItemTag) -> MenuViewMode? {
        switch tag {
        case .listView: return .list
        case .galleryView: return .gallery
        default: return nil
        }
    }
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .list: return "列表视图"
        case .gallery: return "画廊视图"
        }
    }
}

/// 菜单状态结构体
/// 用于管理菜单项的状态（启用/禁用、勾选/未勾选）
/// - Requirements: 14.4, 14.5, 14.6, 14.7
struct MenuState: Equatable {
    
    // MARK: - 段落样式状态
    
    /// 当前段落样式
    var currentParagraphStyle: ParagraphStyle = .body
    
    /// 是否启用块引用
    var isBlockQuoteEnabled: Bool = false
    
    // MARK: - 视图模式状态
    
    /// 当前视图模式
    var currentViewMode: MenuViewMode = .list
    
    // MARK: - 切换状态
    
    /// 是否启用浅色背景
    var isLightBackgroundEnabled: Bool = false
    
    /// 是否隐藏文件夹
    var isFolderHidden: Bool = false
    
    /// 是否显示笔记数量
    var isNoteCountVisible: Bool = true
    
    // MARK: - 选中状态
    
    /// 是否有选中的笔记
    var hasSelectedNote: Bool = false
    
    /// 是否有选中的文本
    var hasSelectedText: Bool = false
    
    /// 编辑器是否有焦点
    var isEditorFocused: Bool = false
    
    // MARK: - 字体样式状态
    
    /// 是否为粗体
    var isBold: Bool = false
    
    /// 是否为斜体
    var isItalic: Bool = false
    
    /// 是否有下划线
    var isUnderline: Bool = false
    
    /// 是否有删除线
    var isStrikethrough: Bool = false
    
    /// 是否高亮
    var isHighlight: Bool = false
    
    // MARK: - 文本对齐状态
    
    /// 当前文本对齐方式
    var textAlignment: NSTextAlignment = .left
    
    // MARK: - 核对清单状态
    
    /// 是否在核对清单中
    var isInChecklist: Bool = false
    
    /// 当前项是否已勾选
    var isCurrentItemChecked: Bool = false
    
    // MARK: - 初始化
    
    /// 默认初始化
    init() {}
    
    /// 完整初始化
    init(
        currentParagraphStyle: ParagraphStyle = .body,
        isBlockQuoteEnabled: Bool = false,
        currentViewMode: MenuViewMode = .list,
        isLightBackgroundEnabled: Bool = false,
        isFolderHidden: Bool = false,
        isNoteCountVisible: Bool = true,
        hasSelectedNote: Bool = false,
        hasSelectedText: Bool = false,
        isEditorFocused: Bool = false,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isStrikethrough: Bool = false,
        isHighlight: Bool = false,
        textAlignment: NSTextAlignment = .left,
        isInChecklist: Bool = false,
        isCurrentItemChecked: Bool = false
    ) {
        self.currentParagraphStyle = currentParagraphStyle
        self.isBlockQuoteEnabled = isBlockQuoteEnabled
        self.currentViewMode = currentViewMode
        self.isLightBackgroundEnabled = isLightBackgroundEnabled
        self.isFolderHidden = isFolderHidden
        self.isNoteCountVisible = isNoteCountVisible
        self.hasSelectedNote = hasSelectedNote
        self.hasSelectedText = hasSelectedText
        self.isEditorFocused = isEditorFocused
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isStrikethrough = isStrikethrough
        self.isHighlight = isHighlight
        self.textAlignment = textAlignment
        self.isInChecklist = isInChecklist
        self.isCurrentItemChecked = isCurrentItemChecked
    }
    
    // MARK: - 状态查询方法
    
    /// 检查菜单项是否应该启用
    /// - Parameter tag: 菜单项标签
    /// - Returns: 是否启用
    func shouldEnableMenuItem(for tag: MenuItemTag) -> Bool {
        // 需要选中笔记的操作
        if tag.requiresSelectedNote {
            return hasSelectedNote
        }
        
        // 需要编辑器焦点的操作
        if tag.requiresEditorFocus {
            return isEditorFocused
        }
        
        // 其他操作默认启用
        return true
    }
    
    /// 检查菜单项是否应该显示勾选状态
    /// - Parameter tag: 菜单项标签
    /// - Returns: 是否勾选
    func shouldCheckMenuItem(for tag: MenuItemTag) -> Bool {
        switch tag {
        // 段落样式（互斥选择）
        case .heading:
            return currentParagraphStyle == .heading
        case .subheading:
            return currentParagraphStyle == .subheading
        case .subtitle:
            return currentParagraphStyle == .subtitle
        case .bodyText:
            return currentParagraphStyle == .body
        case .orderedList:
            return currentParagraphStyle == .orderedList
        case .unorderedList:
            return currentParagraphStyle == .unorderedList
        case .blockQuote:
            return currentParagraphStyle == .blockQuote
            
        // 视图模式（互斥选择）
        case .listView:
            return currentViewMode == .list
        case .galleryView:
            return currentViewMode == .gallery
            
        // 切换状态
        case .lightBackground:
            return isLightBackgroundEnabled
        // 文件夹可见性和笔记数量显示：不使用勾选标记，只通过动态标题显示状态
        case .hideFolders:
            return false
        case .showNoteCount:
            return false
            
        // 字体样式
        case .bold:
            return isBold
        case .italic:
            return isItalic
        case .underline:
            return isUnderline
        case .strikethrough:
            return isStrikethrough
        case .highlight:
            return isHighlight
            
        // 文本对齐
        case .alignLeft:
            return textAlignment == .left
        case .alignCenter:
            return textAlignment == .center
        case .alignRight:
            return textAlignment == .right
            
        // 核对清单
        case .markAsChecked:
            return isCurrentItemChecked
            
        default:
            return false
        }
    }
    
    // MARK: - 状态更新方法
    
    /// 设置段落样式
    /// - Parameter style: 新的段落样式
    mutating func setParagraphStyle(_ style: ParagraphStyle) {
        currentParagraphStyle = style
    }
    
    /// 设置视图模式
    /// - Parameter mode: 新的视图模式
    mutating func setViewMode(_ mode: MenuViewMode) {
        currentViewMode = mode
    }
    
    /// 更新编辑器焦点状态
    /// - Parameter focused: 是否有焦点
    mutating func setEditorFocused(_ focused: Bool) {
        isEditorFocused = focused
    }
    
    /// 更新笔记选中状态
    /// - Parameter selected: 是否有选中笔记
    mutating func setNoteSelected(_ selected: Bool) {
        hasSelectedNote = selected
    }
    
    /// 更新文本选中状态
    /// - Parameter selected: 是否有选中文本
    mutating func setTextSelected(_ selected: Bool) {
        hasSelectedText = selected
    }
    
    /// 切换浅色背景
    mutating func toggleLightBackground() {
        isLightBackgroundEnabled.toggle()
    }
    
    /// 切换文件夹可见性
    mutating func toggleFolderVisibility() {
        isFolderHidden.toggle()
    }
    
    /// 切换笔记数量显示
    mutating func toggleNoteCount() {
        isNoteCountVisible.toggle()
    }
}

// MARK: - MenuState 通知扩展

extension MenuState {
    /// 菜单状态变化通知名称
    static let didChangeNotification = Notification.Name("MenuStateDidChange")
    
    /// 发送状态变化通知
    func postChangeNotification() {
        NotificationCenter.default.post(
            name: MenuState.didChangeNotification,
            object: nil,
            userInfo: ["state": self]
        )
    }
}

// MARK: - 菜单状态同步通知
// 注意：通知名称定义在 Sources/Extensions/Notification+MenuState.swift 中
// 以便 MiNoteLibrary 和 MiNoteMac 两个 target 都可以访问
