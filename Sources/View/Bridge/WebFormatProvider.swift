//
//  WebFormatProvider.swift
//  MiNoteMac
//
//  Web 编辑器格式提供者 - 实现 FormatMenuProvider 协议
//  为 Web 编辑器提供统一的格式状态获取和应用接口
//  桥接 WebEditorContext 和 FormatStateManager，使菜单栏格式菜单能够正确显示 Web 编辑器的格式状态
//
//  _Requirements: 3.1, 3.2, 3.3, 7.1, 7.2, 7.3, 7.4, 8.1, 8.2, 8.3_
//

import Foundation
import Combine
import SwiftUI

// MARK: - WebFormatProvider

/// Web 编辑器格式提供者
/// 实现 FormatMenuProvider 协议，为 Web 编辑器提供格式操作接口
/// _Requirements: 3.1, 3.2, 3.3, 7.1, 7.2, 7.3, 7.4_
@MainActor
final class WebFormatProvider: FormatMenuProvider {
    
    // MARK: - Properties
    
    /// Web 编辑器上下文（弱引用，避免循环引用）
    private weak var webEditorContext: WebEditorContext?
    
    /// 格式状态变化主题
    private let formatStateSubject = PassthroughSubject<FormatState, Never>()
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 防抖定时器
    private var debounceTimer: Timer?
    
    /// 防抖间隔（毫秒）- 满足需求 10.1 的 50ms 要求
    /// _Requirements: 10.1_
    private let debounceInterval: TimeInterval = 0.05  // 50ms
    
    /// 上次状态（用于增量更新）
    private var lastState: FormatState?
    
    // MARK: - FormatMenuProvider Protocol Properties
    
    /// 编辑器类型
    /// _Requirements: 7.4_
    var editorType: EditorType {
        return .web
    }
    
    /// 编辑器是否可用
    var isEditorAvailable: Bool {
        guard let context = webEditorContext else { return false }
        return context.isEditorReady
    }
    
