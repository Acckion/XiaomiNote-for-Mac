//
//  NativeEditorContext.swift
//  MiNoteMac
//
//  原生编辑器上下文 - 管理编辑器状态、格式应用和用户交互
//  需求: 9.1, 9.2, 9.3, 9.4, 9.5
//

import SwiftUI
import Combine
import AppKit

/// 文本格式类型枚举
enum TextFormat: CaseIterable, Hashable {
    case bold           // 加粗
    case italic         // 斜体
    case underline      // 下划线
    case strikethrough  // 删除线
    case highlight      // 高亮
    case heading1       // 大标题
    case heading2       // 二级标题
    case heading3       // 三级标题
    case alignCenter    // 居中对齐
    case alignRight     // 右对齐
    case bulletList     // 无序列表
    case numberedList   // 有序列表
    case checkbox       // 复选框
    case quote          // 引用块
    case horizontalRule // 分割线
    
    /// 格式的显示名称
    var displayName: String {
        switch self {
        case .bold: return "加粗"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .highlight: return "高亮"
        case .heading1: return "大标题"
        case .heading2: return "二级标题"
        case .heading3: return "三级标题"
        case .alignCenter: return "居中"
        case .alignRight: return "右对齐"
        case .bulletList: return "无序列表"
        case .numberedList: return "有序列表"
        case .checkbox: return "复选框"
        case .quote: return "引用"
        case .horizontalRule: return "分割线"
        }
    }
    
    /// 格式的快捷键
    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .bold: return "b"
        case .italic: return "i"
        case .underline: return "u"
        default: return nil
        }
    }
    
    /// 是否需要 Command 修饰键
    var requiresCommand: Bool {
        switch self {
        case .bold, .italic, .underline: return true
        default: return false
        }
    }
    
    /// 是否是块级格式（影响整行）
    var isBlockFormat: Bool {
        switch self {
        case .heading1, .heading2, .heading3, .alignCenter, .alignRight,
             .bulletList, .numberedList, .checkbox, .quote, .horizontalRule:
            return true
        default:
            return false
        }
    }
    
    /// 是否是内联格式（只影响选中文本）
    var isInlineFormat: Bool {
        return !isBlockFormat
    }
}

/// 特殊元素类型枚举
enum SpecialElement: Equatable {
    case checkbox(checked: Bool, level: Int)
    case horizontalRule
    case bulletPoint(indent: Int)
    case numberedItem(number: Int, indent: Int)
    case quote(content: String)
    case image(fileId: String?, src: String?)
    
    /// 元素的显示名称
    var displayName: String {
        switch self {
        case .checkbox: return "复选框"
        case .horizontalRule: return "分割线"
        case .bulletPoint: return "项目符号"
        case .numberedItem: return "编号列表"
        case .quote: return "引用块"
        case .image: return "图片"
        }
    }
}

/// 编辑器类型枚举
enum EditorType: String, CaseIterable, Identifiable, Codable {
    case native = "native"
    case web = "web"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .native:
            return "原生编辑器"
        case .web:
            return "Web 编辑器"
        }
    }
    
    var description: String {
        switch self {
        case .native:
            return "使用 SwiftUI 和 NSTextView 实现的原生编辑器，提供最佳的 macOS 体验"
        case .web:
            return "基于 Web 技术的编辑器，功能完整且稳定"
        }
    }
    
    var icon: String {
        switch self {
        case .native:
            return "doc.text"
        case .web:
            return "globe"
        }
    }
    
    var features: [String] {
        switch self {
        case .native:
            return [
                "原生 macOS 体验",
                "更好的性能",
                "系统级快捷键支持",
                "无缝的复制粘贴",
                "原生滚动和缩放"
            ]
        case .web:
            return [
                "功能完整",
                "跨平台兼容",
                "稳定可靠",
                "丰富的编辑功能",
                "成熟的实现"
            ]
        }
    }
    
    var minimumSystemVersion: String {
        switch self {
        case .native:
            return "macOS 13.0"
        case .web:
            return "macOS 10.15"
        }
    }
}

/// 原生编辑器上下文 - 管理编辑器状态和操作
/// 需求: 9.1, 9.2, 9.3, 9.4, 9.5
@MainActor
class NativeEditorContext: ObservableObject {
    // MARK: - Published Properties
    
    /// 当前应用的格式集合
    @Published var currentFormats: Set<TextFormat> = []
    
