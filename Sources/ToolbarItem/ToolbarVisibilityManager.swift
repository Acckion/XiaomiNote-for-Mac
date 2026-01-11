//
//  ToolbarVisibilityManager.swift
//  MiNoteMac
//
//  工具栏可见性管理器
//  负责根据应用状态动态更新工具栏项的可见性
//
//  Created by Kiro on 2026/1/10.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit
import Combine

/// 工具栏可见性管理器
///
/// 负责根据应用状态动态更新工具栏项的可见性
/// 使用 macOS 15 的 `NSToolbarItem.isHidden` 属性实现
///
/// **Requirements: 1.3, 5.4**
/// - 1.3: 定义编辑器相关工具栏项
/// - 5.4: 使用 Combine publishers 观察状态变化
@MainActor
public class ToolbarVisibilityManager {
    
    // MARK: - 依赖
    
    /// 工具栏引用（弱引用避免循环引用）
    private weak var toolbar: NSToolbar?
    
    /// 视图模型引用（弱引用避免循环引用）
    private weak var viewModel: NotesViewModel?
    
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 工具栏项分类常量
    
    /// 编辑器相关工具栏项标识符
    /// 这些项在画廊视图中应该隐藏
    /// **Requirements: 1.3**
    private let editorItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .formatMenu,
        .undo,
        .redo,
        .checkbox,
        .horizontalRule,
        .attachment,
        .audioRecording,
        .increaseIndent,
        .decreaseIndent
    ]
    
    /// 画廊视图下应该隐藏的分隔符标识符
    /// 在两栏布局（画廊视图）下，时间线跟踪分隔符不需要显示
    private let galleryHiddenSeparatorIdentifiers: Set<NSToolbarItem.Identifier> = [
        .timelineTrackingSeparator
    ]
    
    /// 笔记操作相关工具栏项标识符
    /// 这些项在没有选中笔记时应该隐藏
    /// **Requirements: 4.1, 4.2**
    private let noteActionItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .share,
        .noteOperations
    ]
    
    /// 上下文相关工具栏项标识符
    /// 这些项根据特定上下文条件显示/隐藏
    /// **Requirements: 3.1, 3.2, 3.3**
    private let contextItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .lockPrivateNotes
    ]
    
    /// 画廊展开编辑时需要隐藏的工具栏项标识符
    /// 这些项在画廊视图展开编辑笔记时应该隐藏，因为它们与笔记编辑无关
    private let galleryExpandedHiddenItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .onlineStatus,
        .viewOptions
    ]
    
    // MARK: - 初始化
    
    /// 初始化工具栏可见性管理器
    /// - Parameters:
    ///   - toolbar: 要管理的工具栏
    ///   - viewModel: 笔记视图模型
    public init(toolbar: NSToolbar, viewModel: NotesViewModel?) {
        self.toolbar = toolbar
        self.viewModel = viewModel
        
        // 设置状态监听
        setupStateObservers()
        
        // 初始更新可见性
        updateToolbarVisibility()
    }
    
    // MARK: - 状态监听
    
    /// 设置状态监听
    /// **Requirements: 5.1, 5.2, 5.3, 5.4**
    private func setupStateObservers() {
        // 监听视图模式变化
        // **Requirements: 5.1**
        ViewOptionsManager.shared.$state
            .map(\.viewMode)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听文件夹选择变化
        // **Requirements: 5.2**
        viewModel?.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听笔记选择变化
        // **Requirements: 5.3**
        viewModel?.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听私密笔记解锁状态变化
        // **Requirements: 3.4**
        viewModel?.$isPrivateNotesUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听画廊展开状态变化
        // 用于控制返回按钮和编辑器工具栏项的可见性
        viewModel?.$isGalleryExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 可见性更新
    
    /// 更新所有工具栏项的可见性
    /// **Requirements: 1.1, 1.2, 2.1, 3.1, 3.2, 3.3, 4.1, 4.2**
    public func updateToolbarVisibility() {
        guard let toolbar = toolbar else { return }
        
        // 获取当前状态
        let viewMode = ViewOptionsManager.shared.viewMode
        let hasSelectedNote = viewModel?.selectedNote != nil
        let isPrivateFolder = viewModel?.selectedFolder?.id == "2"
        let isUnlocked = viewModel?.isPrivateNotesUnlocked ?? false
        let isGalleryExpanded = viewModel?.isGalleryExpanded ?? false
        
        // 遍历工具栏项并更新可见性
        for item in toolbar.items {
            updateItemVisibility(
                item,
                viewMode: viewMode,
                hasSelectedNote: hasSelectedNote,
                isPrivateFolder: isPrivateFolder,
                isUnlocked: isUnlocked,
                isGalleryExpanded: isGalleryExpanded
            )
        }
    }
    
    /// 更新单个工具栏项的可见性
    /// - Parameters:
    ///   - item: 要更新的工具栏项
    ///   - viewMode: 当前视图模式
    ///   - hasSelectedNote: 是否有选中的笔记
    ///   - isPrivateFolder: 是否在私密笔记文件夹
    ///   - isUnlocked: 私密笔记是否已解锁
    ///   - isGalleryExpanded: 画廊视图是否展开（正在编辑笔记）
    ///
    /// **Requirements: 1.1, 1.2, 2.1, 3.1, 3.2, 3.3, 4.1, 4.2**
    public func updateItemVisibility(
        _ item: NSToolbarItem,
        viewMode: ViewMode? = nil,
        hasSelectedNote: Bool? = nil,
        isPrivateFolder: Bool? = nil,
        isUnlocked: Bool? = nil,
        isGalleryExpanded: Bool? = nil
    ) {
        // 使用传入的值或获取当前状态
        let currentViewMode = viewMode ?? ViewOptionsManager.shared.viewMode
        let currentHasSelectedNote = hasSelectedNote ?? (viewModel?.selectedNote != nil)
        let currentIsPrivateFolder = isPrivateFolder ?? (viewModel?.selectedFolder?.id == "2")
        let currentIsUnlocked = isUnlocked ?? (viewModel?.isPrivateNotesUnlocked ?? false)
        let currentIsGalleryExpanded = isGalleryExpanded ?? (viewModel?.isGalleryExpanded ?? false)
        
        let identifier = item.itemIdentifier
        
        // 画廊视图是否处于展开编辑状态
        let isInGalleryEditMode = (currentViewMode == .gallery && currentIsGalleryExpanded)
        
        if editorItemIdentifiers.contains(identifier) {
            // 编辑器项：在列表视图中显示，或在画廊视图展开编辑时显示
            // **Requirements: 1.1, 1.2, 2.1**
            item.isHidden = (currentViewMode == .gallery && !currentIsGalleryExpanded)
        } else if galleryHiddenSeparatorIdentifiers.contains(identifier) {
            // 时间线跟踪分隔符：仅在列表视图（三栏布局）中显示
            // 在画廊视图（两栏布局）下始终隐藏，无论是否展开
            item.isHidden = (currentViewMode == .gallery)
        } else if noteActionItemIdentifiers.contains(identifier) {
            // 笔记操作项：
            // - 列表视图：有选中笔记时显示
            // - 画廊视图：仅在展开编辑时显示
            // **Requirements: 4.1, 4.2**
            if currentViewMode == .gallery {
                item.isHidden = !isInGalleryEditMode
            } else {
                item.isHidden = !currentHasSelectedNote
            }
        } else if identifier == .lockPrivateNotes {
            // 锁按钮：仅在私密笔记文件夹且已解锁时显示
            // **Requirements: 3.1, 3.2, 3.3**
            item.isHidden = !(currentIsPrivateFolder && currentIsUnlocked)
        } else if identifier == .backToGallery {
            // 返回画廊按钮：仅在画廊视图展开编辑时显示
            item.isHidden = !isInGalleryEditMode
        } else if galleryExpandedHiddenItemIdentifiers.contains(identifier) {
            // 网络状态和视图选项：在画廊视图展开编辑时隐藏
            // 这些项与笔记编辑无关，展开编辑时隐藏以简化工具栏
            item.isHidden = isInGalleryEditMode
        }
        // 其他项保持默认可见（不修改 isHidden）
    }
    
    // MARK: - 辅助方法
    
    /// 检查工具栏项是否属于编辑器类别
    /// - Parameter identifier: 工具栏项标识符
    /// - Returns: 如果是编辑器项返回 true
    public func isEditorItem(_ identifier: NSToolbarItem.Identifier) -> Bool {
        return editorItemIdentifiers.contains(identifier)
    }
    
    /// 检查工具栏项是否属于笔记操作类别
    /// - Parameter identifier: 工具栏项标识符
    /// - Returns: 如果是笔记操作项返回 true
    public func isNoteActionItem(_ identifier: NSToolbarItem.Identifier) -> Bool {
        return noteActionItemIdentifiers.contains(identifier)
    }
    
    /// 检查工具栏项是否属于上下文类别
    /// - Parameter identifier: 工具栏项标识符
    /// - Returns: 如果是上下文项返回 true
    public func isContextItem(_ identifier: NSToolbarItem.Identifier) -> Bool {
        return contextItemIdentifiers.contains(identifier)
    }
}

#endif
