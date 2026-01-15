# Design Document: 列表行为优化

## Overview

本设计文档描述了原生编辑器列表行为优化的实现方案。核心目标是修复现有列表功能中不符合主流编辑器操作习惯的问题，使列表编辑体验与 Apple Notes、Google Docs、Notion 等主流编辑器保持一致。支持三种列表类型：无序列表（•）、有序列表（1. 2. 3.）和勾选框列表（☐/☑）。

### 设计原则

1. **光标限制**：光标不能移动到列表标记（序号、项目符号或勾选框）的左侧
2. **文本分割**：回车键在任意位置都能正确分割文本
3. **格式继承**：新列表项继承当前项的类型和缩进
4. **编号连续**：有序列表编号在增删时自动更新
5. **勾选框交互**：点击勾选框切换状态，新建勾选框默认未勾选

### 核心改动

1. 重写 `shouldChangeText` 方法限制光标位置
2. 优化 `handleReturnKeyForList` 方法支持文本分割
3. 新增 `handleBackspaceForList` 方法处理删除键
4. 新增编号更新机制

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        NativeTextView                            │
│                    (NSTextView 子类)                             │
├─────────────────────────────────────────────────────────────────┤
│  - shouldChangeText(in:replacementString:)  光标位置限制         │
│  - keyDown(with:)                           键盘事件处理         │
│  - moveLeft(_:)                             左移光标处理         │
│  - moveToBeginningOfLine(_:)                行首移动处理         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ListBehaviorHandler                          │
│                    (列表行为处理器 - 新增)                        │
├─────────────────────────────────────────────────────────────────┤
│  + getContentStartPosition(in:at:)    获取内容区域起始位置       │
│  + handleEnterKey(textView:)          处理回车键                 │
│  + handleBackspaceKey(textView:)      处理删除键                 │
│  + splitTextAtCursor(textView:)       在光标位置分割文本         │
│  + mergeWithPreviousLine(textView:)   与上一行合并               │
│  + updateOrderedListNumbers(in:from:) 更新有序列表编号           │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│     ListFormatHandler     │   │     NewLineHandler        │
│   (现有列表格式处理器)     │   │   (现有换行处理器)        │
└───────────────────────────┘   └───────────────────────────┘
```

## Components and Interfaces

### 1. ListBehaviorHandler（新增组件）

列表行为处理器，负责处理列表相关的光标限制、回车和删除键行为。

```swift
/// 列表行为处理器
/// 负责处理列表的光标限制、回车键和删除键行为
/// _Requirements: 1.1-1.4, 2.1-2.7, 3.1-3.4, 4.1-4.4_
@MainActor
public struct ListBehaviorHandler {
    
    // MARK: - 光标位置限制
    
