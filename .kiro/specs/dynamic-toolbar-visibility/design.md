# Design Document: Dynamic Toolbar Visibility

## Overview

本设计实现类似 Apple Notes 的工具栏动态显示功能，使用 macOS 15 新增的 `NSToolbarItem.hidden` 属性。根据当前视图模式（画廊/列表）、文件夹选择（私密笔记）和笔记选择状态，动态控制工具栏项的可见性。

## Architecture

### 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                    MainWindowController                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              ToolbarVisibilityManager               │    │
│  │  - 监听状态变化                                      │    │
│  │  - 计算工具栏项可见性                                │    │
│  │  - 更新 NSToolbarItem.isHidden                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                            │                                 │
│                            ▼                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              State Publishers (Combine)              │    │
│  │  - ViewOptionsManager.$state.viewMode               │    │
│  │  - NotesViewModel.$selectedFolder                   │    │
│  │  - NotesViewModel.$selectedNote                     │    │
│  │  - NotesViewModel.$isPrivateNotesUnlocked           │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 工具栏项分类

```swift
enum ToolbarItemCategory {
    case editor      // 编辑器相关：formatMenu, undo, redo, checkbox, horizontalRule, attachment, increaseIndent, decreaseIndent
    case noteAction  // 笔记操作：share, noteOperations
    case context     // 上下文相关：lockPrivateNotes
    case global      // 全局可用：newNote, newFolder, search, viewOptions, onlineStatus, toggleSidebar
}
```

## Components and Interfaces

### ToolbarVisibilityManager

负责管理工具栏项可见性的核心组件。

```swift
/// 工具栏可见性管理器
/// 负责根据应用状态动态更新工具栏项的可见性
@MainActor
public class ToolbarVisibilityManager {
    
    // MARK: - 依赖
    
    private weak var toolbar: NSToolbar?
    private weak var viewModel: NotesViewModel?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 工具栏项引用
    
    /// 编辑器相关工具栏项标识符
    private let editorItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .formatMenu, .undo, .redo, .checkbox, 
        .horizontalRule, .attachment, .increaseIndent, .decreaseIndent
    ]
    
    /// 笔记操作相关工具栏项标识符
    private let noteActionItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .share, .noteOperations
    ]
    
    /// 上下文相关工具栏项标识符
    private let contextItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .lockPrivateNotes
    ]
    
    // MARK: - 初始化
    
    public init(toolbar: NSToolbar, viewModel: NotesViewModel) {
        self.toolbar = toolbar
        self.viewModel = viewModel
        setupStateObservers()
    }
    
    // MARK: - 状态监听
    
    private func setupStateObservers() {
        // 监听视图模式变化
        ViewOptionsManager.shared.$state
            .map(\.viewMode)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听文件夹选择变化
        viewModel?.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听笔记选择变化
        viewModel?.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
        
        // 监听私密笔记解锁状态变化
        viewModel?.$isPrivateNotesUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 可见性更新
    
    /// 更新所有工具栏项的可见性
    public func updateToolbarVisibility() {
        guard let toolbar = toolbar else { return }
        
        let viewMode = ViewOptionsManager.shared.viewMode
        let hasSelectedNote = viewModel?.selectedNote != nil
        let isPrivateFolder = viewModel?.selectedFolder?.id == "2"
        let isUnlocked = viewModel?.isPrivateNotesUnlocked ?? false
        
        // 遍历工具栏项并更新可见性
        for item in toolbar.items {
            updateItemVisibility(
                item,
                viewMode: viewMode,
                hasSelectedNote: hasSelectedNote,
                isPrivateFolder: isPrivateFolder,
                isUnlocked: isUnlocked
            )
        }
    }
    
    /// 更新单个工具栏项的可见性
    private func updateItemVisibility(
        _ item: NSToolbarItem,
        viewMode: ViewMode,
        hasSelectedNote: Bool,
        isPrivateFolder: Bool,
        isUnlocked: Bool
    ) {
        let identifier = item.itemIdentifier
        
        if editorItemIdentifiers.contains(identifier) {
            // 编辑器项：仅在列表视图中显示
            item.isHidden = (viewMode == .gallery)
        } else if noteActionItemIdentifiers.contains(identifier) {
            // 笔记操作项：仅在有选中笔记时显示
            item.isHidden = !hasSelectedNote
        } else if identifier == .lockPrivateNotes {
            // 锁按钮：仅在私密笔记文件夹且已解锁时显示
            item.isHidden = !(isPrivateFolder && isUnlocked)
        }
        // 其他项保持默认可见
    }
}
```

