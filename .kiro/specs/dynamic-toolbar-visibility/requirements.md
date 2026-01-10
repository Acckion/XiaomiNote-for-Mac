# Requirements Document

## Introduction

实现类似 Apple Notes 的工具栏动态显示功能。根据当前视图模式和应用状态，动态隐藏或显示特定的工具栏项。使用 macOS 15 新增的 `NSToolbarItem.hidden` 属性实现，隐藏的工具栏项在自定义工具栏界面中会显示为虚线框。

## Glossary

- **Toolbar_System**: 工具栏系统，负责管理和显示工具栏项
- **Toolbar_Item**: 工具栏项，工具栏中的单个按钮或控件
- **View_Mode**: 视图模式，包括列表视图（三栏布局）和画廊视图（两栏布局）
- **Editor_Items**: 编辑器相关工具栏项，包括格式、插入、撤销/重做等按钮
- **Context_Items**: 上下文相关工具栏项，如私密笔记的锁按钮
- **Hidden_State**: 隐藏状态，工具栏项的 `isHidden` 属性值

## Requirements

### Requirement 1: 画廊视图下隐藏编辑器工具栏项

**User Story:** As a user, I want editor toolbar items to be hidden in gallery view, so that the toolbar only shows relevant actions when no note is open.

#### Acceptance Criteria

1. WHEN the view mode is gallery, THE Toolbar_System SHALL set Editor_Items hidden state to true
2. WHEN the view mode changes from gallery to list, THE Toolbar_System SHALL set Editor_Items hidden state to false
3. THE Editor_Items SHALL include: formatMenu, undo, redo, checkbox, horizontalRule, attachment, increaseIndent, decreaseIndent
4. WHEN Editor_Items are hidden, THE Toolbar_System SHALL display them with dashed border in customize toolbar interface

### Requirement 2: 列表视图下显示编辑器工具栏项

**User Story:** As a user, I want editor toolbar items to be visible in list view, so that I can format and edit the selected note.

#### Acceptance Criteria

1. WHEN the view mode is list, THE Toolbar_System SHALL set Editor_Items hidden state to false
2. WHEN a note is selected in list view, THE Editor_Items SHALL be enabled for interaction
3. WHEN no note is selected in list view, THE Editor_Items SHALL be visible but disabled

### Requirement 3: 私密笔记锁按钮条件显示

**User Story:** As a user, I want the lock button to only appear when viewing unlocked private notes, so that I can quickly lock them when needed.

#### Acceptance Criteria

1. WHEN the selected folder is private notes folder AND private notes are unlocked, THE Toolbar_System SHALL set lockPrivateNotes item hidden state to false
2. WHEN the selected folder is not private notes folder, THE Toolbar_System SHALL set lockPrivateNotes item hidden state to true
3. WHEN private notes are locked, THE Toolbar_System SHALL set lockPrivateNotes item hidden state to true
4. WHEN folder selection changes, THE Toolbar_System SHALL update lockPrivateNotes visibility immediately

### Requirement 4: 笔记操作按钮条件显示

**User Story:** As a user, I want note operation buttons to be hidden when no note is available to operate on, so that the toolbar remains clean and relevant.

#### Acceptance Criteria

1. WHEN the view mode is gallery AND no note is selected, THE Toolbar_System SHALL set noteOperations and share items hidden state to true
2. WHEN a note is selected (in any view mode), THE Toolbar_System SHALL set noteOperations and share items hidden state to false
3. WHEN the selected note changes, THE Toolbar_System SHALL update visibility immediately

### Requirement 5: 工具栏状态响应式更新

**User Story:** As a user, I want toolbar visibility to update automatically when app state changes, so that I always see relevant actions.

#### Acceptance Criteria

1. WHEN view mode changes, THE Toolbar_System SHALL update all affected items visibility within 100ms
2. WHEN folder selection changes, THE Toolbar_System SHALL update context-dependent items visibility immediately
3. WHEN note selection changes, THE Toolbar_System SHALL update note-dependent items visibility immediately
4. THE Toolbar_System SHALL use Combine publishers to observe state changes

### Requirement 6: 自定义工具栏界面兼容性

**User Story:** As a user, I want to see hidden toolbar items in the customize toolbar interface, so that I can understand what items are available.

#### Acceptance Criteria

1. WHEN the customize toolbar interface is open, THE Toolbar_System SHALL display hidden items with dashed border (macOS 15 native behavior)
2. THE user SHALL be able to add hidden items to the toolbar through the customize interface
3. WHEN a hidden item is added to toolbar, THE Toolbar_System SHALL respect its hidden state based on current context
