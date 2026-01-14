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
public enum TextFormat: CaseIterable, Hashable, Sendable {
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
    case audio(fileId: String, digest: String?, mimeType: String?)
    
    /// 元素的显示名称
    var displayName: String {
        switch self {
        case .checkbox: return "复选框"
        case .horizontalRule: return "分割线"
        case .bulletPoint: return "项目符号"
        case .numberedItem: return "编号列表"
        case .quote: return "引用块"
        case .image: return "图片"
        case .audio: return "语音录音"
        }
    }
}

/// 缩进操作类型枚举
/// 需求: 6.1, 6.2, 6.3, 6.5 - 支持增加和减少缩进操作
enum IndentOperation: Equatable {
    case increase  // 增加缩进
    case decrease  // 减少缩进
    
    /// 操作的显示名称
    var displayName: String {
        switch self {
        case .increase: return "增加缩进"
        case .decrease: return "减少缩进"
        }
    }
}

/// 编辑器类型枚举
public enum EditorType: String, CaseIterable, Identifiable, Codable, Sendable {
    case native = "native"
    case web = "web"
    
    public var id: String { rawValue }
    
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
public class NativeEditorContext: ObservableObject {
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
    
    /// 内容版本号，用于强制触发视图更新
    /// 
    /// 当笔记切换时，SwiftUI 可能无法正确检测 NSAttributedString 的属性变化
    /// 通过递增版本号，可以强制触发 NativeEditorView 的 updateNSView 方法
    /// 
    /// _Requirements: 3.1_
    @Published var contentVersion: Int = 0
    
    // MARK: - 内容保护属性
    // _Requirements: 2.5, 9.1_ - 保存失败时的内容保护
    
    /// 保存失败时的备份内容
    /// 
    /// 当保存操作失败时，将当前编辑内容备份到此属性
    /// 用于后续重试保存或恢复内容
    /// 
    /// _Requirements: 2.5, 9.1_
    @Published var backupContent: NSAttributedString? = nil
    
    /// 最后一次保存失败的错误信息
    /// 
    /// _Requirements: 9.1_
    @Published var lastSaveError: String? = nil
    
    /// 是否有待重试的保存操作
    /// 
    /// _Requirements: 9.1_
    @Published var hasPendingRetry: Bool = false
    
    /// 部分激活的格式集合（用于混合格式状态显示）
    /// 需求: 6.1, 6.2
    @Published var partiallyActiveFormats: Set<TextFormat> = []
    
    /// 格式激活比例（用于混合格式状态显示）
    /// 需求: 6.2
    @Published var formatActivationRatios: [TextFormat: Double] = [:]
    
    // MARK: - Private Properties
    
    /// 格式变化发布者
    private let formatChangeSubject = PassthroughSubject<TextFormat, Never>()
    
    /// 特殊元素插入发布者
    private let specialElementSubject = PassthroughSubject<SpecialElement, Never>()
    
    /// 内容变化发布者
    private let contentChangeSubject = PassthroughSubject<NSAttributedString, Never>()
    
    /// 选择变化发布者
    private let selectionChangeSubject = PassthroughSubject<NSRange, Never>()
    
    /// 缩进操作发布者
    /// 需求: 6.1, 6.2, 6.3, 6.5 - 支持缩进操作
    private let indentChangeSubject = PassthroughSubject<IndentOperation, Never>()
    
    /// 格式转换器
    private let formatConverter = XiaoMiFormatConverter.shared
    
    /// 自定义渲染器
    private let customRenderer = CustomRenderer.shared
    
    /// 格式状态同步器
    private let formatStateSynchronizer = FormatStateSynchronizer.createDefault()
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 格式提供者
    
    /// 格式提供者（延迟初始化）
    /// _Requirements: 3.1, 3.2, 3.3_
    private var _formatProvider: NativeFormatProvider?
    
    /// 格式提供者（公开访问）
    /// _Requirements: 3.1, 3.2, 3.3_
    public var formatProvider: NativeFormatProvider {
        if _formatProvider == nil {
            _formatProvider = NativeFormatProvider(editorContext: self)
            print("[NativeEditorContext] 创建 NativeFormatProvider")
        }
        return _formatProvider!
    }
    
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
    
    /// 缩进操作发布者
    /// 需求: 6.1, 6.2, 6.3, 6.5 - 支持缩进操作
    var indentChangePublisher: AnyPublisher<IndentOperation, Never> {
        indentChangeSubject.eraseToAnyPublisher()
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
        
        // 延迟注册格式提供者到 FormatStateManager
        // 使用 Task 确保在主线程上执行
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // 触发 formatProvider 的延迟初始化
            _ = self.formatProvider
            print("[NativeEditorContext] 初始化完成，formatProvider 已创建")
        }
    }
    
    // MARK: - Public Methods - 格式应用 (需求 9.3)
    
    /// 当前格式应用方式（用于一致性检查）
    /// 需求: 5.4 - 确保格式应用方式一致性
    @Published var currentApplicationMethod: FormatApplicationMethod = .programmatic
    
    /// 应用格式到选中文本
    /// - Parameter format: 要应用的格式
    func applyFormat(_ format: TextFormat) {
        applyFormat(format, method: .programmatic)
    }
    
