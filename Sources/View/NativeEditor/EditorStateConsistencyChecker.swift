//
//  EditorStateConsistencyChecker.swift
//  MiNoteMac
//
//  编辑器状态一致性检查器 - 监控编辑器状态并确保格式菜单按钮状态一致
//  需求: 4.3 - 当编辑器处于不可编辑状态时，格式菜单应禁用所有格式按钮
//

import Foundation
import AppKit
import Combine

// MARK: - 编辑器状态

/// 编辑器状态枚举
enum EditorState: Equatable {
    /// 正常可编辑状态
    case editable
    
    /// 只读状态
    case readOnly
    
    /// 未获得焦点
    case unfocused
    
    /// 无内容
    case empty
    
    /// 加载中
    case loading
    
    /// 错误状态
    case error(String)
    
    /// 是否允许格式操作
    var allowsFormatting: Bool {
        switch self {
        case .editable:
            return true
        case .readOnly, .unfocused, .empty, .loading, .error:
            return false
        }
    }
    
    /// 状态描述
    var description: String {
        switch self {
        case .editable:
            return "可编辑"
        case .readOnly:
            return "只读模式"
        case .unfocused:
            return "编辑器未获得焦点"
        case .empty:
            return "无内容"
        case .loading:
            return "加载中"
        case .error(let message):
            return "错误: \(message)"
        }
    }
    
