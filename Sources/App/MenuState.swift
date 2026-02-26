import AppKit

/// 段落样式枚举
/// 用于表示当前段落的样式类型
enum ParagraphStyle: String, CaseIterable {
    case heading
    case subheading
    case subtitle
    case body
    case orderedList
    case unorderedList
    case blockQuote

    /// 获取对应的菜单项标签
    var menuItemTag: MenuItemTag {
        switch self {
        case .heading: .heading
        case .subheading: .subheading
        case .subtitle: .subtitle
        case .body: .bodyText
        case .orderedList: .orderedList
        case .unorderedList: .unorderedList
        case .blockQuote: .blockQuote
        }
    }

    /// 从菜单项标签创建段落样式
    static func from(tag: MenuItemTag) -> ParagraphStyle? {
        switch tag {
        case .heading: .heading
        case .subheading: .subheading
        case .subtitle: .subtitle
        case .bodyText: .body
        case .orderedList: .orderedList
        case .unorderedList: .unorderedList
        case .blockQuote: .blockQuote
        default: nil
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .heading: "大标题"
        case .subheading: "二级标题"
        case .subtitle: "三级标题"
        case .body: "正文"
        case .orderedList: "有序列表"
        case .unorderedList: "无序列表"
        case .blockQuote: "块引用"
        }
    }
}

/// 菜单视图模式枚举
/// 用于表示笔记列表的显示模式（菜单状态专用）
enum MenuViewMode: String, CaseIterable {
    case list
    case gallery

    /// 获取对应的菜单项标签
    var menuItemTag: MenuItemTag {
        switch self {
        case .list: .listView
        case .gallery: .galleryView
        }
    }

    /// 从菜单项标签创建视图模式
    static func from(tag: MenuItemTag) -> MenuViewMode? {
        switch tag {
        case .listView: .list
        case .galleryView: .gallery
        default: nil
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .list: "列表视图"
        case .gallery: "画廊视图"
        }
    }
}

/// 菜单状态结构体
/// 用于管理菜单项的状态（启用/禁用、勾选/未勾选）
struct MenuState: Equatable {

    // MARK: - 段落样式状态

    /// 当前段落样式
    var currentParagraphStyle: ParagraphStyle = .body

    /// 是否启用块引用
    var isBlockQuoteEnabled = false

    // MARK: - 视图模式状态

    /// 当前视图模式
    var currentViewMode: MenuViewMode = .list

    // MARK: - 切换状态

    /// 是否隐藏文件夹
    var isFolderHidden = false

    /// 是否显示笔记数量
    var isNoteCountVisible = true

    // MARK: - 选中状态

    /// 是否有选中的笔记
    var hasSelectedNote = false

    /// 是否有选中的文本
    var hasSelectedText = false

    /// 编辑器是否有焦点
    var isEditorFocused = false

    // MARK: - 字体样式状态

    /// 是否为粗体
    var isBold = false

    /// 是否为斜体
    var isItalic = false

    /// 是否有下划线
    var isUnderline = false

    /// 是否有删除线
    var isStrikethrough = false

    /// 是否高亮
    var isHighlight = false

    // MARK: - 文本对齐状态

    /// 当前文本对齐方式
    var textAlignment: NSTextAlignment = .left

    // MARK: - 核对清单状态

    /// 是否在核对清单中
    var isInChecklist = false

    /// 当前项是否已勾选
    var isCurrentItemChecked = false

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
        if let result = checkParagraphStyle(for: tag) { return result }
        if let result = checkViewMode(for: tag) { return result }
        if let result = checkFontStyle(for: tag) { return result }
        if let result = checkAlignment(for: tag) { return result }
        return checkOtherState(for: tag)
    }

    /// 检查段落样式勾选状态
    private func checkParagraphStyle(for tag: MenuItemTag) -> Bool? {
        switch tag {
        case .heading: currentParagraphStyle == .heading
        case .subheading: currentParagraphStyle == .subheading
        case .subtitle: currentParagraphStyle == .subtitle
        case .bodyText: currentParagraphStyle == .body
        case .orderedList: currentParagraphStyle == .orderedList
        case .unorderedList: currentParagraphStyle == .unorderedList
        case .blockQuote: currentParagraphStyle == .blockQuote
        default: nil
        }
    }

    /// 检查视图模式勾选状态
    private func checkViewMode(for tag: MenuItemTag) -> Bool? {
        switch tag {
        case .listView: currentViewMode == .list
        case .galleryView: currentViewMode == .gallery
        default: nil
        }
    }

    /// 检查字体样式勾选状态
    private func checkFontStyle(for tag: MenuItemTag) -> Bool? {
        switch tag {
        case .bold: isBold
        case .italic: isItalic
        case .underline: isUnderline
        case .strikethrough: isStrikethrough
        case .highlight: isHighlight
        default: nil
        }
    }

    /// 检查文本对齐勾选状态
    private func checkAlignment(for tag: MenuItemTag) -> Bool? {
        switch tag {
        case .alignLeft: textAlignment == .left
        case .alignCenter: textAlignment == .center
        case .alignRight: textAlignment == .right
        default: nil
        }
    }

    /// 检查其他状态勾选
    private func checkOtherState(for tag: MenuItemTag) -> Bool {
        switch tag {
        case .hideFolders: false
        case .showNoteCount: false
        default: false
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