    /// 应用格式到选中文本（带应用方式标识）
    /// - Parameters:
    ///   - format: 要应用的格式
    ///   - method: 应用方式
    /// 需求: 5.4 - 确保格式应用方式一致性
    func applyFormat(_ format: TextFormat, method: FormatApplicationMethod) {
        // 记录应用方式
        currentApplicationMethod = method
        
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
        
        // 使用 CursorFormatManager 处理工具栏格式切换
        // _Requirements: 6.3 - 同步更新 Format_State 和 Typing_Attributes
        CursorFormatManager.shared.handleToolbarFormatToggle(format)
        
        // 标记有未保存的更改
        hasUnsavedChanges = true
        
        // 重置应用方式
        currentApplicationMethod = .programmatic
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
    
    /// 清除标题格式（将文本恢复为正文样式）
    func clearHeadingFormat() {
        print("[NativeEditorContext] 清除标题格式，恢复为正文样式")
        
        // 移除所有标题格式
        currentFormats.remove(.heading1)
        currentFormats.remove(.heading2)
        currentFormats.remove(.heading3)
        toolbarButtonStates[.heading1] = false
        toolbarButtonStates[.heading2] = false
        toolbarButtonStates[.heading3] = false
        
        // 重置字体大小为正文大小（13pt）
        // _需求: 1.6, 1.7, 5.1, 5.4, 5.5_
        resetFontSizeToBody()
        
        // 注意：不要调用 formatChangeSubject.send(.heading1)！
        // 因为这会触发 NativeEditorView.Coordinator 中的 applyFormat(.heading1)
        // 导致大标题格式被错误地应用
        // _修复: heading2/heading3 转正文时错误应用大标题格式_
        
        // 标记有未保存的更改
        hasUnsavedChanges = true
        
        // 强制更新格式状态，确保 UI 同步
        updateCurrentFormats()
        
        print("[NativeEditorContext] ✅ 标题格式已清除，字体大小已重置为 13pt")
    }
    
    /// 重置字体大小为正文大小
    /// 
    /// 将选中文本或当前行的字体大小重置为正文大小，同时保留字体特性（加粗、斜体等）
    /// 用于将标题转换为正文时，确保字体大小正确重置
    /// 
    /// - 选择模式：重置选中文本的字体大小
    /// - 光标模式：重置当前行的字体大小
    /// 
    /// _需求: 1.6, 1.7, 4.7_
    /// _Requirements: 3.1, 3.2, 3.3, 3.4, 6.2, 6.3, 6.4, 6.5_
    private func resetFontSizeToBody() {
        // 使用 FontSizeManager 获取正文字体大小
        let bodySize = FontSizeManager.shared.bodySize
        print("[NativeEditorContext] 开始重置字体大小为正文大小（\(bodySize)pt）")
        
        // 确定要处理的范围
        let range: NSRange
        if selectedRange.length > 0 {
            // 选择模式：使用选中范围
            range = selectedRange
            print("[NativeEditorContext]   📝 选择模式：使用选中范围")
        } else {
            // 光标模式：获取当前行的范围
            let string = nsAttributedText.string as NSString
            let lineRange = string.lineRange(for: NSRange(location: cursorPosition, length: 0))
            range = lineRange
            print("[NativeEditorContext]   📍 光标模式：使用当前行范围")
        }
        
        // 检查范围是否有效
        guard range.length > 0 else {
            print("[NativeEditorContext]   ⚠️ 范围长度为0，跳过字体大小重置")
            return
        }
        
        print("[NativeEditorContext]   - 处理范围: location=\(range.location), length=\(range.length)")
        
        // 创建可变副本
        let mutableText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
        
        // 遍历范围，重置字体大小
        mutableText.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            if let font = value as? NSFont {
                print("[NativeEditorContext]   - 处理子范围: location=\(subRange.location), length=\(subRange.length)")
                print("[NativeEditorContext]     原字体: \(font.fontName), 大小: \(font.pointSize)pt")
                
                // 使用 FontSizeManager 创建新字体，保留字体特性（加粗、斜体）
                let traits = font.fontDescriptor.symbolicTraits
                let newFont = FontSizeManager.shared.createFont(ofSize: bodySize, traits: traits)
                print("[NativeEditorContext]     新字体: \(newFont.fontName), 大小: \(bodySize)pt（保留特性: bold=\(traits.contains(.bold)), italic=\(traits.contains(.italic))）")
                
                // 应用新字体
                mutableText.addAttribute(.font, value: newFont, range: subRange)
            }
        }
        
        // 更新编辑器内容
        updateNSContent(mutableText)
        
        print("[NativeEditorContext] ✅ 字体大小重置完成")
    }
    