    /// 用户提示消息
    var userMessage: String? {
        switch self {
        case .editable:
            return nil
        case .readOnly:
            return "当前为只读模式，无法编辑"
        case .unfocused:
            return "请先点击编辑器"
        case .empty:
            return "请先输入内容"
        case .loading:
            return "正在加载..."
        case .error(let message):
            return message
        }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: EditorState, rhs: EditorState) -> Bool {
        switch (lhs, rhs) {
        case (.editable, .editable),
             (.readOnly, .readOnly),
             (.unfocused, .unfocused),
             (.empty, .empty),
             (.loading, .loading):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// MARK: - 编辑器状态一致性检查器

/// 编辑器状态一致性检查器
/// 
/// 负责监控编辑器状态，确保格式菜单按钮状态与编辑器状态一致。
/// 当编辑器处于不可编辑状态时，自动禁用所有格式按钮。
/// 
/// 需求: 4.3
@MainActor
final class EditorStateConsistencyChecker: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = EditorStateConsistencyChecker()
    
    // MARK: - Published Properties
    
    /// 当前编辑器状态
    @Published private(set) var currentState: EditorState = .unfocused
    
    /// 格式按钮是否应该启用
    @Published private(set) var formatButtonsEnabled: Bool = false
    
    /// 状态变化原因
    @Published private(set) var stateChangeReason: String = ""
    
    // MARK: - Private Properties
    
    /// 日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 错误处理器
    private let errorHandler = FormatErrorHandler.shared
    
    /// 状态变化发布者
    private let stateChangeSubject = PassthroughSubject<EditorState, Never>()
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 上次状态检查时间
    private var lastCheckTime: Date = Date()
    
    /// 状态检查间隔（秒）
    private let checkInterval: TimeInterval = 0.1
    
    /// 连续不一致计数
    private var inconsistencyCount: Int = 0
    
    /// 不一致阈值
    private let inconsistencyThreshold: Int = 3
    
    // MARK: - Public Publishers
    
    /// 状态变化发布者
    var stateChangePublisher: AnyPublisher<EditorState, Never> {
        stateChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// 检查编辑器状态
    /// 
    /// - Parameters:
    ///   - textView: 文本视图
    ///   - context: 编辑器上下文
    /// - Returns: 当前编辑器状态
    func checkEditorState(textView: NSTextView?, context: NativeEditorContext?) -> EditorState {
        let newState = determineEditorState(textView: textView, context: context)
        
        if newState != currentState {
            updateState(newState, reason: "状态检查")
        }
        
        return newState
    }
    
    /// 更新编辑器状态
    /// 
    /// - Parameters:
    ///   - state: 新状态
    ///   - reason: 状态变化原因
    func updateState(_ state: EditorState, reason: String) {
        let previousState = currentState
        currentState = state
        stateChangeReason = reason
        formatButtonsEnabled = state.allowsFormatting
        
        // 记录状态变化
        logger.logInfo(
            "[EditorStateConsistencyChecker] 状态变化: \(previousState.description) -> \(state.description), 原因: \(reason)",
            category: "EditorState"
        )
        
        // 发布状态变化
        stateChangeSubject.send(state)
        
        // 发送通知
        NotificationCenter.default.post(
            name: .editorStateDidChange,
            object: self,
            userInfo: [
                "previousState": previousState,
                "newState": state,
                "reason": reason
            ]
        )
        
        // 如果状态不允许格式操作，处理错误
        if !state.allowsFormatting {
            handleNonEditableState(state)
        }
    }
    
    /// 验证格式操作是否允许
    /// 
    /// - Parameter format: 要应用的格式
    /// - Returns: 是否允许操作
    func validateFormatOperation(_ format: TextFormat) -> Bool {
        guard currentState.allowsFormatting else {
            // 记录错误
            let error: FormatError
            switch currentState {
            case .readOnly:
                error = .editorNotEditable
            case .unfocused:
                error = .editorNotFocused
            case .empty:
                error = .emptySelectionForInlineFormat(format: format.displayName)
            default:
                error = .formatApplicationFailed(format: format.displayName, reason: currentState.description)
            }
            
            let context = FormatErrorContext(
                operation: "validateFormatOperation",
                format: format.displayName,
                selectedRange: nil,
                textLength: nil,
                cursorPosition: nil,
                additionalInfo: ["editorState": currentState.description]
            )
            
            errorHandler.handleError(error, context: context)
            
            return false
        }
        
        return true
    }
    
    /// 检查状态一致性
    /// 
    /// - Parameters:
    ///   - textView: 文本视图
    ///   - context: 编辑器上下文
    /// - Returns: 是否一致
    func checkConsistency(textView: NSTextView?, context: NativeEditorContext?) -> Bool {
        let actualState = determineEditorState(textView: textView, context: context)
        let isConsistent = actualState == currentState
        
        if !isConsistent {
            inconsistencyCount += 1
            
            logger.logWarning(
                "[EditorStateConsistencyChecker] 状态不一致: 期望 \(currentState.description), 实际 \(actualState.description)",
                category: "EditorState"
            )
            
            // 如果连续不一致超过阈值，强制更新状态
            if inconsistencyCount >= inconsistencyThreshold {
                logger.logWarning(
                    "[EditorStateConsistencyChecker] 连续不一致 \(inconsistencyCount) 次，强制更新状态",
                    category: "EditorState"
                )
                updateState(actualState, reason: "强制同步（连续不一致）")
                inconsistencyCount = 0
            }
        } else {
            inconsistencyCount = 0
        }
        
        return isConsistent
    }
    
    /// 重置状态
    func reset() {
        currentState = .unfocused
        formatButtonsEnabled = false
        stateChangeReason = "重置"
        inconsistencyCount = 0
        
        logger.logInfo("[EditorStateConsistencyChecker] 状态已重置", category: "EditorState")
    }
    
    /// 获取状态统计信息
    func getStateStatistics() -> [String: Any] {
        return [
            "currentState": currentState.description,
            "formatButtonsEnabled": formatButtonsEnabled,
            "stateChangeReason": stateChangeReason,
            "inconsistencyCount": inconsistencyCount,
            "lastCheckTime": lastCheckTime
        ]
    }
    
    // MARK: - Private Methods
    
    /// 设置通知观察者
    private func setupNotificationObservers() {
        // 监听编辑器焦点变化
        NotificationCenter.default.publisher(for: NSTextView.didBecomeFirstResponderNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if notification.object is NSTextView {
                    self?.updateState(.editable, reason: "编辑器获得焦点")
                }
            }
            .store(in: &cancellables)
        
        // 监听编辑器失去焦点
        NotificationCenter.default.publisher(for: NSTextView.didResignFirstResponderNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if notification.object is NSTextView {
                    self?.updateState(.unfocused, reason: "编辑器失去焦点")
                }
            }
            .store(in: &cancellables)
        
        // 监听强制状态更新通知
        NotificationCenter.default.publisher(for: .formatStateNeedsForceUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logger.logInfo("[EditorStateConsistencyChecker] 收到强制状态更新通知", category: "EditorState")
            }
            .store(in: &cancellables)
    }
    
    /// 确定编辑器状态
    private func determineEditorState(textView: NSTextView?, context: NativeEditorContext?) -> EditorState {
        // 检查 textView 是否存在
        guard let textView = textView else {
            return .error("编辑器不可用")
        }
        
        // 检查是否可编辑
        guard textView.isEditable else {
            return .readOnly
        }
        
        // 检查是否获得焦点
        guard textView.window?.firstResponder === textView else {
            return .unfocused
        }
        
        // 检查是否有内容
        guard let textStorage = textView.textStorage, textStorage.length > 0 else {
            return .empty
        }
        
        // 检查上下文状态
        if let context = context {
            if !context.isEditorFocused {
                return .unfocused
            }
        }
        
        return .editable
    }
    
    /// 处理不可编辑状态
    private func handleNonEditableState(_ state: EditorState) {
        // 发送通知禁用格式按钮
        NotificationCenter.default.post(
            name: .formatButtonsShouldDisable,
            object: self,
            userInfo: ["state": state, "message": state.userMessage ?? ""]
        )
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    /// 编辑器状态变化
    static let editorStateDidChange = Notification.Name("editorStateDidChange")
    
    /// 格式按钮应该禁用
    static let formatButtonsShouldDisable = Notification.Name("formatButtonsShouldDisable")
    
    /// 格式按钮应该启用
    static let formatButtonsShouldEnable = Notification.Name("formatButtonsShouldEnable")
}

// MARK: - NSTextView 通知扩展

extension NSTextView {
    /// 成为第一响应者通知
    static let didBecomeFirstResponderNotification = Notification.Name("NSTextViewDidBecomeFirstResponder")
    
    /// 失去第一响应者通知
    static let didResignFirstResponderNotification = Notification.Name("NSTextViewDidResignFirstResponder")
}