### MainWindowToolbarDelegate 修改

在工具栏代理中集成可见性管理器。

```swift
extension MainWindowToolbarDelegate {
    
    /// 工具栏项添加后设置初始可见性
    public func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
            return
        }
        
        // 设置初始可见性
        visibilityManager?.updateItemVisibility(item)
        
        // ... 其他现有逻辑
    }
}
```

## Data Models

### ToolbarVisibilityState

表示工具栏可见性状态的数据结构。

```swift
/// 工具栏可见性状态
struct ToolbarVisibilityState {
    /// 视图模式
    let viewMode: ViewMode
    
    /// 是否有选中的笔记
    let hasSelectedNote: Bool
    
    /// 是否在私密笔记文件夹
    let isPrivateFolder: Bool
    
    /// 私密笔记是否已解锁
    let isUnlocked: Bool
    
    /// 计算编辑器项是否应该隐藏
    var shouldHideEditorItems: Bool {
        viewMode == .gallery
    }
    
    /// 计算笔记操作项是否应该隐藏
    var shouldHideNoteActionItems: Bool {
        !hasSelectedNote
    }
    
    /// 计算锁按钮是否应该隐藏
    var shouldHideLockButton: Bool {
        !(isPrivateFolder && isUnlocked)
    }
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Editor Items Visibility Consistency

*For any* view mode state, the editor toolbar items (formatMenu, undo, redo, checkbox, horizontalRule, attachment, increaseIndent, decreaseIndent) should have their `isHidden` property equal to `(viewMode == .gallery)`.

**Validates: Requirements 1.1, 1.2, 2.1**

### Property 2: Lock Button Visibility Consistency

*For any* combination of folder selection and unlock state, the lockPrivateNotes toolbar item should have its `isHidden` property equal to `!(isPrivateFolder && isUnlocked)`.

**Validates: Requirements 3.1, 3.2, 3.3**

### Property 3: Note Action Items Visibility Consistency

*For any* note selection state, the note action toolbar items (share, noteOperations) should have their `isHidden` property equal to `!hasSelectedNote`.

**Validates: Requirements 4.1, 4.2**

### Property 4: State Change Responsiveness

*For any* state change (view mode, folder selection, note selection, unlock state), the toolbar visibility should be updated synchronously on the main thread.

**Validates: Requirements 3.4, 4.3, 5.1, 5.2, 5.3**

## Error Handling

### 错误场景

1. **工具栏引用丢失**
   - 场景：toolbar 弱引用变为 nil
   - 处理：在 updateToolbarVisibility 中检查 toolbar 是否存在，不存在则直接返回

2. **视图模型引用丢失**
   - 场景：viewModel 弱引用变为 nil
   - 处理：使用默认值（hasSelectedNote = false, isPrivateFolder = false, isUnlocked = false）

3. **工具栏项不存在**
   - 场景：尝试更新不在工具栏中的项
   - 处理：只遍历 toolbar.items 中实际存在的项

## Testing Strategy

### 单元测试

1. **ToolbarVisibilityState 计算测试**
   - 测试各种状态组合下的可见性计算结果
   - 验证边界条件

2. **状态变化响应测试**
   - 模拟状态变化，验证可见性更新被触发

### 属性测试

使用 Swift 的属性测试框架验证正确性属性：

1. **Property 1 测试**：生成随机视图模式，验证编辑器项可见性
2. **Property 2 测试**：生成随机文件夹和解锁状态组合，验证锁按钮可见性
3. **Property 3 测试**：生成随机笔记选择状态，验证笔记操作项可见性

### 集成测试

1. **视图模式切换测试**
   - 从列表切换到画廊，验证编辑器项隐藏
   - 从画廊切换到列表，验证编辑器项显示

2. **私密笔记场景测试**
   - 选择私密笔记文件夹并解锁，验证锁按钮显示
   - 切换到其他文件夹，验证锁按钮隐藏

### 测试配置

- 属性测试最少运行 100 次迭代
- 每个属性测试需要标注对应的设计文档属性
- 标注格式：**Feature: dynamic-toolbar-visibility, Property {number}: {property_text}**