    /// 获取列表项内容区域的起始位置
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 当前位置
    /// - Returns: 内容区域起始位置（列表标记之后的位置）
    /// _Requirements: 1.1, 1.3, 1.4_
    public static func getContentStartPosition(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int
    
    /// 检查位置是否在列表标记区域内
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 要检查的位置
    /// - Returns: 是否在列表标记区域内
    /// _Requirements: 1.1_
    public static func isInListMarkerArea(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool
    
    /// 调整光标位置，确保不在列表标记区域内
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 原始位置
    /// - Returns: 调整后的位置
    /// _Requirements: 1.1, 1.3_
    public static func adjustCursorPosition(
        in textStorage: NSTextStorage,
        from position: Int
    ) -> Int
    
    // MARK: - 回车键处理
    
    /// 处理列表项中的回车键
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 是否已处理
    /// _Requirements: 2.1-2.7, 3.1-3.4_
    public static func handleEnterKey(
        textView: NSTextView
    ) -> Bool
    
    /// 在光标位置分割文本并创建新列表项
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - textStorage: 文本存储
    ///   - cursorPosition: 光标位置
    /// - Returns: 是否成功分割
    /// _Requirements: 2.1, 2.2, 2.3_
    public static func splitTextAtCursor(
        textView: NSTextView,
        textStorage: NSTextStorage,
        cursorPosition: Int
    ) -> Bool
    
    // MARK: - 删除键处理
    
    /// 处理列表项中的删除键（Backspace）
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 是否已处理
    /// _Requirements: 4.1-4.4_
    public static func handleBackspaceKey(
        textView: NSTextView
    ) -> Bool
    
    /// 将当前列表项与上一行合并
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - textStorage: 文本存储
    /// - Returns: 是否成功合并
    /// _Requirements: 4.1, 4.2, 4.3, 4.4_
    public static func mergeWithPreviousLine(
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool
    
    // MARK: - 编号更新
    
    /// 更新有序列表编号
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - startPosition: 起始位置
    /// _Requirements: 6.1, 6.2, 6.3, 6.4_
    public static func updateOrderedListNumbers(
        in textStorage: NSTextStorage,
        from startPosition: Int
    )
    
    // MARK: - 勾选框状态切换
    
    /// 切换勾选框状态
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - position: 勾选框位置
    /// - Returns: 是否成功切换
    /// _Requirements: 7.1, 7.2, 7.3, 7.4_
    public static func toggleCheckboxState(
        textView: NSTextView,
        at position: Int
    ) -> Bool
    
    /// 检查位置是否在勾选框区域内
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 要检查的位置
    /// - Returns: 是否在勾选框区域内
    /// _Requirements: 1.5, 7.1, 7.2_
    public static func isInCheckboxArea(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool
}
```

### 2. NativeTextView 扩展

扩展现有的 NativeTextView 以支持光标位置限制和键盘事件处理。

```swift
extension NativeTextView {
    
    // MARK: - 光标位置限制
    
    /// 重写 shouldChangeText 方法，限制光标位置
    /// _Requirements: 1.1_
    override func shouldChangeText(
        in affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool
    
    /// 重写 moveLeft 方法，处理左移光标
    /// _Requirements: 1.2_
    override func moveLeft(_ sender: Any?)
    
    /// 重写 moveToBeginningOfLine 方法，处理行首移动
    /// _Requirements: 1.4_
    override func moveToBeginningOfLine(_ sender: Any?)
    
    /// 重写 moveWordLeft 方法，处理 Option+左方向键
    /// _Requirements: 1.4_
    override func moveWordLeft(_ sender: Any?)
    
    // MARK: - 选择行为限制
    
    /// 重写 moveLeftAndModifySelection 方法，处理 Shift+左方向键
    /// _Requirements: 5.1_
    override func moveLeftAndModifySelection(_ sender: Any?)
    
    /// 重写 moveToBeginningOfLineAndModifySelection 方法
    /// _Requirements: 5.2_
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?)
}
```

## Data Models

### 列表项信息结构

```swift
/// 列表项信息
struct ListItemInfo {
    /// 列表类型（无序、有序或勾选框）
    let listType: ListType
    
    /// 缩进级别
    let indent: Int
    
    /// 列表编号（仅有序列表）
    let number: Int?
    
    /// 勾选状态（仅勾选框列表）
    let isChecked: Bool?
    
    /// 行范围
    let lineRange: NSRange
    
    /// 列表标记范围（附件字符的范围）
    let markerRange: NSRange
    
    /// 内容区域起始位置
    let contentStartPosition: Int
    
    /// 内容文本
    let contentText: String
}
```

### 文本分割结果

```swift
/// 文本分割结果
struct TextSplitResult {
    /// 光标前的文本
    let textBefore: String
    
    /// 光标后的文本
    let textAfter: String
    
    /// 原始行范围
    let originalLineRange: NSRange
    
    /// 光标位置
    let cursorPosition: Int
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: 光标位置限制

*For any* 列表项，当尝试将光标移动到列表标记左侧时，光标应该被限制在内容区域起始位置。使用左方向键从内容起始位置继续向左移动时，光标应该移动到上一行末尾。

**Validates: Requirements 1.1, 1.2, 1.4**

### Property 2: 文本分割正确性

*For any* 有内容的列表项和任意光标位置，当按下回车键时，光标前的文本应该保留在当前行，光标后的文本应该移动到新创建的列表项中。原始文本 = 当前行文本 + 新行文本。

**Validates: Requirements 2.1, 2.2, 2.3**

### Property 3: 格式继承正确性

*For any* 列表项，当创建新列表项时，新项应该继承当前项的列表类型和缩进级别。对于有序列表，新项的编号应该等于当前项编号加 1。对于勾选框列表，新项应该是未勾选状态（☐）。

**Validates: Requirements 2.4, 2.5, 2.6**

### Property 4: 空列表回车取消格式

*For any* 空的列表项（只有列表标记没有内容），当按下回车键时，列表格式应该被取消，列表标记应该被移除，当前行应该恢复为普通正文格式。

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

### Property 5: 删除键合并行为

*For any* 列表项，当光标在内容区域起始位置按下删除键时，当前行的内容应该合并到上一行。如果上一行是列表项，内容追加到列表项末尾；如果上一行是普通文本，内容追加到行末尾并取消列表格式。

**Validates: Requirements 4.1, 4.2, 4.3, 4.4**

### Property 6: 选择行为限制

*For any* 列表项，当使用 Shift+左方向键从内容起始位置向左选择时，选择应该扩展到上一行而非选中列表标记。当使用 Cmd+Shift+左方向键选择到行首时，选择应该到内容区域起始位置。

**Validates: Requirements 5.1, 5.2**

### Property 7: 编号连续性

*For any* 连续的有序列表，在任何插入、删除或移动操作后，列表编号应该始终从 1 开始连续递增。不存在重复或跳跃的编号。

**Validates: Requirements 6.1, 6.2, 6.4**

### Property 8: 勾选框状态切换

*For any* 勾选框列表项，当点击勾选框时，勾选状态应该切换（☐ ↔ ☑），光标位置和列表项内容应该保持不变。

**Validates: Requirements 7.1, 7.2, 7.3, 7.4**

## Error Handling

### 边界条件处理

1. **空文档**：在空文档中不存在列表，所有列表相关操作不生效
2. **文档开头**：在文档第一行的列表项中，左移光标到内容起始位置后不再移动
3. **文档末尾**：在文档最后一行的列表项中，回车创建新列表项正常工作
4. **单字符内容**：列表项只有一个字符时，分割操作正常工作
5. **嵌套列表**：不同缩进级别的列表项，光标限制和分割操作独立处理

### 错误恢复

1. **附件丢失**：如果列表附件丢失，回退到使用 listType 属性检测列表
2. **编号不连续**：检测到编号不连续时，自动触发编号更新
3. **格式冲突**：列表格式与其他格式冲突时，优先保留列表格式

## Testing Strategy

### 单元测试

1. **ListBehaviorHandler 测试**
   - 测试 getContentStartPosition 正确返回内容起始位置
   - 测试 isInListMarkerArea 正确检测列表标记区域
   - 测试 adjustCursorPosition 正确调整光标位置
   - 测试 splitTextAtCursor 正确分割文本
   - 测试 mergeWithPreviousLine 正确合并行
   - 测试 updateOrderedListNumbers 正确更新编号
   - 测试 toggleCheckboxState 正确切换勾选状态
   - 测试 isInCheckboxArea 正确检测勾选框区域

2. **NativeTextView 扩展测试**
   - 测试 moveLeft 在列表项中的行为
   - 测试 moveToBeginningOfLine 在列表项中的行为
   - 测试选择操作在列表项中的行为
   - 测试点击勾选框切换状态

### 属性测试

使用 Swift 的属性测试框架验证正确性属性：

- 最小 100 次迭代
- 每个属性测试引用设计文档中的属性编号
- 标签格式：**Feature: list-behavior-optimization, Property {number}: {property_text}**

### 集成测试

1. **端到端列表编辑测试**
   - 创建列表 → 在中间位置回车 → 验证文本分割
   - 创建列表 → 在空项回车 → 验证格式取消
   - 创建列表 → 在内容起始位置删除 → 验证行合并

2. **编号更新测试**
   - 创建有序列表 → 插入新项 → 验证编号更新
   - 创建有序列表 → 删除某项 → 验证编号更新

3. **勾选框测试**
   - 创建勾选框列表 → 点击勾选框 → 验证状态切换
   - 创建勾选框列表 → 回车创建新项 → 验证新项为未勾选状态
   - 创建勾选框列表 → 使用快捷键切换状态 → 验证状态切换