    /// 格式状态变化发布者
    /// _Requirements: 8.1, 8.2, 8.3_
    var formatStatePublisher: AnyPublisher<FormatState, Never> {
        formatStateSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    /// 初始化格式提供者
    /// - Parameter webEditorContext: Web 编辑器上下文
    init(webEditorContext: WebEditorContext) {
        self.webEditorContext = webEditorContext
        setupObservers()
    }
    
    // MARK: - FormatMenuProvider Protocol Methods - 状态获取
    
    /// 获取当前格式状态
    /// - Returns: 当前格式状态
    /// _Requirements: 7.1_
    func getCurrentFormatState() -> FormatState {
        guard let context = webEditorContext else {
            return FormatState.default
        }
        
        var state = FormatState()
        
        // 从 WebEditorContext 读取字符级格式状态
        state.isBold = context.isBold
        state.isItalic = context.isItalic
        state.isUnderline = context.isUnderline
        state.isStrikethrough = context.isStrikethrough
        state.isHighlight = context.isHighlighted
        
        // 从 WebEditorContext 读取段落格式状态
        state.paragraphFormat = detectParagraphFormat(from: context)
        
        // 从 WebEditorContext 读取对齐格式状态
        state.alignment = detectAlignmentFormat(from: context)
        
        // 从 WebEditorContext 读取引用块状态
        state.isQuote = context.isInQuote
        
        // 从 WebEditorContext 读取选择状态
        state.hasSelection = context.hasSelection
        state.selectionLength = context.selectedText.count
        
        return state
    }
    
    /// 检查指定格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    /// _Requirements: 7.3_
    func isFormatActive(_ format: TextFormat) -> Bool {
        let state = getCurrentFormatState()
        return state.isFormatActive(format)
    }
    
    // MARK: - FormatMenuProvider Protocol Methods - 格式应用
    
    /// 应用格式
    /// - Parameter format: 要应用的格式
    /// - Note: 自动处理互斥规则
    /// _Requirements: 7.2_
    func applyFormat(_ format: TextFormat) {
        guard let context = webEditorContext else {
            return
        }
        
        // 根据格式类型调用 WebEditorContext 的相应方法
        switch format {
        case .bold:
            context.toggleBold()
        case .italic:
            context.toggleItalic()
        case .underline:
            context.toggleUnderline()
        case .strikethrough:
            context.toggleStrikethrough()
        case .highlight:
            context.toggleHighlight()
        case .heading1:
            context.setHeadingLevel(1)
        case .heading2:
            context.setHeadingLevel(2)
        case .heading3:
            context.setHeadingLevel(3)
        case .alignCenter:
            context.setTextAlignment(.center)
        case .alignRight:
            context.setTextAlignment(.trailing)
        case .bulletList:
            context.toggleBulletList()
        case .numberedList:
            context.toggleOrderList()
        case .checkbox:
            context.insertCheckbox()
        case .quote:
            context.toggleQuote()
        case .horizontalRule:
            context.insertHorizontalRule()
        }
        
        // 调度状态更新
        scheduleStateUpdate()
    }
    
    /// 切换格式
    /// - Parameter format: 要切换的格式
    /// - Note: 如果格式已激活则移除，否则应用
    func toggleFormat(_ format: TextFormat) {
        guard webEditorContext != nil else {
            return
        }
        
        // Web 编辑器的 toggle 方法会自动处理切换逻辑
        applyFormat(format)
    }
    
    /// 清除段落格式（恢复为正文）
    /// _Requirements: 2.2_
    func clearParagraphFormat() {
        guard webEditorContext != nil else {
            return
        }
        
        webEditorContext?.setHeadingLevel(nil)
        
        // 调度状态更新
        scheduleStateUpdate()
    }
    
    /// 清除对齐格式（恢复为左对齐）
    /// _Requirements: 3.2_
    func clearAlignmentFormat() {
        guard webEditorContext != nil else {
            return
        }
        
        webEditorContext?.setTextAlignment(.leading)
        
        // 调度状态更新
        scheduleStateUpdate()
    }
    
    // MARK: - Private Methods - 格式检测
    
    /// 从 WebEditorContext 检测段落格式
    /// - Parameter context: Web 编辑器上下文
    /// - Returns: 段落格式
    private func detectParagraphFormat(from context: WebEditorContext) -> ParagraphFormat {
        // 检查标题级别
        if let headingLevel = context.headingLevel {
            switch headingLevel {
            case 1: return .heading1
            case 2: return .heading2
            case 3: return .heading3
            default: break
            }
        }
        
        // 检查列表类型
        if let listType = context.listType {
            switch listType.lowercased() {
            case "bullet": return .bulletList
            case "order", "ordered": return .numberedList
            case "checkbox": return .checkbox
            default: break
            }
        }
        
        return .body
    }
    
    /// 从 WebEditorContext 检测对齐格式
    /// - Parameter context: Web 编辑器上下文
    /// - Returns: 对齐格式
    private func detectAlignmentFormat(from context: WebEditorContext) -> AlignmentFormat {
        switch context.textAlignment {
        case .center:
            return .center
        case .trailing:
            return .right
        default:
            return .left
        }
    }
    
    // MARK: - Private Methods - 状态更新
    
    /// 调度状态更新（带防抖）
    /// _Requirements: 10.1_
    private func scheduleStateUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performStateUpdate()
            }
        }
    }
    
    /// 执行状态更新
    private func performStateUpdate() {
        let state = getCurrentFormatState()
        
        // 增量更新：只有状态变化时才发送
        if let lastState = lastState, state == lastState {
            return
        }
        
        lastState = state
        formatStateSubject.send(state)
    }
    
    /// 立即执行状态更新（不使用防抖）
    func forceStateUpdate() {
        debounceTimer?.invalidate()
        lastState = nil  // 清除上次状态，强制发送
        performStateUpdate()
    }
    
    // MARK: - Private Methods - 观察者设置
    
    /// 设置观察者
    private func setupObservers() {
        guard let context = webEditorContext else { return }
        
        // 监听加粗状态变化
        context.$isBold
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听斜体状态变化
        context.$isItalic
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听下划线状态变化
        context.$isUnderline
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听删除线状态变化
        context.$isStrikethrough
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听高亮状态变化
        context.$isHighlighted
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听标题级别变化
        context.$headingLevel
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听对齐方式变化
        context.$textAlignment
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听列表类型变化
        context.$listType
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听引用块状态变化
        context.$isInQuote
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听选择状态变化
        context.$hasSelection
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
        
        // 监听编辑器就绪状态变化
        context.$isEditorReady
            .dropFirst()
            .sink { [weak self] isReady in
                if isReady {
                    self?.forceStateUpdate()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Deinit
    
    nonisolated deinit {
    }
}

// MARK: - WebFormatProvider 扩展 - 调试方法

extension WebFormatProvider {
    
    /// 打印当前格式状态（调试用）
    func printCurrentState() {
        let state = getCurrentFormatState()
        print("[WebFormatProvider] 当前格式状态:")
        print("  - 段落格式: \(state.paragraphFormat.displayName)")
        print("  - 对齐方式: \(state.alignment.displayName)")
        print("  - 加粗: \(state.isBold)")
        print("  - 斜体: \(state.isItalic)")
        print("  - 下划线: \(state.isUnderline)")
        print("  - 删除线: \(state.isStrikethrough)")
        print("  - 高亮: \(state.isHighlight)")
        print("  - 引用块: \(state.isQuote)")
        print("  - 有选择: \(state.hasSelection)")
        print("  - 选择长度: \(state.selectionLength)")
    }
}
