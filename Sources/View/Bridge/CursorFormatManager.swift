//
//  CursorFormatManager.swift
//  MiNoteMac
//
//  光标格式管理器 - 统一管理光标位置的格式检测、工具栏同步和输入格式继承
//  负责协调格式检测、工具栏同步和 typingAttributes 同步
//
//  _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_
//

import Foundation
import AppKit
import Combine

// MARK: - 光标格式检测错误

/// 光标格式检测错误
/// _Requirements: 5.5_
public enum CursorFormatDetectionError: Error, CustomStringConvertible {
    case textViewUnavailable
    case textStorageEmpty
    case invalidPosition
    case attributeExtractionFailed
    
    public var description: String {
        switch self {
        case .textViewUnavailable:
            return "NSTextView 不可用"
        case .textStorageEmpty:
            return "文本存储为空"
        case .invalidPosition:
            return "无效的光标位置"
        case .attributeExtractionFailed:
            return "属性提取失败"
        }
    }
}

// MARK: - 格式检测结果

/// 格式检测结果
/// _Requirements: 1.1-1.6_
public struct FormatDetectionResult {
    /// 检测到的格式状态
    public let state: FormatState
    
    /// 检测位置
    public let position: Int
    
    /// 是否为光标模式（无选择）
    public let isCursorMode: Bool
    
    /// 检测时间戳
    public let timestamp: Date
    
    public init(state: FormatState, position: Int, isCursorMode: Bool, timestamp: Date = Date()) {
        self.state = state
        self.position = position
        self.isCursorMode = isCursorMode
        self.timestamp = timestamp
    }
}

// MARK: - 光标格式管理器

/// 光标格式管理器
/// 统一管理光标位置的格式检测、工具栏同步和输入格式继承
/// _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_
@MainActor
public final class CursorFormatManager {
    
    // MARK: - Singleton
    
    /// 共享实例
    public static let shared = CursorFormatManager()
    
    // MARK: - Properties
    
    /// 当前关联的 NSTextView（弱引用）
    private weak var textView: NSTextView?
    
    /// 当前关联的 NativeEditorContext（弱引用）
    private weak var editorContext: NativeEditorContext?
    
    /// 防抖定时器
    private var debounceTimer: Timer?
    
    /// 防抖间隔（毫秒）
    /// _Requirements: 6.5_
    private let debounceInterval: TimeInterval = 0.05  // 50ms
    
    /// 当前检测到的格式状态
    /// _Requirements: 1.1-1.6_
    public private(set) var currentFormatState: FormatState = FormatState()
    
    /// 待处理的选择范围（用于防抖）
    private var pendingRange: NSRange?
    
