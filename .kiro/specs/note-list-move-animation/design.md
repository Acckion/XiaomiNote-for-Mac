# Design Document: Note List Move Animation

## Overview

为 NotesListView 添加笔记位置变化的移动动画。当用户编辑笔记导致编辑时间更新时，笔记会在列表中重新排序（通常移动到顶部）。此设计通过 SwiftUI 的 animation 修饰符实现平滑的位置过渡动画。

## Architecture

### 动画实现方案

使用 SwiftUI 的声明式动画机制：
1. 在 List 上添加 `animation(_:value:)` 修饰符
2. 监听 `filteredNotes` 的变化触发动画
3. 使用 `.easeInOut(duration: 0.3)` 动画曲线

### 关键设计决策

**为什么使用 `animation(_:value:)` 而非 `withAnimation`**：
- `animation(_:value:)` 是声明式的，只在指定值变化时触发
- 避免影响其他不需要动画的 UI 更新
- 更符合 SwiftUI 的设计理念

**为什么监听 `filteredNotes`**：
- `filteredNotes` 是列表数据源，其变化直接反映列表内容变化
- 当笔记编辑时间更新时，排序会改变，`filteredNotes` 数组顺序变化
- SwiftUI 会自动计算列表项的位置变化并应用动画

## Components and Interfaces

### ListAnimationConfig

```swift
/// 列表动画配置
enum ListAnimationConfig {
    /// 列表项移动动画
    static let moveAnimation: Animation = .easeInOut(duration: 0.3)
}
```

### NotesListView 修改

在 `notesListContent` 的 Group 上添加动画修饰符：

```swift
private var notesListContent: some View {
    Group {
        // ... 现有的分组逻辑
    }
    .animation(ListAnimationConfig.moveAnimation, value: viewModel.filteredNotes.map(\.id))
}
```

**注意**：使用 `filteredNotes.map(\.id)` 而非整个 `filteredNotes` 数组，因为：
- 只关心笔记的顺序变化，不关心内容变化
- 避免内容编辑时触发不必要的动画
- `[String]` 类型自动符合 `Equatable`

## Data Models

无需新增数据模型。

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Selection State Preservation

*For any* note list and any selected note, when the note's position changes due to edit time update, the selection state SHALL remain unchanged after the position change completes.

**Validates: Requirements 1.4**

## Error Handling

### 潜在问题与处理

1. **大量笔记同时更新**：动画可能卡顿
   - 处理：300ms 的短动画时长可以减少视觉干扰

2. **快速连续编辑**：多次动画叠加
   - 处理：SwiftUI 会自动合并连续的动画

3. **选中状态丢失**：动画期间选中状态被重置
   - 处理：现有的 `ViewStateCoordinator` 已经处理了选中状态保持

## Testing Strategy

### 单元测试

由于动画是 UI 层面的效果，主要通过代码审查和手动测试验证：

1. **代码审查**：确认动画修饰符正确应用
2. **手动测试**：
   - 编辑笔记内容，观察笔记是否平滑移动到顶部
   - 确认动画时长约为 300ms
   - 确认选中状态在动画期间保持不变

### 属性测试

**Property 1: Selection State Preservation**
- 测试框架：XCTest
- 测试方法：模拟笔记编辑导致的 filteredNotes 顺序变化，验证 selectedNote 保持不变
- 注意：此属性已由现有的 ViewStateCoordinator 测试覆盖（view-state-sync spec）
