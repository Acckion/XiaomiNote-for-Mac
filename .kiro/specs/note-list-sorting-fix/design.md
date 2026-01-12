# 设计文档

## 概述

本设计文档描述了修复笔记列表排序功能的两个问题的技术方案：
1. 按创建时间排序时显示创建时间而非修改时间
2. 修复笔记选择时的错误移动和高亮状态问题

## 架构

### 现有架构分析

当前笔记列表排序涉及以下组件：

```
┌─────────────────────────────────────────────────────────────┐
│                    ViewOptionsManager                        │
│  - sortOrder: NoteSortOrder (.editDate/.createDate/.title)  │
│  - sortDirection: SortDirection                              │
│  - isDateGroupingEnabled: Bool                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    NotesViewModel                            │
│  - filteredNotes: [Note] (根据 sortOrder 排序)              │
│  - selectedNote: Note?                                       │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│     NotesListView       │     │      GalleryView        │
│  - NoteRow (显示时间)   │     │  - NoteCardView         │
│  - groupNotesByDate()   │     │  - groupNotesByDate()   │
└─────────────────────────┘     └─────────────────────────┘
```

### 问题根因分析

#### 问题 1：时间显示不正确

**根因**：`NoteRow` 和 `NoteCardView` 中的 `formatDate` 函数始终使用 `note.updatedAt`，没有根据 `ViewOptionsManager.sortOrder` 切换到 `note.createdAt`。

**代码位置**：
- `Sources/View/SwiftUIViews/NotesListView.swift` 第 670 行
- `Sources/View/SwiftUIViews/NoteCardView.swift` 第 151 行

#### 问题 2：笔记选择时错误移动

**根因**：经过代码分析，发现问题可能与以下因素有关：
1. 笔记选择时触发了 `ensureNoteHasFullContent`，可能更新了笔记的 `updatedAt`
2. `NoteRow` 的 `id` 修饰符使用 `note.id`，但 SwiftUI 的 List 选择机制可能与动画冲突
3. 日期分组逻辑在排序方式为编辑时间时，可能因为时间戳微小差异导致分组变化

## 组件和接口

### 修改 1：NoteRow 时间显示

在 `NoteRow` 中添加对 `ViewOptionsManager.sortOrder` 的监听，根据排序方式选择显示的时间字段。

```swift
// NoteRow 中添加
@ObservedObject var optionsManager: ViewOptionsManager = .shared

/// 根据排序方式获取要显示的日期
private var displayDate: Date {
    switch optionsManager.sortOrder {
    case .createDate:
        return note.createdAt
    case .editDate, .title:
        return note.updatedAt
    }
}

// 修改时间显示
Text(formatDate(displayDate))
```

### 修改 2：NoteCardView 时间显示

类似地，在 `NoteCardView` 中添加对排序方式的支持。

```swift
// NoteCardView 中添加
@ObservedObject var optionsManager: ViewOptionsManager = .shared

/// 根据排序方式获取要显示的日期
private var displayDate: Date {
    switch optionsManager.sortOrder {
    case .createDate:
        return note.createdAt
    case .editDate, .title:
        return note.updatedAt
    }
}

// 修改日期区域
private var dateSection: some View {
    Text(formatDate(displayDate))
        .font(.caption)
        .foregroundColor(.secondary)
}
```

### 修改 3：日期分组逻辑

`groupNotesByDate` 函数已经正确使用 `optionsManager.sortOrder` 来决定使用哪个日期字段进行分组，无需修改。

### 修改 4：修复笔记选择时的移动问题

经过分析，笔记选择时的移动问题可能与以下因素有关：

1. **List 动画与选择状态冲突**：当 `filteredNotes` 数组变化时，SwiftUI 的 List 会触发动画，可能导致选择状态异常

2. **解决方案**：确保笔记选择操作不会触发不必要的数组更新

```swift
// 在 NotesListView 中，确保选择操作不触发排序变化
.onTapGesture {
    // 只更新选择状态，不触发其他操作
    viewModel.selectedNote = note
}
```

## 数据模型

无需修改数据模型。现有的 `Note` 模型已包含 `createdAt` 和 `updatedAt` 字段。

## 正确性属性

*正确性属性是系统在所有有效执行中应保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1：时间显示与排序方式一致性

*对于任意*笔记和任意排序方式，NoteRow 和 NoteCardView 显示的时间应与排序方式对应的时间字段一致：
- 当排序方式为 `createDate` 时，显示 `note.createdAt`
- 当排序方式为 `editDate` 或 `title` 时，显示 `note.updatedAt`

**验证: 需求 1.1, 1.2, 1.3, 1.5**

### Property 2：笔记选择不改变列表顺序

*对于任意*笔记列表和任意选择操作，如果笔记的时间戳未变化，则选择操作后笔记在列表中的相对顺序应保持不变。

**验证: 需求 2.1, 2.5**

### Property 3：日期分组与排序方式一致性

*对于任意*笔记列表和任意排序方式，日期分组应基于与排序方式对应的时间字段：
- 当排序方式为 `createDate` 时，分组基于 `note.createdAt`
- 当排序方式为 `editDate` 或 `title` 时，分组基于 `note.updatedAt`

**验证: 需求 3.1, 3.2**

## 错误处理

本次修改主要涉及 UI 显示逻辑，不涉及复杂的错误处理。主要考虑：

1. **空值处理**：确保 `note.createdAt` 和 `note.updatedAt` 不为空
2. **排序方式变化**：确保排序方式变化时 UI 能正确响应

## 测试策略

### 单元测试

1. 测试 `displayDate` 计算属性在不同排序方式下返回正确的日期
2. 测试 `groupNotesByDate` 函数在不同排序方式下使用正确的日期字段

### 属性测试

使用 Swift 的 XCTest 框架进行属性测试：

1. **Property 1 测试**：生成随机笔记，验证显示的时间与排序方式一致
2. **Property 2 测试**：生成随机笔记列表，模拟选择操作，验证顺序不变
3. **Property 3 测试**：生成随机笔记列表，验证分组基于正确的时间字段

### 手动测试

1. 切换排序方式，验证时间显示正确更新
2. 在不同排序方式下点击笔记，验证不会错误移动
3. 启用日期分组，验证分组与排序方式一致