    /// 是否已注册
    public private(set) var isRegistered: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        print("[CursorFormatManager] 初始化")
    }
    
    // MARK: - Public Methods - 注册/注销
    
    /// 注册编辑器组件
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - context: NativeEditorContext 实例
    /// _Requirements: 6.4_
    public func register(textView: NSTextView, context: NativeEditorContext) {
        print("[CursorFormatManager] 注册编辑器组件")
        self.textView = textView
        self.editorContext = context
        self.isRegistered = true
        
        // 初始化时检测当前格式状态
        let selectedRange = textView.selectedRange()
        handleSelectionChange(selectedRange)
    }
    
    /// 取消注册
    /// _Requirements: 6.4_
    public func unregister() {
        print("[CursorFormatManager] 取消注册")
        
        // 取消防抖定时器
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        // 清除引用
        textView = nil
        editorContext = nil
        isRegistered = false
        
        // 重置状态
        currentFormatState = FormatState()
        pendingRange = nil
    }
    
    // MARK: - Public Methods - 选择变化处理
    
    /// 处理光标位置变化
    /// 
    /// 此方法是 CursorFormatManager 的主要入口点，当光标位置或选择范围变化时调用。
    /// 它使用防抖机制来合并快速连续的变化，避免频繁的状态更新影响性能。
    /// 
    /// 处理流程：
    /// 1. 保存待处理的选择范围
    /// 2. 使用防抖机制调度更新（50ms 延迟）
    /// 3. 在 performUpdate() 中执行实际的格式检测和状态同步
    /// 
    /// - Parameter range: 新的选择范围
    ///   - 当 range.length == 0 时，表示光标模式（无选择）
    ///   - 当 range.length > 0 时，表示选择模式（有选中文字）
    /// 
    /// _Requirements: 3.1, 6.2_
    public func handleSelectionChange(_ range: NSRange) {
        // 保存待处理的范围
        pendingRange = range
        
        // 使用防抖机制
        // _Requirements: 6.5 - 支持防抖机制以避免频繁的状态更新影响性能
        scheduleUpdate()
    }
    
    /// 处理工具栏格式切换
    /// 
    /// 当用户通过工具栏点击格式按钮时调用此方法。
    /// 该方法负责：
    /// 1. 更新 currentFormatState 中对应格式的状态
    /// 2. 同步 typingAttributes 以确保后续输入应用新格式
    /// 3. 更新工具栏按钮状态以反映当前格式
    /// 4. 通知 FormatStateManager 以同步菜单栏状态
    /// 
    /// - Parameter format: 要切换的格式
    /// _Requirements: 4.1-4.6, 6.3_
    public func handleToolbarFormatToggle(_ format: TextFormat) {
        print("[CursorFormatManager] 处理工具栏格式切换: \(format.displayName)")
        
        // 更新当前格式状态
        var newState = currentFormatState
        
        // 切换格式状态
        // _Requirements: 4.1-4.5 - 处理各种格式的切换
        switch format {
        case .bold:
            // _Requirements: 4.1 - 加粗格式切换
            newState.isBold.toggle()
            print("[CursorFormatManager] 加粗状态切换为: \(newState.isBold)")
            
        case .italic:
            // _Requirements: 4.2 - 斜体格式切换
            newState.isItalic.toggle()
            print("[CursorFormatManager] 斜体状态切换为: \(newState.isItalic)")
            
        case .underline:
            // _Requirements: 4.3 - 下划线格式切换
            newState.isUnderline.toggle()
            print("[CursorFormatManager] 下划线状态切换为: \(newState.isUnderline)")
            
        case .strikethrough:
            // _Requirements: 4.4 - 删除线格式切换
            newState.isStrikethrough.toggle()
            print("[CursorFormatManager] 删除线状态切换为: \(newState.isStrikethrough)")
            
        case .highlight:
            // _Requirements: 4.5 - 高亮格式切换
            newState.isHighlight.toggle()
            print("[CursorFormatManager] 高亮状态切换为: \(newState.isHighlight)")
            
        case .quote:
            // 引用块格式切换
            newState.isQuote.toggle()
            print("[CursorFormatManager] 引用块状态切换为: \(newState.isQuote)")
            
        case .heading1:
            // 标题格式切换（互斥）
            newState.paragraphFormat = (newState.paragraphFormat == .heading1) ? .body : .heading1
            print("[CursorFormatManager] 段落格式切换为: \(newState.paragraphFormat.displayName)")
            
        case .heading2:
            newState.paragraphFormat = (newState.paragraphFormat == .heading2) ? .body : .heading2
            print("[CursorFormatManager] 段落格式切换为: \(newState.paragraphFormat.displayName)")
            
        case .heading3:
            newState.paragraphFormat = (newState.paragraphFormat == .heading3) ? .body : .heading3
            print("[CursorFormatManager] 段落格式切换为: \(newState.paragraphFormat.displayName)")
            
        case .bulletList:
            // 列表格式切换（互斥）
            newState.paragraphFormat = (newState.paragraphFormat == .bulletList) ? .body : .bulletList
            print("[CursorFormatManager] 段落格式切换为: \(newState.paragraphFormat.displayName)")
            
        case .numberedList:
            newState.paragraphFormat = (newState.paragraphFormat == .numberedList) ? .body : .numberedList
            print("[CursorFormatManager] 段落格式切换为: \(newState.paragraphFormat.displayName)")
            
        case .checkbox:
            newState.paragraphFormat = (newState.paragraphFormat == .checkbox) ? .body : .checkbox
            print("[CursorFormatManager] 段落格式切换为: \(newState.paragraphFormat.displayName)")
            
        case .alignCenter:
            // 对齐格式切换（互斥）
            newState.alignment = (newState.alignment == .center) ? .left : .center
            print("[CursorFormatManager] 对齐方式切换为: \(newState.alignment.displayName)")
            
        case .alignRight:
            newState.alignment = (newState.alignment == .right) ? .left : .right
            print("[CursorFormatManager] 对齐方式切换为: \(newState.alignment.displayName)")
            
        case .horizontalRule:
            // 分割线是插入操作，不是状态切换
            print("[CursorFormatManager] 分割线是插入操作，不更新格式状态")
            return
        }
        
        currentFormatState = newState
        
        // 同步 typingAttributes
        // _Requirements: 4.1-4.5 - 更新 Typing_Attributes 并在后续输入中应用格式
        syncTypingAttributes(with: newState)
        
        // 更新工具栏状态
        // _Requirements: 4.6 - Typing_Attributes 变化时更新工具栏
        updateToolbarState(with: newState)
        
        // 通知 FormatStateManager
        // _Requirements: 6.3 - 同步更新 Format_State 和 Typing_Attributes
        notifyFormatStateManager(with: newState)
        
        print("[CursorFormatManager] 工具栏格式切换处理完成")
    }
    
    /// 强制刷新格式状态
    public func forceRefresh() {
        print("[CursorFormatManager] 强制刷新格式状态")
        
        // 取消防抖定时器
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        // 立即执行更新
        performUpdate()
    }
}


