//
//  NoteEditorCoordinator.swift
//  MiNoteMac
//
//  笔记编辑器协调器 - 管理不同类型编辑器的创建和切换
//

import SwiftUI
import Combine

/// 笔记编辑器协调器
@MainActor
class NoteEditorCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前编辑器
    @Published var currentEditor: EditorProtocol
    
    /// 当前编辑器类型
    @Published var currentEditorType: EditorType
    
    /// 编辑器是否正在切换
    @Published var isSwitching: Bool = false
    
    /// 编辑器是否可用
    @Published var isEditorAvailable: Bool = true
    
    // MARK: - Private Properties
    
    private let preferencesService: EditorPreferencesService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// 初始化编辑器协调器
    /// - Parameter preferencesService: 编辑器偏好设置服务
    init(preferencesService: EditorPreferencesService = .shared) {
        self.preferencesService = preferencesService
        
        // 获取当前编辑器类型
        let editorType = preferencesService.getCurrentEditorType()
        self.currentEditorType = editorType
        
        // 创建初始编辑器
        self.currentEditor = EditorFactory.createEditorSafely(type: editorType)
        
        // 监听编辑器偏好变化
        setupPreferencesObserver()
    }
    
    // MARK: - Public Methods
    
    /// 切换到指定编辑器类型
    /// - Parameter type: 目标编辑器类型
    /// - Returns: 是否切换成功
    @discardableResult
    func switchToEditor(_ type: EditorType) async -> Bool {
        // 检查编辑器是否可用
        guard EditorFactory.isEditorAvailable(type) else {
            isEditorAvailable = false
            return false
        }
        
        // 如果已经是当前编辑器类型，直接返回
        guard type != currentEditorType else {
            return true
        }
        
        isSwitching = true
        isEditorAvailable = true
        
        // 保存当前内容
        let currentContent = currentEditor.getContent()
        
        // 创建新编辑器
        let newEditor = EditorFactory.createEditorSafely(type: type)
        
        // 加载内容到新编辑器
        newEditor.loadContent(currentContent)
        
        // 更新当前编辑器
        currentEditor = newEditor
        currentEditorType = type
        
        // 更新偏好设置
        preferencesService.setEditorType(type)
        
        isSwitching = false
        
        return true
    }
    
    /// 重新加载当前编辑器
    func reloadCurrentEditor() {
        let content = currentEditor.getContent()
        currentEditor = EditorFactory.createEditorSafely(type: currentEditorType)
        currentEditor.loadContent(content)
    }
    
    /// 检查编辑器兼容性
    func checkEditorCompatibility() {
        let isNativeAvailable = EditorFactory.isEditorAvailable(.native)
        
        // 如果当前使用原生编辑器但不可用，切换到 Web 编辑器
        if currentEditorType == .native && !isNativeAvailable {
            Task {
                await switchToEditor(.web)
            }
        }
        
        isEditorAvailable = EditorFactory.isEditorAvailable(currentEditorType)
    }
    
    /// 获取当前编辑器的内容
    /// - Returns: 编辑器内容
    func getCurrentContent() -> String {
        return currentEditor.getContent()
    }
    
    /// 加载内容到当前编辑器
    /// - Parameter content: 要加载的内容
    func loadContent(_ content: String) {
        currentEditor.loadContent(content)
    }
    
    /// 清空当前编辑器内容
    func clearContent() {
        currentEditor.clearContent()
    }
    
    /// 应用格式到当前编辑器
    /// - Parameter format: 要应用的格式
    func applyFormat(_ format: TextFormat) {
        currentEditor.applyFormat(format)
    }
    
    /// 插入特殊元素到当前编辑器
    /// - Parameter element: 要插入的特殊元素
    func insertSpecialElement(_ element: SpecialElement) {
        currentEditor.insertSpecialElement(element)
    }
    
    /// 获取当前编辑器的格式状态
    /// - Returns: 当前格式集合
    func getCurrentFormats() -> Set<TextFormat> {
        return currentEditor.getCurrentFormats()
    }
    
    /// 设置编辑器焦点
    /// - Parameter focused: 是否获得焦点
    func setEditorFocus(_ focused: Bool) {
        currentEditor.setFocus(focused)
    }
    
    /// 检查编辑器是否有焦点
    /// - Returns: 是否有焦点
    func hasEditorFocus() -> Bool {
        return currentEditor.hasFocus()
    }
    
    // MARK: - Publishers
    
    /// 内容变化发布者
    var contentChangePublisher: AnyPublisher<String, Never> {
        currentEditor.contentChangePublisher
    }
    
    /// 选择变化发布者
    var selectionChangePublisher: AnyPublisher<NSRange, Never> {
        currentEditor.selectionChangePublisher
    }
    
    /// 格式变化发布者
    var formatChangePublisher: AnyPublisher<Set<TextFormat>, Never> {
        currentEditor.formatChangePublisher
    }
    
    // MARK: - Private Methods
    
    /// 设置偏好设置观察者
    private func setupPreferencesObserver() {
        preferencesService.$selectedEditorType
            .removeDuplicates()
            .sink { [weak self] newType in
                guard let self = self else { return }
                
                // 如果编辑器类型发生变化，自动切换
                if newType != self.currentEditorType {
                    Task { @MainActor in
                        await self.switchToEditor(newType)
                    }
                }
            }
            .store(in: &cancellables)
        
        preferencesService.$isNativeEditorAvailable
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.checkEditorCompatibility()
            }
            .store(in: &cancellables)
    }
}

// 注意：由于 MainActor 隔离问题，暂时移除环境键支持
// 使用者需要手动创建和管理 NoteEditorCoordinator 实例

/// SwiftUI 视图扩展，用于注入编辑器协调器
extension View {
    func editorCoordinator(_ coordinator: NoteEditorCoordinator) -> some View {
        // 暂时返回原视图，等待后续实现
        self
    }
}