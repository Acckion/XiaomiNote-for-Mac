# 工具栏三分栏分割线修复方案

## 问题描述

用户希望实现类似 Apple Notes 的三列分割式工具栏布局，但当前的自定义工具栏只有两列效果。用户指出当前代码尝试使用 Spacer 来分割中、右侧区域，但这种方法行不通。

## 问题分析

通过分析 `ContentView.swift` 文件，发现当前的工具栏实现存在以下问题：

1. **工具栏项 placement 配置不正确**：
   - `new-note` 按钮使用 `.automatic` placement，这可能导致系统无法正确识别它属于哪个区域
   - 系统可能不会为 `Spacer()` 绘制分割线

2. **缺少明确的分区标识**：
   - 当前只有 `right-spacer` 使用 `.primaryAction` placement 来分隔中间和右侧区域
   - 缺少分隔左侧和中间区域的 spacer

## 解决方案

基于 SwiftUI 官方文档和 `NavigationSplitView` 的工具栏机制，实施了以下修改：

### 1. 调整工具栏项 placement

**关键修改**：将 `new-note` 按钮的 placement 从 `.automatic` 改为 `.navigation`

```swift
// 修改前：
ToolbarItem(id: "new-note", placement: .automatic) { ... }

// 修改后：
ToolbarItem(id: "new-note", placement: .navigation) { ... }
```

### 2. 移除无效的 Spacer

**关键发现**：用户确认 `Spacer()` 和 `Divider()` 作为工具栏项内容都不会自动创建系统分割线。因此移除了尝试使用 Spacer 分隔区域的代码。

### 3. 依赖系统自动分割机制

根据 SwiftUI 文档，`NavigationSplitView` 会自动根据工具栏项的 `placement` 属性将工具栏分割到不同的区域：

- `.navigation`：对应侧边栏（sidebar）区域
- `.secondaryAction`：对应内容（content）区域（笔记列表）
- `.primaryAction`：对应详情（detail）区域（笔记内容）

## 修改后的工具栏结构

```swift
.toolbar(id: "main-toolbar") {
    // 左侧工具栏项 - 对应侧边栏区域
    ToolbarItem(id: "new-note", placement: .navigation) {
        Button { viewModel.createNewNote() } label: { 
            Label("新建笔记", systemImage: "square.and.pencil") 
        }
    }
    .defaultCustomization(.visible)
    
    // 中间工具栏项 - 对应笔记列表区域
    ToolbarItem(id: "undo", placement: .secondaryAction) { ... }
    .defaultCustomization(.visible)
    
    ToolbarItem(id: "redo", placement: .secondaryAction) { ... }
    .defaultCustomization(.visible)
    
    ToolbarItem(id: "format", placement: .secondaryAction) { ... }
    .defaultCustomization(.visible)
    
    // 右侧工具栏项 - 对应编辑区域
    ToolbarItem(id: "online-status", placement: .primaryAction) { ... }
    .defaultCustomization(.visible)
}
```

## 预期效果

1. **系统自动绘制分割线**：SwiftUI 会根据工具栏项的 `placement` 属性自动在 `.navigation`、`.secondaryAction` 和 `.primaryAction` 之间绘制分割线
2. **保留用户自定义功能**：所有工具栏项仍然在同一个 `.toolbar(id: "main-toolbar")` 块中，支持用户自定义工具栏
3. **正确的区域分配**：
   - `new-note` 按钮明确属于侧边栏区域
   - `undo`、`redo`、`format` 按钮属于中间区域
   - `online-status` 菜单属于右侧区域

## 验证要点

1. **工具栏分割线**：检查应用程序工具栏是否显示两条明显的分割线，将工具栏分为三个区域
2. **用户自定义功能**：验证用户仍然可以自定义工具栏（添加、移除、重新排列工具栏项）
3. **功能完整性**：确保所有工具栏按钮功能正常

## 技术原理

在 SwiftUI 中，`NavigationSplitView` 的三列布局会自动将工具栏项分配到对应的区域：
- 系统根据 `placement` 属性识别工具栏项属于哪一列
- 当工具栏项使用不同的 `placement` 属性时，系统会自动绘制分割线
- 使用 `.automatic` placement 可能导致系统无法正确识别区域归属

## 备份文件

原始文件已备份为：
- `Sources/MiNoteLibrary/View/ContentView.swift.backup`（原始备份）
- `Sources/MiNoteLibrary/View/ContentView.swift.before-toolbar-fix`（本次修复前的备份）

## 注意事项

1. 此解决方案依赖于 SwiftUI 的系统行为，不同 macOS 版本可能有细微差异
2. 如果系统不自动绘制分割线，可能需要检查 `NavigationSplitView` 的样式配置
3. 确保应用程序目标为 macOS 14.0+，以支持最新的工具栏功能