    /// 清除对齐格式（恢复默认左对齐）
    func clearAlignmentFormat() {
        print("[NativeEditorContext] 清除对齐格式，恢复为左对齐")
        
        // 移除居中和居右格式
        currentFormats.remove(.alignCenter)
        currentFormats.remove(.alignRight)
        toolbarButtonStates[.alignCenter] = false
        toolbarButtonStates[.alignRight] = false
        
        // 注意：不要调用 formatChangeSubject.send(.alignCenter)！
        // 因为这会触发 NativeEditorView.Coordinator 中的 applyFormat(.alignCenter)
        // 导致居中对齐格式被错误地应用
        // _修复: 与 clearHeadingFormat 保持一致_
        
        // 标记有未保存的更改
        hasUnsavedChanges = true
        
        // 强制更新格式状态，确保 UI 同步
        updateCurrentFormats()
        
        print("[NativeEditorContext] ✅ 对齐格式已清除")
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
    
    /// 插入语音录音
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Requirements: 9.4, 9.5
    func insertAudio(fileId: String, digest: String? = nil, mimeType: String? = nil) {
        print("[NativeEditorContext] 插入语音录音: fileId=\(fileId)")
        insertSpecialElement(.audio(fileId: fileId, digest: digest, mimeType: mimeType))
    }
    
    // MARK: - Public Methods - 录音模板操作 (需求 4.2, 4.3)
    
    /// 插入录音模板占位符
    /// 
    /// 在原生编辑器中插入 AudioAttachment 作为录音模板占位符
    /// 占位符使用 `temp_[templateId]` 作为 fileId，并设置 `isTemporaryPlaceholder = true`
    /// 导出 XML 时会生成 `<sound fileid="temp_xxx" des="temp"/>` 格式
    /// 
    /// - Parameter templateId: 模板唯一标识符
    /// - Requirements: 4.2
    func insertRecordingTemplate(templateId: String) {
        print("[NativeEditorContext] 插入录音模板: templateId=\(templateId)")
        
        // 创建临时 fileId
        let tempFileId = "temp_\(templateId)"
        
        // 创建 AudioAttachment 作为占位符
        let audioAttachment = customRenderer.createAudioAttachment(
            fileId: tempFileId,
            digest: nil,
            mimeType: nil
        )
        // 标记为临时占位符
        audioAttachment.isTemporaryPlaceholder = true
        
        // 创建包含附件的 NSAttributedString
        let attachmentString = NSMutableAttributedString(attachment: audioAttachment)
        
        // 添加自定义属性标记这是录音模板（用于后续查找和替换）
        let range = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttribute(NSAttributedString.Key("RecordingTemplate"), value: templateId, range: range)
        
        // 将占位符插入到当前文本的光标位置
        let currentText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
        let insertionPoint = min(cursorPosition, currentText.length)
        currentText.insert(attachmentString, at: insertionPoint)
        
        // 更新编辑器内容
        updateNSContent(currentText)
        
        // 更新光标位置到插入附件之后
        updateCursorPosition(insertionPoint + 1)
        
        hasUnsavedChanges = true
        
        print("[NativeEditorContext] ✅ 录音模板占位符已插入（使用 AudioAttachment）")
    }
    
    /// 更新录音模板为音频附件
    /// 
    /// 将临时的录音模板占位符更新为实际的音频附件
    /// 查找带有 `RecordingTemplate` 属性的 AudioAttachment，替换为新的 AudioAttachment
    /// 新附件使用真实的 fileId，且 `isTemporaryPlaceholder = false`
    /// 
    /// - Parameters:
    ///   - templateId: 模板唯一标识符
    ///   - fileId: 音频文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Requirements: 4.3
    func updateRecordingTemplate(templateId: String, fileId: String, digest: String? = nil, mimeType: String? = nil) {
        print("[NativeEditorContext] 更新录音模板: templateId=\(templateId), fileId=\(fileId)")
        
        // 在当前文本中查找对应的录音模板
        let currentText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
        let fullRange = NSRange(location: 0, length: currentText.length)
        
        var templateFound = false
        var foundRange: NSRange?
        
        // 遍历文本，查找带有指定 templateId 的录音模板
        currentText.enumerateAttribute(NSAttributedString.Key("RecordingTemplate"), in: fullRange, options: []) { value, range, stop in
            if let templateValue = value as? String, templateValue == templateId {
                foundRange = range
                templateFound = true
                stop.pointee = true
            }
        }
        
        if templateFound, let range = foundRange {
            // 创建新的 AudioAttachment（非临时）
            let audioAttachment = customRenderer.createAudioAttachment(
                fileId: fileId,
                digest: digest,
                mimeType: mimeType
            )
            // 确保不是临时占位符
            audioAttachment.isTemporaryPlaceholder = false
            
            // 创建包含附件的 NSAttributedString
            let attachmentString = NSAttributedString(attachment: audioAttachment)
            
            // 替换模板
            currentText.replaceCharacters(in: range, with: attachmentString)
            
            // 更新编辑器内容
            updateNSContent(currentText)
            hasUnsavedChanges = true
            
            print("[NativeEditorContext] ✅ 录音模板已更新为音频附件（使用 AudioAttachment）")
        } else {
            print("[NativeEditorContext] ⚠️ 未找到对应的录音模板: templateId=\(templateId)")
        }
    }
    
    /// 更新录音模板并强制保存
    /// 
    /// 更新录音模板为音频附件后立即强制保存，确保内容持久化
    /// 与Web编辑器保持相同的保存逻辑
    /// 
    /// - Parameters:
    ///   - templateId: 模板唯一标识符
    ///   - fileId: 音频文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    /// - Requirements: 1.1, 2.1
    func updateRecordingTemplateAndSave(templateId: String, fileId: String, digest: String? = nil, mimeType: String? = nil) async throws {
        print("[NativeEditorContext] 更新录音模板并强制保存: templateId=\(templateId), fileId=\(fileId)")
        
        // 1. 更新录音模板
        updateRecordingTemplate(templateId: templateId, fileId: fileId, digest: digest, mimeType: mimeType)
        
        // 2. 强制保存内容
        // 原生编辑器的保存通过 contentChangeSubject 触发
        // 发送内容变化信号，确保立即保存
        contentChangeSubject.send(nsAttributedText)
        
        print("[NativeEditorContext] ✅ 录音模板更新和保存完成")
    }
    
    /// 验证内容持久化
    /// 
    /// 验证保存后的内容是否包含预期的音频附件，确保持久化成功
    /// 
    /// - Parameter expectedContent: 预期的内容（包含音频附件的XML）
    /// - Returns: 是否验证成功
    /// - Requirements: 1.3, 3.4
    func verifyContentPersistence(expectedContent: String) async -> Bool {
        print("[NativeEditorContext] 验证内容持久化，预期内容长度: \(expectedContent.count)")
        
        // 导出当前内容为XML格式
        let currentXML = exportToXML()
        
        // 验证XML内容是否包含音频附件且不包含临时模板
        let isValid = currentXML.contains("<sound fileid=") && 
                     !currentXML.contains("des=\"temp\"") && 
                     currentXML.count > 0
        
        print("[NativeEditorContext] 内容持久化验证结果: \(isValid ? "成功" : "失败")")
        print("[NativeEditorContext] 当前XML长度: \(currentXML.count)")
        
        return isValid
    }
    
    // MARK: - Public Methods - 缩进操作 (需求 6.1, 6.2, 6.3, 6.5)
    
    /// 增加缩进
    /// 需求: 6.1, 6.3, 6.5 - 增加当前行或选中文本的缩进级别
    func increaseIndent() {
        print("[NativeEditorContext] 增加缩进")
        indentChangeSubject.send(.increase)
        hasUnsavedChanges = true
    }
    
    /// 减少缩进
    /// 需求: 6.2, 6.4, 6.5 - 减少当前行或选中文本的缩进级别
    func decreaseIndent() {
        print("[NativeEditorContext] 减少缩进")
        indentChangeSubject.send(.decrease)
        hasUnsavedChanges = true
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
    /// 
    /// 当焦点状态变化时，发送 `.editorFocusDidChange` 通知以更新菜单状态
    /// _Requirements: 14.5_
    func setEditorFocused(_ focused: Bool) {
        // 只有状态真正变化时才更新和发送通知
        guard isEditorFocused != focused else { return }
        
        isEditorFocused = focused
        
        // 发送编辑器焦点变化通知
        // _Requirements: 14.5_
        postEditorFocusNotification(focused)
        
        if focused {
            // 注册格式提供者到 FormatStateManager
            // _Requirements: 8.4_
            FormatStateManager.shared.setActiveProvider(formatProvider)
            
            // 同步编辑器上下文状态
            updateCurrentFormats()
            detectSpecialElementAtCursor()
        } else {
            // 编辑器失去焦点时，清除活动提供者
            // 注意：这里不清除，因为用户可能只是临时切换焦点
            // FormatStateManager.shared.clearActiveProvider()
        }
    }
    
    /// 发送编辑器焦点变化通知
    /// 
    /// 当编辑器焦点状态变化时，发送通知以更新菜单状态
    /// 
    /// _Requirements: 14.5_
    private func postEditorFocusNotification(_ focused: Bool) {
        NotificationCenter.default.post(
            name: .editorFocusDidChange,
            object: self,
            userInfo: ["isEditorFocused": focused]
        )
        print("[NativeEditorContext] 发送编辑器焦点变化通知: isEditorFocused=\(focused)")
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
            
            // 新增：递增版本号，强制触发视图更新
            // _Requirements: 3.1_
            contentVersion += 1
            
            // 新增：发送内容变化通知，确保 Coordinator 收到更新
            // _Requirements: 2.1, 2.2, 2.3_
            contentChangeSubject.send(mutableAttributed)
            
            // 调试日志：检查斜体字体是否正确保留
            print("[NativeEditorContext] 🔍 loadFromXML 完成后检查字体属性:")
            mutableAttributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                if let font = value as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    let rangeText = (mutableAttributed.string as NSString).substring(with: range)
                    print("[NativeEditorContext]   - 范围 \(range): '\(rangeText)'")
                    print("[NativeEditorContext]     字体: \(font.fontName), 大小: \(font.pointSize)")
                    print("[NativeEditorContext]     特性: bold=\(traits.contains(.bold)), italic=\(traits.contains(.italic))")
                }
            }
            
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
    /// 
    /// 将当前编辑器内容（nsAttributedText）转换为小米笔记 XML 格式
    /// 
    /// - Returns: 小米笔记 XML 格式内容
    /// - Note: 
    ///   - 使用 nsAttributedText 而不是 attributedText，因为 NativeEditorView 使用的是 nsAttributedText
    ///   - 空内容返回空字符串
    ///   - 转换失败时记录错误并返回空字符串
    /// 
    /// _Requirements: 2.1, 5.1_
    func exportToXML() -> String {
        // 处理空内容的情况
        // _Requirements: 5.1_
        guard nsAttributedText.length > 0 else {
            print("[NativeEditorContext] exportToXML: 内容为空，返回空字符串")
            return ""
        }
        
        // 检查是否只包含空白字符
        let trimmedString = nsAttributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedString.isEmpty {
            print("[NativeEditorContext] exportToXML: 内容仅包含空白字符，返回空字符串")
            return ""
        }
        
        do {
            // 关键修复：使用 nsAttributedText 而不是 attributedText
            // 因为 NativeEditorView 使用的是 nsAttributedText，编辑后的内容存储在这里
            // _Requirements: 2.1_
            let xmlContent = try formatConverter.nsAttributedStringToXML(nsAttributedText)
            
            print("[NativeEditorContext] exportToXML: 成功导出 XML - 长度: \(xmlContent.count)")
            return xmlContent
        } catch {
            // _Requirements: 9.3_ - 格式转换失败时记录错误日志
            print("[NativeEditorContext] exportToXML: 导出 XML 失败 - \(error)")
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
    /// 菜单栏格式菜单也需要调用此方法来获取当前格式状态
    public func forceUpdateFormats() {
        print("[NativeEditorContext] forceUpdateFormats 被调用")
        formatStateSynchronizer.performImmediateUpdate()
    }
    
    /// 请求从外部源同步内容
    /// 
    /// 当需要确保 nsAttributedText 是最新的时候调用此方法
    /// 这会发送一个通知，让 NativeEditorView 同步内容
    /// 菜单栏格式菜单需要调用此方法来确保内容是最新的
    public func requestContentSync() {
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
    /// 
    /// 配置内容变化监听，确保：
    /// 1. 通过 contentChangeSubject 发布内容变化
    /// 2. hasUnsavedChanges 正确更新
    /// 
    /// _Requirements: 2.1, 6.1_
    private func setupInternalObservers() {
        // 监听 nsAttributedText 变化
        // 当内容变化时，更新 hasUnsavedChanges 状态
        // _Requirements: 6.1_ - 内容未保存时显示"未保存"状态
        $nsAttributedText
            .dropFirst()
            .sink { [weak self] newContent in
                guard let self = self else { return }
                
                // 更新未保存状态
                // _Requirements: 6.1_
                self.hasUnsavedChanges = true
                
                // 发布内容变化通知
                // _Requirements: 2.1_ - 内容变化时触发保存流程
                // 注意：这里不直接发送 contentChangeSubject，因为 updateNSContent 方法已经会发送
                // 这里只处理通过 @Published 属性直接修改的情况
                print("[NativeEditorContext] 内容变化检测 - 长度: \(newContent.length), hasUnsavedChanges: true")
            }
            .store(in: &cancellables)
        
        // 监听 hasUnsavedChanges 变化，用于调试和状态同步
        // _Requirements: 6.1, 6.2, 6.3, 6.4_
        $hasUnsavedChanges
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] hasChanges in
                guard let self = self else { return }
                
                // 发送保存状态变化通知
                // _Requirements: 6.1, 6.2, 6.3, 6.4_
                NotificationCenter.default.post(
                    name: .nativeEditorSaveStatusDidChange,
                    object: self,
                    userInfo: ["hasUnsavedChanges": hasChanges]
                )
                
                print("[NativeEditorContext] 保存状态变化: hasUnsavedChanges = \(hasChanges)")
            }
            .store(in: &cancellables)
    }
    
    /// 标记内容已保存
    /// 
    /// 当内容成功保存后调用此方法，重置 hasUnsavedChanges 状态
    /// 
    /// _Requirements: 6.3_ - 保存完成时显示"已保存"状态
    public func markContentSaved() {
        hasUnsavedChanges = false
        // 清除备份内容和错误状态
        clearSaveErrorState()
        print("[NativeEditorContext] 内容已标记为已保存")
    }
    
    // MARK: - 内容保护方法
    // _Requirements: 2.5, 9.1_ - 保存失败时的内容保护
    
    /// 备份当前内容
    /// 
    /// 在保存操作开始前调用，备份当前编辑内容
    /// 如果保存失败，可以使用备份内容进行恢复或重试
    /// 
    /// _Requirements: 2.5, 9.1_
    public func backupCurrentContent() {
        backupContent = nsAttributedText.copy() as? NSAttributedString
        print("[NativeEditorContext] 📦 内容已备份 - 长度: \(nsAttributedText.length)")
    }
    
    /// 标记保存失败
    /// 
    /// 当保存操作失败时调用此方法，记录错误信息并保留编辑内容
    /// 
    /// - Parameter error: 错误信息
    /// 
    /// _Requirements: 2.5, 9.1_
    public func markSaveFailed(error: String) {
        lastSaveError = error
        hasPendingRetry = true
        // 确保内容已备份
        if backupContent == nil {
            backupCurrentContent()
        }
        print("[NativeEditorContext] ❌ 保存失败已标记 - 错误: \(error)")
        print("[NativeEditorContext]   - 备份内容长度: \(backupContent?.length ?? 0)")
        print("[NativeEditorContext]   - hasPendingRetry: \(hasPendingRetry)")
    }
    
    /// 清除保存错误状态
    /// 
    /// 当保存成功或用户取消重试时调用
    /// 
    /// _Requirements: 9.1_
    public func clearSaveErrorState() {
        backupContent = nil
        lastSaveError = nil
        hasPendingRetry = false
        print("[NativeEditorContext] 🧹 保存错误状态已清除")
    }
    
    /// 获取待保存的内容
    /// 
    /// 优先返回备份内容（如果有），否则返回当前内容
    /// 用于重试保存操作
    /// 
    /// - Returns: 待保存的 NSAttributedString
    /// 
    /// _Requirements: 9.1_
    public func getContentForRetry() -> NSAttributedString {
        if let backup = backupContent {
            print("[NativeEditorContext] 📤 使用备份内容进行重试 - 长度: \(backup.length)")
            return backup
        }
        print("[NativeEditorContext] 📤 使用当前内容进行重试 - 长度: \(nsAttributedText.length)")
        return nsAttributedText
    }
    
    /// 从备份恢复内容
    /// 
    /// 如果有备份内容，将其恢复到编辑器
    /// 
    /// - Returns: 是否成功恢复
    /// 
    /// _Requirements: 9.1_
    @discardableResult
    public func restoreFromBackup() -> Bool {
        guard let backup = backupContent else {
            print("[NativeEditorContext] ⚠️ 无备份内容可恢复")
            return false
        }
        nsAttributedText = backup
        hasUnsavedChanges = true
        print("[NativeEditorContext] ✅ 内容已从备份恢复 - 长度: \(backup.length)")
        return true
    }
    
    /// 通知内容变化
    /// 
    /// 手动触发内容变化通知，用于需要强制触发保存流程的场景
    /// 
    /// _Requirements: 2.1_ - 触发保存流程
    public func notifyContentChange() {
        contentChangeSubject.send(nsAttributedText)
        hasUnsavedChanges = true
        print("[NativeEditorContext] 手动触发内容变化通知")
    }
    
    /// 根据当前光标位置更新格式状态 (需求 9.1)
    /// 增强版本 - 完善所有格式类型的状态检测
    /// 需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10
    /// 混合格式需求: 6.1, 6.2
    /// 错误处理需求: 4.2 - 状态同步失败时重新检测格式状态并更新界面
    func updateCurrentFormats() {
        print("[NativeEditorContext] ========================================")
        print("[NativeEditorContext] 🔄 开始更新当前格式状态")
        print("[NativeEditorContext] ========================================")
        print("[NativeEditorContext]   - 文本长度: \(nsAttributedText.length)")
        print("[NativeEditorContext]   - 光标位置: \(cursorPosition)")
        print("[NativeEditorContext]   - 选中范围: location=\(selectedRange.location), length=\(selectedRange.length)")
        
        // 需求 4.2: 状态同步错误处理
        let errorHandler = FormatErrorHandler.shared
        
        guard !nsAttributedText.string.isEmpty else {
            print("[NativeEditorContext]   ⚠️ 文本为空，清除所有格式")
            clearAllFormats()
            clearMixedFormatStates()
            print("[NativeEditorContext] ========================================")
            return
        }
        
        // 确保位置有效
        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            print("[NativeEditorContext]   ❌ 位置无效 (position: \(position))，清除所有格式")
            clearAllFormats()
            clearMixedFormatStates()
            print("[NativeEditorContext] ========================================")
            return
        }
        
        print("[NativeEditorContext]   ✅ 有效位置: \(position)")
        
        // 需求 6.1, 6.2: 如果有选中范围，检测混合格式状态
        if selectedRange.length > 0 {
            print("[NativeEditorContext]   📝 选中了文本，检测混合格式状态 (选中长度: \(selectedRange.length))")
            updateMixedFormatStates()
        } else {
            print("[NativeEditorContext]   📍 光标模式（未选中文本）")
            // 清除混合格式状态
            clearMixedFormatStates()
        }
        
        // 获取当前位置的属性
        // 关键修复：当没有选中文字时（光标模式），应该获取光标前一个字符的属性
        // 因为光标实际上是在字符之间的，用户期望看到的是光标左侧文字的格式
        var attributePosition = position
        if selectedRange.length == 0 && position > 0 {
            // 光标模式：获取光标前一个字符的属性
            attributePosition = position - 1
            print("[NativeEditorContext]   💡 光标模式：使用前一个字符的属性位置: \(attributePosition)")
        }
        
        let attributes = nsAttributedText.attributes(at: attributePosition, effectiveRange: nil)
        print("[NativeEditorContext]   📦 获取到 \(attributes.count) 个属性")
        
        // 检测所有格式类型
        var detectedFormats: Set<TextFormat> = []
        
        print("[NativeEditorContext] ----------------------------------------")
        print("[NativeEditorContext] 🔍 开始检测各类格式...")
        print("[NativeEditorContext] ----------------------------------------")
        
        // 1. 检测字体属性（加粗、斜体、标题）
        let fontFormats = detectFontFormats(from: attributes)
        detectedFormats.formUnion(fontFormats)
        print("[NativeEditorContext]   ✅ 字体格式检测完成: \(fontFormats.map { $0.displayName })")
        
        // 2. 检测文本装饰（下划线、删除线、高亮）
        let decorationFormats = detectTextDecorations(from: attributes)
        detectedFormats.formUnion(decorationFormats)
        print("[NativeEditorContext]   ✅ 装饰格式检测完成: \(decorationFormats.map { $0.displayName })")
        
        // 3. 检测段落格式（对齐方式）
        let paragraphFormats = detectParagraphFormats(from: attributes)
        detectedFormats.formUnion(paragraphFormats)
        print("[NativeEditorContext]   ✅ 段落格式检测完成: \(paragraphFormats.map { $0.displayName })")
        
        // 4. 检测列表格式（无序、有序、复选框）
        let listFormats = detectListFormats(at: attributePosition)
        detectedFormats.formUnion(listFormats)
        print("[NativeEditorContext]   ✅ 列表格式检测完成: \(listFormats.map { $0.displayName })")
        
        // 5. 检测特殊元素格式（引用块、分割线）
        let specialFormats = detectSpecialElementFormats(at: attributePosition)
        detectedFormats.formUnion(specialFormats)
        print("[NativeEditorContext]   ✅ 特殊格式检测完成: \(specialFormats.map { $0.displayName })")
        
        // 需求 6.1: 如果有选中范围，合并混合格式检测结果
        if selectedRange.length > 0 {
            let mixedHandler = MixedFormatStateHandler.shared
            let activeFormats = mixedHandler.getActiveFormats(in: nsAttributedText, range: selectedRange)
            detectedFormats.formUnion(activeFormats)
            print("[NativeEditorContext]   ✅ 混合格式检测完成: \(activeFormats.map { $0.displayName })")
        }
        
        print("[NativeEditorContext] ----------------------------------------")
        print("[NativeEditorContext] 📊 最终检测到的所有格式: \(detectedFormats.map { $0.displayName })")
        print("[NativeEditorContext] ----------------------------------------")
        
        // 更新状态并验证
        updateFormatsWithValidation(detectedFormats)
        
        print("[NativeEditorContext] ========================================")
        print("[NativeEditorContext] ✅ 格式状态更新完成")
        print("[NativeEditorContext] ========================================")
    }
    
    /// 更新混合格式状态
    /// 需求: 6.1, 6.2
    private func updateMixedFormatStates() {
        let mixedHandler = MixedFormatStateHandler.shared
        let states = mixedHandler.detectMixedFormatStates(in: nsAttributedText, range: selectedRange)
        
        // 更新部分激活格式集合
        var newPartiallyActive: Set<TextFormat> = []
        var newRatios: [TextFormat: Double] = [:]
        
        for (format, state) in states {
            newRatios[format] = state.activationRatio
            if state.isPartiallyActive {
                newPartiallyActive.insert(format)
            }
        }
        
        partiallyActiveFormats = newPartiallyActive
        formatActivationRatios = newRatios
        
        print("[NativeEditorContext]   - 部分激活格式: \(newPartiallyActive.map { $0.displayName })")
    }
    
    /// 清除混合格式状态
    private func clearMixedFormatStates() {
        partiallyActiveFormats.removeAll()
        formatActivationRatios.removeAll()
    }
    
    /// 检测字体格式（加粗、斜体、标题）
    /// 需求: 2.1, 2.2, 2.6
    /// 
    /// 标题检测完全基于字体大小，因为在小米笔记中字体大小和标题类型是一一对应的：
    /// - 23pt = 大标题
    /// - 20pt = 二级标题
    /// - 17pt = 三级标题
    /// - 14pt = 正文
    /// 
    /// _Requirements: 3.1, 3.2, 3.3, 3.4, 6.2, 6.3, 6.4, 6.5_ - 使用 FontSizeManager 统一检测逻辑
    private func detectFontFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        print("[NativeEditorContext] ========== 开始检测字体格式 ==========")
        // 调试：打印所有属性键
        print("[NativeEditorContext] detectFontFormats - 属性键: \(attributes.keys.map { $0.rawValue })")
        
        guard let font = attributes[.font] as? NSFont else {
            print("[NativeEditorContext] ❌ 没有找到 .font 属性，无法继续检测")
            print("[NativeEditorContext] ========== 检测结束（无字体） ==========")
            return formats
        }
        
        let fontSize = font.pointSize
        print("[NativeEditorContext] 📏 字体信息:")
        print("[NativeEditorContext]   - 字体名称: \(font.fontName)")
        print("[NativeEditorContext]   - 字体大小: \(fontSize)pt")
        
        // 检测字体特性
        let traits = font.fontDescriptor.symbolicTraits
        print("[NativeEditorContext]   - 字体特性: bold=\(traits.contains(.bold)), italic=\(traits.contains(.italic))")
        
        // 通过字体大小检测标题格式
        // 在小米笔记中，字体大小和标题类型是一一对应的，不需要额外的 headingLevel 属性
        print("[NativeEditorContext] 🔍 通过字体大小判断标题类型")
        print("[NativeEditorContext]   当前阈值: 大标题>=\(FontSizeManager.shared.heading1Threshold)pt, 二级标题>=\(FontSizeManager.shared.heading2Threshold)pt, 三级标题>=\(FontSizeManager.shared.heading3Threshold)pt")
        
        // 使用 FontSizeManager 的统一检测逻辑
        let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: fontSize)
        switch detectedFormat {
        case .heading1:
            formats.insert(.heading1)
            print("[NativeEditorContext] ✅ 字体大小 \(fontSize)pt >= \(FontSizeManager.shared.heading1Threshold)pt，识别为【大标题】")
        case .heading2:
            formats.insert(.heading2)
            print("[NativeEditorContext] ✅ 字体大小 \(fontSize)pt 在 [\(FontSizeManager.shared.heading2Threshold), \(FontSizeManager.shared.heading1Threshold)) 范围内，识别为【二级标题】")
        case .heading3:
            formats.insert(.heading3)
            print("[NativeEditorContext] ✅ 字体大小 \(fontSize)pt 在 [\(FontSizeManager.shared.heading3Threshold), \(FontSizeManager.shared.heading2Threshold)) 范围内，识别为【三级标题】")
        default:
            print("[NativeEditorContext] ✅ 字体大小 \(fontSize)pt < \(FontSizeManager.shared.heading3Threshold)pt，识别为【正文】（不添加标题格式）")
        }
        
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
            print("[NativeEditorContext] detectFontFormats - 检测到斜体（字体特性）")
        }
        
        print("[NativeEditorContext] ========== 检测结束，最终格式: \(formats.map { $0.displayName }) ==========")
        return formats
    }
    
    /// 检测斜体格式（使用 obliqueness 属性）
    /// 需求: 2.2 - 斜体检测
    /// 
    /// 由于中文字体（如苹方）通常没有真正的斜体变体，
    /// 我们使用 obliqueness 属性来实现和检测斜体效果
    private func detectItalicFromObliqueness(from attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            print("[NativeEditorContext] detectItalicFromObliqueness - 检测到 obliqueness: \(obliqueness)")
            return true
        }
        return false
    }
    
    /// 检测文本装饰（下划线、删除线、高亮、斜体）
    /// 需求: 2.2, 2.3, 2.4, 2.5
    private func detectTextDecorations(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []
        
        // 斜体检测 - 使用 obliqueness 属性
        // 这是为了支持中文斜体，因为中文字体通常没有真正的斜体变体
        if detectItalicFromObliqueness(from: attributes) {
            formats.insert(.italic)
            print("[NativeEditorContext] detectTextDecorations - 检测到斜体（obliqueness）")
        }
        
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
        
        // 获取当前行的范围
        let lineRange = getLineRange(at: position)
        guard lineRange.location < nsAttributedText.length else {
            return formats
        }
        
        // 检查当前行开头的属性
        let lineAttributes = nsAttributedText.attributes(at: lineRange.location, effectiveRange: nil)
        
        // 方法 1: 检查 listType 自定义属性（最可靠的方式）
        if let listType = lineAttributes[.listType] {
            print("[NativeEditorContext] detectListFormats - 检测到 listType: \(listType)")
            // listType 可能是 ListType 枚举或字符串
            if let listTypeEnum = listType as? ListType {
                switch listTypeEnum {
                case .bullet:
                    formats.insert(.bulletList)
                    print("[NativeEditorContext] detectListFormats - 检测到无序列表 (ListType.bullet)")
                case .ordered:
                    formats.insert(.numberedList)
                    print("[NativeEditorContext] detectListFormats - 检测到有序列表 (ListType.ordered)")
                case .checkbox:
                    formats.insert(.checkbox)
                    print("[NativeEditorContext] detectListFormats - 检测到复选框 (ListType.checkbox)")
                case .none:
                    break
                }
            } else if let listTypeString = listType as? String {
                if listTypeString == "bullet" {
                    formats.insert(.bulletList)
                    print("[NativeEditorContext] detectListFormats - 检测到无序列表 (string: bullet)")
                } else if listTypeString == "ordered" || listTypeString == "order" {
                    formats.insert(.numberedList)
                    print("[NativeEditorContext] detectListFormats - 检测到有序列表 (string: \(listTypeString))")
                } else if listTypeString == "checkbox" {
                    formats.insert(.checkbox)
                    print("[NativeEditorContext] detectListFormats - 检测到复选框 (string: checkbox)")
                }
            }
        }
        
        // 方法 2: 检查附件（备用方式）
        if formats.isEmpty {
            // 检查当前位置是否有附件
            let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)
            
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                // 检测复选框
                if attachment is InteractiveCheckboxAttachment {
                    formats.insert(.checkbox)
                    print("[NativeEditorContext] detectListFormats - 检测到复选框 (当前位置附件)")
                }
                // 检测无序列表
                else if attachment is BulletAttachment {
                    formats.insert(.bulletList)
                    print("[NativeEditorContext] detectListFormats - 检测到无序列表 (当前位置附件)")
                }
                // 检测有序列表
                else if attachment is OrderAttachment {
                    formats.insert(.numberedList)
                    print("[NativeEditorContext] detectListFormats - 检测到有序列表 (当前位置附件)")
                }
            }
            
            // 如果当前位置没有附件，检查当前行的开头
            if formats.isEmpty {
                if let attachment = lineAttributes[.attachment] as? NSTextAttachment {
                    if attachment is InteractiveCheckboxAttachment {
                        formats.insert(.checkbox)
                        print("[NativeEditorContext] detectListFormats - 检测到复选框 (行开头附件)")
                    } else if attachment is BulletAttachment {
                        formats.insert(.bulletList)
                        print("[NativeEditorContext] detectListFormats - 检测到无序列表 (行开头附件)")
                    } else if attachment is OrderAttachment {
                        formats.insert(.numberedList)
                        print("[NativeEditorContext] detectListFormats - 检测到有序列表 (行开头附件)")
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
    /// 需求: 4.2 - 状态同步失败时重新检测格式状态并更新界面
    /// 需求: 14.6 - 段落样式变化时发送通知更新菜单状态
    private func updateFormatsWithValidation(_ detectedFormats: Set<TextFormat>) {
        let errorHandler = FormatErrorHandler.shared
        
        do {
            // 验证互斥格式
            let validatedFormats = validateMutuallyExclusiveFormats(detectedFormats)
            
            // 检查状态一致性
            let previousFormats = currentFormats
            
            // 检测段落样式变化（用于发送通知）
            // _Requirements: 14.6_
            let previousParagraphStyle = detectParagraphStyleFromFormats(previousFormats)
            
            // 更新当前格式
            currentFormats = validatedFormats
            
            // 更新工具栏按钮状态
            for format in TextFormat.allCases {
                toolbarButtonStates[format] = validatedFormats.contains(format)
            }
            
            // 检测新的段落样式并发送通知（如果变化）
            // _Requirements: 14.6_
            let newParagraphStyle = detectParagraphStyleFromFormats(validatedFormats)
            if previousParagraphStyle != newParagraphStyle {
                postParagraphStyleNotification(newParagraphStyle)
            }
            
            // 验证状态更新是否成功
            if currentFormats != validatedFormats {
                // 状态不一致，记录错误
                let context = FormatErrorContext(
                    operation: "updateFormatsWithValidation",
                    format: nil,
                    selectedRange: selectedRange,
                    textLength: nsAttributedText.length,
                    cursorPosition: cursorPosition,
                    additionalInfo: [
                        "previousFormats": previousFormats.map { $0.displayName },
                        "expectedFormats": validatedFormats.map { $0.displayName },
                        "actualFormats": currentFormats.map { $0.displayName }
                    ]
                )
                errorHandler.handleError(
                    .stateInconsistency(
                        expected: validatedFormats.map { $0.displayName }.joined(separator: ", "),
                        actual: currentFormats.map { $0.displayName }.joined(separator: ", ")
                    ),
                    context: context
                )
            }
            
            // 记录格式变化（调试用）
            #if DEBUG
            if !validatedFormats.isEmpty {
                let formatNames = validatedFormats.map { $0.displayName }.joined(separator: ", ")
                print("[NativeEditorContext] 检测到格式: \(formatNames)")
            }
            #endif
            
            // 成功后重置错误计数
            errorHandler.resetErrorCount()
        } catch {
            // 需求 4.2: 状态同步失败时重新检测格式状态
            let context = FormatErrorContext(
                operation: "updateFormatsWithValidation",
                format: nil,
                selectedRange: selectedRange,
                textLength: nsAttributedText.length,
                cursorPosition: cursorPosition,
                additionalInfo: nil
            )
            let result = errorHandler.handleError(
                .stateSyncFailed(reason: error.localizedDescription),
                context: context
            )
            
            // 根据恢复操作执行相应处理
            if result.recoveryAction == .forceStateUpdate {
                // 清除所有格式并重新检测
                clearAllFormats()
            }
        }
    }
    
    // MARK: - 公共方法 - 段落样式查询
    
    /// 获取当前段落样式字符串
    /// 
    /// 根据当前格式集合返回对应的段落样式字符串
    /// 用于菜单栏勾选状态同步
    /// 
    /// _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
    /// - Returns: 段落样式字符串（heading, subheading, subtitle, body, orderedList, unorderedList, blockQuote）
    public func getCurrentParagraphStyleString() -> String {
        let result = detectParagraphStyleFromFormats(currentFormats)
        print("[NativeEditorContext] getCurrentParagraphStyleString - currentFormats: \(currentFormats.map { $0.displayName }), result: \(result)")
        return result
    }
    
    /// 从格式集合中检测段落样式
    /// 
    /// 将 TextFormat 映射到段落样式字符串（用于菜单状态同步）
    /// 
    /// _Requirements: 14.6_
    private func detectParagraphStyleFromFormats(_ formats: Set<TextFormat>) -> String {
        print("[NativeEditorContext] ========== 开始转换格式为段落样式 ==========")
        print("[NativeEditorContext] 输入格式集合: \(formats.map { $0.displayName })")
        
        let paragraphStyle: String
        
        if formats.contains(.heading1) {
            paragraphStyle = "heading"
            print("[NativeEditorContext] ✅ 检测到 heading1 格式，返回段落样式: 【heading】(大标题)")
        } else if formats.contains(.heading2) {
            paragraphStyle = "subheading"
            print("[NativeEditorContext] ✅ 检测到 heading2 格式，返回段落样式: 【subheading】(二级标题)")
        } else if formats.contains(.heading3) {
            paragraphStyle = "subtitle"
            print("[NativeEditorContext] ✅ 检测到 heading3 格式，返回段落样式: 【subtitle】(三级标题)")
        } else if formats.contains(.numberedList) {
            paragraphStyle = "orderedList"
            print("[NativeEditorContext] ✅ 检测到 numberedList 格式，返回段落样式: 【orderedList】(有序列表)")
        } else if formats.contains(.bulletList) {
            paragraphStyle = "unorderedList"
            print("[NativeEditorContext] ✅ 检测到 bulletList 格式，返回段落样式: 【unorderedList】(无序列表)")
        } else if formats.contains(.quote) {
            paragraphStyle = "blockQuote"
            print("[NativeEditorContext] ✅ 检测到 quote 格式，返回段落样式: 【blockQuote】(引用)")
        } else {
            paragraphStyle = "body"
            print("[NativeEditorContext] ✅ 没有检测到任何块级格式，返回默认段落样式: 【body】(正文)")
        }
        
        print("[NativeEditorContext] ========== 段落样式转换完成: \(paragraphStyle) ==========")
        return paragraphStyle
    }
    
    /// 发送段落样式变化通知
    /// 
    /// 当段落样式变化时，发送通知以更新菜单状态
    /// 
    /// _Requirements: 14.6_
    private func postParagraphStyleNotification(_ paragraphStyleRaw: String) {
        NotificationCenter.default.post(
            name: .paragraphStyleDidChange,
            object: self,
            userInfo: ["paragraphStyle": paragraphStyleRaw]
        )
        print("[NativeEditorContext] 发送段落样式变化通知: paragraphStyle=\(paragraphStyleRaw)")
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
    
    // MARK: - Public Methods - 缩放操作 (Requirements: 10.2, 10.3, 10.4)
    
    /// 放大
    /// - Requirements: 10.2
    func zoomIn() {
        print("[NativeEditorContext] 放大")
        // 发送缩放通知，让编辑器视图处理
        NotificationCenter.default.post(name: .editorZoomIn, object: nil)
    }
    
    /// 缩小
    /// - Requirements: 10.3
    func zoomOut() {
        print("[NativeEditorContext] 缩小")
        // 发送缩放通知，让编辑器视图处理
        NotificationCenter.default.post(name: .editorZoomOut, object: nil)
    }
    
    /// 重置缩放
    /// - Requirements: 10.4
    func resetZoom() {
        print("[NativeEditorContext] 重置缩放")
        // 发送重置缩放通知，让编辑器视图处理
        NotificationCenter.default.post(name: .editorResetZoom, object: nil)
    }
}

// MARK: - 缩放通知扩展

extension Notification.Name {
    /// 编辑器放大通知
    static let editorZoomIn = Notification.Name("editorZoomIn")
    /// 编辑器缩小通知
    static let editorZoomOut = Notification.Name("editorZoomOut")
    /// 编辑器重置缩放通知
    static let editorResetZoom = Notification.Name("editorResetZoom")
}