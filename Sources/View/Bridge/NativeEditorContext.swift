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
    
    /// 格式状态同步器
    private let formatStateSynchronizer = FormatStateSynchronizer.createDefault()
    
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
        
        // 设置格式状态同步器的更新回调
        formatStateSynchronizer.setUpdateCallback { [weak self] in
            self?.updateCurrentFormats()
        }
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
        // 使用同步器调度状态更新（防抖）
        formatStateSynchronizer.scheduleStateUpdate()
        detectSpecialElementAtCursor()
    }
    
    /// 更新选择范围
    /// - Parameter range: 新的选择范围
    func updateSelectedRange(_ range: NSRange) {
        selectedRange = range
        cursorPosition = range.location
        // 使用同步器调度状态更新（防抖）
        formatStateSynchronizer.scheduleStateUpdate()
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
        // 关键修复：如果 XML 为空，清空编辑器
        guard !xml.isEmpty else {
            print("[NativeEditorContext] XML 为空，清空编辑器")
            attributedText = AttributedString()
            nsAttributedText = NSAttributedString()
            hasUnsavedChanges = false
            return
        }
        
        do {
            // 使用新的 xmlToNSAttributedString 方法直接获取 NSAttributedString
            // 这样可以正确保留自定义的 NSTextAttachment 子类（如 ImageAttachment）
            let nsAttributed = try formatConverter.xmlToNSAttributedString(xml, folderId: currentFolderId)
            
            print("[NativeEditorContext] 🖼️ NSAttributedString 转换完成（直接转换）")
            print("[NativeEditorContext]   - nsAttributed.length: \(nsAttributed.length)")
            print("[NativeEditorContext]   - nsAttributed.string: '\(nsAttributed.string)'")
            
            // 检查是否包含附件
            var attachmentCount = 0
            var imageAttachmentCount = 0
            nsAttributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: nsAttributed.length), options: []) { value, range, _ in
                if let attachment = value as? NSTextAttachment {
                    attachmentCount += 1
                    print("[NativeEditorContext] 🖼️ 发现附件 \(attachmentCount): \(type(of: attachment)) at range \(range)")
                    if let imageAttachment = attachment as? ImageAttachment {
                        imageAttachmentCount += 1
                        print("[NativeEditorContext]   - ImageAttachment.fileId: '\(imageAttachment.fileId ?? "nil")'")
                        print("[NativeEditorContext]   - ImageAttachment.src: '\(imageAttachment.src ?? "nil")'")
                    }
                }
            }
            print("[NativeEditorContext] 🖼️ 总共发现 \(attachmentCount) 个附件，其中 \(imageAttachmentCount) 个是 ImageAttachment")
            
            // 为没有设置前景色的文本添加默认颜色（适配深色模式）
            let mutableAttributed = NSMutableAttributedString(attributedString: nsAttributed)
            let fullRange = NSRange(location: 0, length: mutableAttributed.length)
            
            // 遍历所有范围，为没有前景色的文本设置 labelColor
            mutableAttributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                if value == nil {
                    // 使用 labelColor，它会自动适配深色/浅色模式
                    mutableAttributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
            }
            
            nsAttributedText = mutableAttributed
            
            // 同时更新 attributedText（用于导出）
            if let attributed = try? AttributedString(mutableAttributed, including: \.appKit) {
                attributedText = attributed
            }
            
            hasUnsavedChanges = false
            print("[NativeEditorContext] ✅ 加载 XML 成功 - 长度: \(xml.count), 转换后文本长度: \(mutableAttributed.length)")
        } catch {
            print("[NativeEditorContext] ❌ 加载 XML 失败: \(error)")
            // 关键修复：加载失败时清空编辑器，避免显示旧内容
            attributedText = AttributedString()
            nsAttributedText = NSAttributedString()
            hasUnsavedChanges = false
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
    
    // MARK: - 格式状态同步器方法
    
    /// 立即更新格式状态（不使用防抖）
    /// 
    /// 在某些情况下（如用户点击格式按钮），我们需要立即更新状态
    func forceUpdateFormats() {
        print("[NativeEditorContext] forceUpdateFormats 被调用")
        formatStateSynchronizer.performImmediateUpdate()
    }
    
    /// 请求从外部源同步内容
    /// 
    /// 当需要确保 nsAttributedText 是最新的时候调用此方法
    /// 这会发送一个通知，让 NativeEditorView 同步内容
    func requestContentSync() {
        print("[NativeEditorContext] requestContentSync 被调用")
        // 发送通知请求同步
        NotificationCenter.default.post(name: .nativeEditorRequestContentSync, object: self)
    }
    
    /// 获取格式状态同步器的性能统计信息
    /// - Returns: 性能统计信息字典
    func getFormatSyncPerformanceStats() -> [String: Any] {
        return formatStateSynchronizer.getPerformanceStats()
    }
    
    /// 重置格式状态同步器的性能统计信息
    func resetFormatSyncPerformanceStats() {
        formatStateSynchronizer.resetPerformanceStats()
    }
    
    /// 打印格式状态同步器的性能统计信息
    func printFormatSyncPerformanceStats() {
        formatStateSynchronizer.printPerformanceStats()
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
    /// 增强版本 - 完善所有格式类型的状态检测
    /// 需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10
    func updateCurrentFormats() {
        print("[NativeEditorContext] updateCurrentFormats 被调用")
        print("[NativeEditorContext]   - nsAttributedText.length: \(nsAttributedText.length)")
        print("[NativeEditorContext]   - cursorPosition: \(cursorPosition)")
        print("[NativeEditorContext]   - selectedRange: \(selectedRange)")
        
        guard !nsAttributedText.string.isEmpty else {
            print("[NativeEditorContext]   - 文本为空，清除所有格式")
            clearAllFormats()
            return
        }
        
        // 确保位置有效
        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            print("[NativeEditorContext]   - 位置无效 (position: \(position))，清除所有格式")
            clearAllFormats()
            return
        }
        
        print("[NativeEditorContext]   - 有效位置: \(position)")
        
        // 获取当前位置的属性
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)
        print("[NativeEditorContext]   - 属性数量: \(attributes.count)")
        
        // 检测所有格式类型
        var detectedFormats: Set<TextFormat> = []
        
        // 1. 检测字体属性（加粗、斜体、标题）
        let fontFormats = detectFontFormats(from: attributes)
        detectedFormats.formUnion(fontFormats)
        print("[NativeEditorContext]   - 字体格式: \(fontFormats.map { $0.displayName })")
        
        // 2. 检测文本装饰（下划线、删除线、高亮）
        let decorationFormats = detectTextDecorations(from: attributes)
        detectedFormats.formUnion(decorationFormats)
        print("[NativeEditorContext]   - 装饰格式: \(decorationFormats.map { $0.displayName })")
        
        // 3. 检测段落格式（对齐方式）
        let paragraphFormats = detectParagraphFormats(from: attributes)
        detectedFormats.formUnion(paragraphFormats)
        print("[NativeEditorContext]   - 段落格式: \(paragraphFormats.map { $0.displayName })")
        
        // 4. 检测列表格式（无序、有序、复选框）
        let listFormats = detectListFormats(at: position)
        detectedFormats.formUnion(listFormats)
        print("[NativeEditorContext]   - 列表格式: \(listFormats.map { $0.displayName })")
        
        // 5. 检测特殊元素格式（引用块、分割线）
        let specialFormats = detectSpecialElementFormats(at: position)
        detectedFormats.formUnion(specialFormats)
        print("[NativeEditorContext]   - 特殊格式: \(specialFormats.map { $0.displayName })")
        
        print("[NativeEditorContext]   - 检测到的所有格式: \(detectedFormats.map { $0.displayName })")
        
        // 更新状态并验证
        updateFormatsWithValidation(detectedFormats)
    }
    
    /// 检测字体格式（加粗、斜体、标题）
    /// 需求: 2.1, 2.2, 2.6
    private func detectFontFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        // 调试：打印所有属性键
        print("[NativeEditorContext] detectFontFormats - 属性键: \(attributes.keys.map { $0.rawValue })")
        
        guard let font = attributes[.font] as? NSFont else {
            print("[NativeEditorContext] detectFontFormats - 没有找到 .font 属性")
            return formats
        }
        
        print("[NativeEditorContext] detectFontFormats - 字体: \(font.fontName), 大小: \(font.pointSize)")
        
        // 检测字体特性
        let traits = font.fontDescriptor.symbolicTraits
        print("[NativeEditorContext] detectFontFormats - 字体特性: \(traits)")
        
        // 加粗检测 (需求 2.1)
        // 方法 1: 检查 symbolicTraits
        var isBold = traits.contains(.bold)
        
        // 方法 2: 检查字体名称是否包含 "Bold"（备用检测）
        if !isBold {
            let fontName = font.fontName.lowercased()
            isBold = fontName.contains("bold") || fontName.contains("-bold")
            if isBold {
                print("[NativeEditorContext] detectFontFormats - 通过字体名称检测到粗体: \(font.fontName)")
            }
        }
        
        // 方法 3: 检查字体 weight（备用检测）
        if !isBold {
            if let weightTrait = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
               let weight = weightTrait[.weight] as? CGFloat {
                // NSFontWeight.bold 的值约为 0.4
                isBold = weight >= 0.4
                if isBold {
                    print("[NativeEditorContext] detectFontFormats - 通过字体 weight 检测到粗体: weight=\(weight)")
                }
            }
        }
        
        if isBold {
            formats.insert(.bold)
            print("[NativeEditorContext] detectFontFormats - 检测到粗体")
        }
        
        // 斜体检测 (需求 2.2)
        // 方法 1: 检查 symbolicTraits
        var isItalic = traits.contains(.italic)
        
        // 方法 2: 检查字体名称是否包含 "Italic" 或 "Oblique"（备用检测）
        if !isItalic {
            let fontName = font.fontName.lowercased()
            isItalic = fontName.contains("italic") || fontName.contains("oblique")
            if isItalic {
                print("[NativeEditorContext] detectFontFormats - 通过字体名称检测到斜体: \(font.fontName)")
            }
        }
        
        if isItalic {
            formats.insert(.italic)
            print("[NativeEditorContext] detectFontFormats - 检测到斜体")
        }
        
        // 标题检测 (需求 2.6)
        let fontSize = font.pointSize
        if fontSize >= 24 {
            formats.insert(.heading1)
            print("[NativeEditorContext] detectFontFormats - 检测到大标题 (fontSize: \(fontSize))")
        } else if fontSize >= 20 {
            formats.insert(.heading2)
            print("[NativeEditorContext] detectFontFormats - 检测到二级标题 (fontSize: \(fontSize))")
        } else if fontSize >= 16 && fontSize < 20 {
            formats.insert(.heading3)
            print("[NativeEditorContext] detectFontFormats - 检测到三级标题 (fontSize: \(fontSize))")
        }
        
        return formats
    }
    
    /// 检测文本装饰（下划线、删除线、高亮）
    /// 需求: 2.3, 2.4, 2.5
    private func detectTextDecorations(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        // 下划线检测 (需求 2.3)
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            formats.insert(.underline)
        }
        
        // 删除线检测 (需求 2.4)
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            formats.insert(.strikethrough)
        }
        
        // 高亮检测 (需求 2.5)
        // 检查背景色是否存在且不是默认颜色
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            // 排除透明或白色背景
            if backgroundColor.alphaComponent > 0.1 && backgroundColor != .clear && backgroundColor != .white {
                formats.insert(.highlight)
            }
        }
        
        return formats
    }
    
    /// 检测段落格式（对齐方式）
    /// 需求: 2.7, 2.8
    private func detectParagraphFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        guard let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle else {
            return formats
        }
        
        // 对齐方式检测 (需求 2.7, 2.8)
        switch paragraphStyle.alignment {
        case .center:
            formats.insert(.alignCenter)
        case .right:
            formats.insert(.alignRight)
        default:
            break
        }
        
        // 更新缩进级别
        currentIndentLevel = Int(paragraphStyle.firstLineHeadIndent / 20) + 1
        
        return formats
    }
    
    /// 检测列表格式（无序、有序、复选框）
    /// 需求: 2.9
    private func detectListFormats(at position: Int) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        // 检查当前位置是否有附件
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)
        
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            // 检测复选框
            if attachment is InteractiveCheckboxAttachment {
                formats.insert(.checkbox)
            }
            // 检测无序列表
            else if attachment is BulletAttachment {
                formats.insert(.bulletList)
            }
            // 检测有序列表
            else if attachment is OrderAttachment {
                formats.insert(.numberedList)
            }
        }
        
        // 如果当前位置没有附件，检查当前行的开头
        if formats.isEmpty {
            let lineRange = getLineRange(at: position)
            if lineRange.location < nsAttributedText.length {
                let lineAttributes = nsAttributedText.attributes(at: lineRange.location, effectiveRange: nil)
                if let attachment = lineAttributes[.attachment] as? NSTextAttachment {
                    if attachment is InteractiveCheckboxAttachment {
                        formats.insert(.checkbox)
                    } else if attachment is BulletAttachment {
                        formats.insert(.bulletList)
                    } else if attachment is OrderAttachment {
                        formats.insert(.numberedList)
                    }
                }
            }
        }
        
        return formats
    }
    
    /// 检测特殊元素格式（引用块、分割线）
    /// 需求: 2.10, 7.1, 7.2, 7.3
    private func detectSpecialElementFormats(at position: Int) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)
        
        // 检测引用块 (需求 2.10)
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            formats.insert(.quote)
        }
        
        // 检测分割线 (需求 7.2)
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            if attachment is HorizontalRuleAttachment {
                formats.insert(.horizontalRule)
            }
        }
        
        return formats
    }
    
    /// 获取指定位置所在行的范围
    private func getLineRange(at position: Int) -> NSRange {
        let string = nsAttributedText.string as NSString
        return string.lineRange(for: NSRange(location: position, length: 0))
    }
    
    /// 更新格式状态并验证
    private func updateFormatsWithValidation(_ detectedFormats: Set<TextFormat>) {
        // 验证互斥格式
        let validatedFormats = validateMutuallyExclusiveFormats(detectedFormats)
        
        // 更新当前格式
        currentFormats = validatedFormats
        
        // 更新工具栏按钮状态
        for format in TextFormat.allCases {
            toolbarButtonStates[format] = validatedFormats.contains(format)
        }
        
        // 记录格式变化（调试用）
        #if DEBUG
        if !validatedFormats.isEmpty {
            let formatNames = validatedFormats.map { $0.displayName }.joined(separator: ", ")
            print("[NativeEditorContext] 检测到格式: \(formatNames)")
        }
        #endif
    }
    
    /// 验证互斥格式，确保只保留一个
    private func validateMutuallyExclusiveFormats(_ formats: Set<TextFormat>) -> Set<TextFormat> {
        var validated = formats
        
        // 标题格式互斥 - 优先保留最大的标题
        let headings: [TextFormat] = [.heading1, .heading2, .heading3]
        let detectedHeadings = headings.filter { formats.contains($0) }
        if detectedHeadings.count > 1 {
            // 保留第一个（最大的）标题
            for heading in detectedHeadings.dropFirst() {
                validated.remove(heading)
            }
        }
        
        // 对齐格式互斥 - 优先保留居中
        let alignments: [TextFormat] = [.alignCenter, .alignRight]
        let detectedAlignments = alignments.filter { formats.contains($0) }
        if detectedAlignments.count > 1 {
            // 保留第一个对齐方式
            for alignment in detectedAlignments.dropFirst() {
                validated.remove(alignment)
            }
        }
        
        // 列表格式互斥 - 优先保留复选框
        let lists: [TextFormat] = [.checkbox, .bulletList, .numberedList]
        let detectedLists = lists.filter { formats.contains($0) }
        if detectedLists.count > 1 {
            // 保留第一个列表类型
            for list in detectedLists.dropFirst() {
                validated.remove(list)
            }
        }
        
        return validated
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