// MARK: - Private Methods - 格式检测

extension CursorFormatManager {
    
    /// 检测光标位置的格式状态
    /// - Parameter position: 光标位置
    /// - Returns: 格式状态
    /// _Requirements: 1.1-1.6, 5.1-5.5_
    private func detectFormatState(at position: Int) -> FormatState {
        print("[CursorFormatManager] 检测格式状态 at position: \(position)")
        
        guard let textView = textView else {
            print("[CursorFormatManager] ⚠️ textView 不可用，使用默认格式状态")
            return FormatState.default
        }
        
        guard let textStorage = textView.textStorage else {
            print("[CursorFormatManager] ⚠️ textStorage 不可用，使用默认格式状态")
            return FormatState.default
        }
        
        // 边界条件：空文档
        // _Requirements: 5.4_
        guard textStorage.length > 0 else {
            print("[CursorFormatManager] 空文档，使用默认格式状态")
            return FormatState.default
        }
        
        // 边界条件：位置为 0
        // _Requirements: 5.1_
        guard position > 0 else {
            print("[CursorFormatManager] 位置为 0，使用默认格式状态")
            return FormatState.default
        }
        
        // 获取光标前一个字符的属性
        // _Requirements: 5.2, 5.3_
        let attributePosition = min(position - 1, textStorage.length - 1)
        guard attributePosition >= 0 else {
            print("[CursorFormatManager] 无效的属性位置，使用默认格式状态")
            return FormatState.default
        }
        
        let attributes = textStorage.attributes(at: attributePosition, effectiveRange: nil)
        print("[CursorFormatManager] 获取到 \(attributes.count) 个属性")
        
        // 构建格式状态
        var state = FormatState()
        
        // 检测字体属性（加粗、斜体）
        // _Requirements: 1.1, 1.2_
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            
            // 加粗检测
            if traits.contains(.bold) {
                state.isBold = true
                print("[CursorFormatManager] 检测到加粗")
            } else {
                // 备用检测：检查字体名称
                let fontName = font.fontName.lowercased()
                if fontName.contains("bold") {
                    state.isBold = true
                    print("[CursorFormatManager] 通过字体名称检测到加粗")
                }
            }
            
            // 斜体检测
            if traits.contains(.italic) {
                state.isItalic = true
                print("[CursorFormatManager] 检测到斜体")
            } else {
                // 备用检测：检查字体名称
                let fontName = font.fontName.lowercased()
                if fontName.contains("italic") || fontName.contains("oblique") {
                    state.isItalic = true
                    print("[CursorFormatManager] 通过字体名称检测到斜体")
                }
            }
            
            // 检测标题格式
            if let headingLevel = attributes[.headingLevel] as? Int {
                switch headingLevel {
                case 1:
                    state.paragraphFormat = .heading1
                    print("[CursorFormatManager] 检测到大标题")
                case 2:
                    state.paragraphFormat = .heading2
                    print("[CursorFormatManager] 检测到二级标题")
                case 3:
                    state.paragraphFormat = .heading3
                    print("[CursorFormatManager] 检测到三级标题")
                default:
                    break
                }
            }
        }
        