    /// 光标位置
    @Published var cursorPosition: Int = 0
    
    /// 选择范围
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)
    
    /// 编辑器是否获得焦点
    @Published var isEditorFocused: Bool = false
    
    /// 当前编辑的内容（NSAttributedString 用于与 NSTextView 交互）
    @Published var attributedText: AttributedString = AttributedString()
    
    /// 当前编辑的 NSAttributedString（用于 NSTextView）
    @Published var nsAttributedText: NSAttributedString = NSAttributedString()
    
    /// 当前检测到的特殊元素类型
    @Published var currentSpecialElement: SpecialElement? = nil
    
    /// 当前缩进级别
    @Published var currentIndentLevel: Int = 1
    
    /// 当前文件夹 ID（用于图片存储）
    @Published var currentFolderId: String? = nil
    
    /// 是否有未保存的更改
    @Published var hasUnsavedChanges: Bool = false
    
    /// 工具栏按钮状态
    @Published var toolbarButtonStates: [TextFormat: Bool] = [:]
    
    // MARK: - Private Properties
    
    /// 格式变化发布者
    private let formatChangeSubject = PassthroughSubject<TextFormat, Never>()
    
    /// 特殊元素插入发布者
    private let specialElementSubject = PassthroughSubject<SpecialElement, Never>()
    
    /// 内容变化发布者
    private let contentChangeSubject = PassthroughSubject<NSAttributedString, Never>()
    
    /// 选择变化发布者
    private let selectionChangeSubject = PassthroughSubject<NSRange, Never>()
    
    /// 格式转换器
    private let formatConverter = XiaoMiFormatConverter.shared
    
    /// 自定义渲染器
    private let customRenderer = CustomRenderer.shared
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Publishers
    
    /// 格式变化发布者
    var formatChangePublisher: AnyPublisher<TextFormat, Never> {
        formatChangeSubject.eraseToAnyPublisher()
    }
    
    /// 特殊元素插入发布者
    var specialElementPublisher: AnyPublisher<SpecialElement, Never> {
        specialElementSubject.eraseToAnyPublisher()
    }
    
    /// 内容变化发布者
    var contentChangePublisher: AnyPublisher<NSAttributedString, Never> {
        contentChangeSubject.eraseToAnyPublisher()
    }
    
    /// 选择变化发布者
    var selectionChangePublisher: AnyPublisher<NSRange, Never> {
        selectionChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init() {
        // 初始化工具栏按钮状态
        for format in TextFormat.allCases {
            toolbarButtonStates[format] = false
        }
        
        // 设置内部观察者
        setupInternalObservers()
    }
    
    // MARK: - Public Methods - 格式应用 (需求 9.3)
    
    /// 应用格式到选中文本
    /// - Parameter format: 要应用的格式
    func applyFormat(_ format: TextFormat) {
        // 切换格式状态
        if currentFormats.contains(format) {
            currentFormats.remove(format)
            toolbarButtonStates[format] = false
        } else {
            // 处理互斥格式
            handleMutuallyExclusiveFormats(for: format)
            currentFormats.insert(format)
            toolbarButtonStates[format] = true
        }
        
        // 发布格式变化
        formatChangeSubject.send(format)
        
        // 标记有未保存的更改
        hasUnsavedChanges = true
    }
    
    /// 设置格式状态（不触发切换）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - active: 是否激活
    func setFormatState(_ format: TextFormat, active: Bool) {
        if active {
            currentFormats.insert(format)
        } else {
            currentFormats.remove(format)
        }
        toolbarButtonStates[format] = active
    }
    
    /// 清除所有格式
    func clearAllFormats() {
        currentFormats.removeAll()
        for format in TextFormat.allCases {
            toolbarButtonStates[format] = false
        }
    }
    
    /// 插入特殊元素
    /// - Parameter element: 要插入的特殊元素
    func insertSpecialElement(_ element: SpecialElement) {
        specialElementSubject.send(element)
        hasUnsavedChanges = true
    }
    
    /// 插入分割线
    func insertHorizontalRule() {
        insertSpecialElement(.horizontalRule)
    }
    
    /// 插入复选框
    /// - Parameters:
    ///   - checked: 是否选中（默认为 false）
    ///   - level: 复选框级别（默认为 3）
    func insertCheckbox(checked: Bool = false, level: Int = 3) {
        insertSpecialElement(.checkbox(checked: checked, level: level))
    }
    
    /// 插入引用块
    /// - Parameter content: 引用内容（默认为空）
    func insertQuote(content: String = "") {
        insertSpecialElement(.quote(content: content))
    }
    
    /// 插入图片
    /// - Parameters:
    ///   - fileId: 文件 ID（可选）
    ///   - src: 图片源 URL（可选）
    func insertImage(fileId: String? = nil, src: String? = nil) {
        insertSpecialElement(.image(fileId: fileId, src: src))
    }
    
    /// 插入图片（从 NSImage）
    /// - Parameter image: 要插入的图片
    func insertImage(_ image: NSImage) {
        // 保存图片到本地存储
        let folderId = currentFolderId ?? "default"
        
        if let saveResult = ImageStorageManager.shared.saveImage(image, folderId: folderId) {
            insertSpecialElement(.image(fileId: saveResult.fileId, src: nil))
        }
    }
    
    // MARK: - Public Methods - 光标和选择管理 (需求 9.1, 9.2)
    
    /// 更新光标位置
    /// - Parameter position: 新的光标位置
    func updateCursorPosition(_ position: Int) {
        cursorPosition = position
        updateCurrentFormats()
        detectSpecialElementAtCursor()
    }
    
    /// 更新选择范围
    /// - Parameter range: 新的选择范围
    func updateSelectedRange(_ range: NSRange) {
        selectedRange = range
        cursorPosition = range.location
        updateCurrentFormats()
        detectSpecialElementAtCursor()
        selectionChangeSubject.send(range)
    }
    
    /// 设置编辑器焦点状态 (需求 9.5)
    /// - Parameter focused: 是否获得焦点
    func setEditorFocused(_ focused: Bool) {
        isEditorFocused = focused
        
        if focused {
            // 同步编辑器上下文状态
            updateCurrentFormats()
            detectSpecialElementAtCursor()
        }
    }
    
    // MARK: - Public Methods - 内容管理
    
    /// 更新编辑器内容（AttributedString）
    /// - Parameter text: 新的内容
    func updateContent(_ text: AttributedString) {
        attributedText = text
        hasUnsavedChanges = true
    }
    
    /// 更新编辑器内容（NSAttributedString）
    /// - Parameter text: 新的内容
    func updateNSContent(_ text: NSAttributedString) {
        nsAttributedText = text
        contentChangeSubject.send(text)
        hasUnsavedChanges = true
    }
    
    /// 从 XML 加载内容
    /// - Parameter xml: 小米笔记 XML 格式内容
    func loadFromXML(_ xml: String) {
        do {
            let attributed = try formatConverter.xmlToAttributedString(xml)
            attributedText = attributed
            
            // 转换为 NSAttributedString
            let nsAttributed = try NSAttributedString(attributed, including: \.appKit)
            nsAttributedText = nsAttributed
            
            hasUnsavedChanges = false
        } catch {
            print("[NativeEditorContext] 加载 XML 失败: \(error)")
        }
    }
    
    /// 导出为 XML
    /// - Returns: 小米笔记 XML 格式内容
    func exportToXML() -> String {
        do {
            return try formatConverter.attributedStringToXML(attributedText)
        } catch {
            print("[NativeEditorContext] 导出 XML 失败: \(error)")
            return ""
        }
    }
    
    /// 检查格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    func isFormatActive(_ format: TextFormat) -> Bool {
        return currentFormats.contains(format)
    }
    
    /// 获取当前行的块级格式
    /// - Returns: 块级格式，如果没有则返回 nil
    func getCurrentBlockFormat() -> TextFormat? {
        return currentFormats.first { $0.isBlockFormat }
    }
    
    // MARK: - Private Methods
    
    /// 设置内部观察者
    private func setupInternalObservers() {
        // 监听内容变化
        $nsAttributedText
            .dropFirst()
            .sink { [weak self] _ in
                self?.hasUnsavedChanges = true
            }
            .store(in: &cancellables)
    }
    
    /// 根据当前光标位置更新格式状态 (需求 9.1)
    private func updateCurrentFormats() {
        guard !nsAttributedText.string.isEmpty else {
            clearAllFormats()
            return
        }
        
        // 确保位置有效
        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            clearAllFormats()
            return
        }
        
        // 获取当前位置的属性
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)
        
        // 清除当前格式
        var detectedFormats: Set<TextFormat> = []
        
        // 检测字体属性
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            
            if traits.contains(.bold) {
                detectedFormats.insert(.bold)
            }
            if traits.contains(.italic) {
                detectedFormats.insert(.italic)
            }
            
            // 检测标题大小
            let fontSize = font.pointSize
            if fontSize >= 24 {
                detectedFormats.insert(.heading1)
            } else if fontSize >= 20 {
                detectedFormats.insert(.heading2)
            } else if fontSize >= 16 && fontSize < 20 {
                detectedFormats.insert(.heading3)
            }
        }
        
        // 检测下划线
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            detectedFormats.insert(.underline)
        }
        
        // 检测删除线
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            detectedFormats.insert(.strikethrough)
        }
        
        // 检测背景色（高亮）
        if attributes[.backgroundColor] != nil {
            detectedFormats.insert(.highlight)
        }
        
        // 检测段落样式
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            switch paragraphStyle.alignment {
            case .center:
                detectedFormats.insert(.alignCenter)
            case .right:
                detectedFormats.insert(.alignRight)
            default:
                break
            }
            
            // 更新缩进级别
            currentIndentLevel = Int(paragraphStyle.firstLineHeadIndent / 20) + 1
        }
        
        // 检测引用块属性
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            detectedFormats.insert(.quote)
        }
        
        // 更新当前格式
        currentFormats = detectedFormats
        
        // 更新工具栏按钮状态
        for format in TextFormat.allCases {
            toolbarButtonStates[format] = detectedFormats.contains(format)
        }
    }
    
    /// 检测光标位置的特殊元素 (需求 9.2, 9.4)
    private func detectSpecialElementAtCursor() {
        guard !nsAttributedText.string.isEmpty else {
            currentSpecialElement = nil
            return
        }
        
        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            currentSpecialElement = nil
            return
        }
        
        // 检查是否有附件
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)
        
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            // 识别附件类型
            if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
                currentSpecialElement = .checkbox(
                    checked: checkboxAttachment.isChecked,
                    level: checkboxAttachment.level
                )
                // 更新工具栏状态
                toolbarButtonStates[.checkbox] = true
            } else if attachment is HorizontalRuleAttachment {
                currentSpecialElement = .horizontalRule
            } else if let bulletAttachment = attachment as? BulletAttachment {
                currentSpecialElement = .bulletPoint(indent: bulletAttachment.indent)
                toolbarButtonStates[.bulletList] = true
            } else if let orderAttachment = attachment as? OrderAttachment {
                currentSpecialElement = .numberedItem(
                    number: orderAttachment.number,
                    indent: orderAttachment.indent
                )
                toolbarButtonStates[.numberedList] = true
            } else if let imageAttachment = attachment as? ImageAttachment {
                currentSpecialElement = .image(
                    fileId: imageAttachment.fileId,
                    src: imageAttachment.src
                )
            } else {
                currentSpecialElement = nil
            }
        } else {
            currentSpecialElement = nil
            // 清除特殊元素相关的工具栏状态
            toolbarButtonStates[.checkbox] = false
            toolbarButtonStates[.bulletList] = false
            toolbarButtonStates[.numberedList] = false
        }
    }
    
    /// 处理互斥格式
    /// - Parameter format: 要应用的格式
    private func handleMutuallyExclusiveFormats(for format: TextFormat) {
        // 标题格式互斥
        if format == .heading1 || format == .heading2 || format == .heading3 {
            currentFormats.remove(.heading1)
            currentFormats.remove(.heading2)
            currentFormats.remove(.heading3)
            toolbarButtonStates[.heading1] = false
            toolbarButtonStates[.heading2] = false
            toolbarButtonStates[.heading3] = false
        }
        
        // 对齐格式互斥
        if format == .alignCenter || format == .alignRight {
            currentFormats.remove(.alignCenter)
            currentFormats.remove(.alignRight)
            toolbarButtonStates[.alignCenter] = false
            toolbarButtonStates[.alignRight] = false
        }
        
        // 列表格式互斥
        if format == .bulletList || format == .numberedList || format == .checkbox {
            currentFormats.remove(.bulletList)
            currentFormats.remove(.numberedList)
            currentFormats.remove(.checkbox)
            toolbarButtonStates[.bulletList] = false
            toolbarButtonStates[.numberedList] = false
            toolbarButtonStates[.checkbox] = false
        }
    }
}