        // 斜体检测 - 使用 obliqueness 属性（支持中文斜体）
        // _Requirements: 1.2_
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            state.isItalic = true
            print("[CursorFormatManager] 通过 obliqueness 检测到斜体")
        }
        
        // 下划线检测
        // _Requirements: 1.3_
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            state.isUnderline = true
            print("[CursorFormatManager] 检测到下划线")
        }
        
        // 删除线检测
        // _Requirements: 1.4_
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            state.isStrikethrough = true
            print("[CursorFormatManager] 检测到删除线")
        }
        
        // 高亮检测
        // _Requirements: 1.5_
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            // 排除透明或白色背景
            if backgroundColor.alphaComponent > 0.1 && backgroundColor != .clear && backgroundColor != .white {
                state.isHighlight = true
                print("[CursorFormatManager] 检测到高亮")
            }
        }
        
        // 检测段落格式（对齐方式）
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            switch paragraphStyle.alignment {
            case .center:
                state.alignment = .center
                print("[CursorFormatManager] 检测到居中对齐")
            case .right:
                state.alignment = .right
                print("[CursorFormatManager] 检测到右对齐")
            default:
                state.alignment = .left
            }
        }
        
        // 检测引用块
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            state.isQuote = true
            print("[CursorFormatManager] 检测到引用块")
        }
        
        // 检测列表格式
        if let listType = attributes[.listType] {
            if let listTypeEnum = listType as? ListType {
                switch listTypeEnum {
                case .bullet:
                    state.paragraphFormat = .bulletList
                    print("[CursorFormatManager] 检测到无序列表")
                case .ordered:
                    state.paragraphFormat = .numberedList
                    print("[CursorFormatManager] 检测到有序列表")
                case .checkbox:
                    state.paragraphFormat = .checkbox
                    print("[CursorFormatManager] 检测到复选框")
                case .none:
                    break
                }
            } else if let listTypeString = listType as? String {
                switch listTypeString {
                case "bullet":
                    state.paragraphFormat = .bulletList
                case "ordered", "order":
                    state.paragraphFormat = .numberedList
                case "checkbox":
                    state.paragraphFormat = .checkbox
                default:
                    break
                }
            }
        }
        
        print("[CursorFormatManager] 格式状态检测完成: \(state)")
        return state
    }
    
    /// 处理格式检测错误
    /// - Parameter error: 格式检测错误
    /// _Requirements: 5.5_
    private func handleDetectionError(_ error: CursorFormatDetectionError) {
        print("[CursorFormatManager] 格式检测错误: \(error)")
        
        // 使用默认格式状态
        let defaultState = FormatState.default
        currentFormatState = defaultState
        
        // 同步到各个组件
        syncTypingAttributes(with: defaultState)
        updateToolbarState(with: defaultState)
        notifyFormatStateManager(with: defaultState)
    }
}


// MARK: - Private Methods - 防抖机制

extension CursorFormatManager {
    
    /// 调度更新（使用防抖）
    /// _Requirements: 6.5_
    private func scheduleUpdate() {
        // 取消之前的定时器
        debounceTimer?.invalidate()
        
        // 设置新的定时器
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performUpdate()
            }
        }
    }
    
    /// 执行更新
    /// 
    /// 此方法是光标位置变化处理的核心，负责：
    /// 1. 检测是否为光标模式（无选择）或选择模式
    /// 2. 在光标模式下：检测光标前一个字符的格式，同步 typingAttributes
    /// 3. 在选择模式下：检测选中文字的格式（使用选择起始位置的格式）
    /// 4. 更新工具栏状态和通知 FormatStateManager
    /// 
    /// _Requirements: 3.1, 6.2_
    private func performUpdate() {
        guard let range = pendingRange else {
            print("[CursorFormatManager] 没有待处理的范围")
            return
        }
        
        print("[CursorFormatManager] 执行更新 - range: \(range)")
        
        // 检测是否为光标模式（无选择）
        // _Requirements: 3.1 - 光标位置变化且没有选中文字
        let isCursorMode = range.length == 0
        
        if isCursorMode {
            // 光标模式：检测光标前一个字符的格式
            // _Requirements: 3.1 - 将 Typing_Attributes 更新为光标前一个字符的 Character_Attributes
            // _Requirements: 10.2 - 光标变化时调用 UnifiedFormatManager.detectFormatState
            let position = range.location
            
            // 优先使用 UnifiedFormatManager 检测格式状态
            let state: FormatState
            if UnifiedFormatManager.shared.isRegistered {
                state = UnifiedFormatManager.shared.detectFormatState(at: position)
                print("[CursorFormatManager] 使用 UnifiedFormatManager 检测格式状态")
            } else {
                state = detectFormatState(at: position)
            }
            
            // 更新当前格式状态
            currentFormatState = state
            currentFormatState.hasSelection = false
            currentFormatState.selectionLength = 0
            
            // 同步 typingAttributes
            // _Requirements: 3.1, 10.2 - 更新 Typing_Attributes
            syncTypingAttributes(with: state)
            
            // 更新工具栏状态
            // _Requirements: 6.2 - 自动执行工具栏更新
            updateToolbarState(with: state)
            
            // 通知 FormatStateManager
            // _Requirements: 6.2 - 自动执行格式检测
            notifyFormatStateManager(with: state)
            
            print("[CursorFormatManager] 光标模式更新完成 - position: \(position), state: \(state)")
        } else {
            // 选择模式：检测选中文字的格式
            // 使用选择起始位置的格式作为当前格式状态
            // _Requirements: 10.2 - 光标变化时调用 UnifiedFormatManager.detectFormatState
            let position = range.location
            
            // 优先使用 UnifiedFormatManager 检测格式状态
            var state: FormatState
            if UnifiedFormatManager.shared.isRegistered {
                state = UnifiedFormatManager.shared.detectFormatState(in: range)
                print("[CursorFormatManager] 使用 UnifiedFormatManager 检测选择范围格式状态")
            } else {
                state = detectFormatState(at: position)
            }
            
            // 更新选择信息
            state.hasSelection = true
            state.selectionLength = range.length
            currentFormatState = state
            
            // 在选择模式下，不更新 typingAttributes
            // 因为用户可能要对选中文字应用新格式
            
            // 更新工具栏状态
            // _Requirements: 6.2 - 自动执行工具栏更新
            updateToolbarState(with: state)
            
            // 通知 FormatStateManager
            notifyFormatStateManager(with: state)
            
            print("[CursorFormatManager] 选择模式更新完成 - range: \(range), state: \(state)")
        }
        
        // 清除待处理的范围
        pendingRange = nil
    }
}

// MARK: - Private Methods - 状态同步

extension CursorFormatManager {
    
    /// 同步 typingAttributes
    /// - Parameter state: 格式状态
    /// _Requirements: 3.1, 3.4, 10.3_
    private func syncTypingAttributes(with state: FormatState) {
        guard let textView = textView else {
            print("[CursorFormatManager] ⚠️ textView 不可用，无法同步 typingAttributes")
            return
        }
        
        print("[CursorFormatManager] 同步 typingAttributes")
        
        // 直接使用传入的 state 构建 typingAttributes
        // 不从 textStorage 读取，确保工具栏切换后的格式状态能正确应用到后续输入
        let attributes = FormatAttributesBuilder.build(from: state)
        textView.typingAttributes = attributes
        
        print("[CursorFormatManager] typingAttributes 已更新，属性数量: \(attributes.count)")
    }
    
    /// 更新工具栏状态
    /// - Parameter state: 格式状态
    /// _Requirements: 1.1-1.6, 4.6_
    private func updateToolbarState(with state: FormatState) {
        guard let editorContext = editorContext else {
            print("[CursorFormatManager] ⚠️ editorContext 不可用，无法更新工具栏状态")
            return
        }
        
        print("[CursorFormatManager] 更新工具栏状态")
        
        // 更新 currentFormats
        let formats = state.toTextFormats()
        editorContext.currentFormats = formats
        
        // 更新 toolbarButtonStates
        for format in TextFormat.allCases {
            editorContext.toolbarButtonStates[format] = state.isFormatActive(format)
        }
        
        print("[CursorFormatManager] 工具栏状态已更新，激活格式: \(formats.map { $0.displayName })")
    }
    
    /// 通知 FormatStateManager
    /// - Parameter state: 格式状态
    /// 
    /// 此方法负责确保格式状态变化被正确传播到所有相关组件：
    /// 1. 发送 `.formatStateDidChange` 通知，MenuManager 监听此通知更新菜单栏
    /// 2. 触发 NativeFormatProvider 的状态发布，FormatStateManager 订阅此发布者更新全局状态
    /// 
    /// _Requirements: 6.6_
    private func notifyFormatStateManager(with state: FormatState) {
        print("[CursorFormatManager] 通知 FormatStateManager - state: \(state)")
        
        // 1. 发送格式状态变化通知
        // MenuManager 监听此通知来更新菜单栏格式状态
        NotificationCenter.default.post(
            name: .formatStateDidChange,
            object: self,
            userInfo: ["state": state]
        )
        
        // 2. 触发 NativeFormatProvider 的状态发布
        // FormatStateManager 订阅 NativeFormatProvider 的 formatStatePublisher
        // 通过强制更新 NativeFormatProvider 的状态，确保 FormatStateManager 也收到更新
        if let editorContext = editorContext {
            editorContext.formatProvider.forceStateUpdate()
            print("[CursorFormatManager] 已触发 NativeFormatProvider 状态更新")
        }
    }
}

// MARK: - FormatAttributesBuilder
// FormatAttributesBuilder 已移至单独的文件: FormatAttributesBuilder.swift
// _Requirements: 2.1-2.6, 3.1_
