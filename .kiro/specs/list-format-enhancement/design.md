# Design Document: 列表格式增强

## Overview

本设计文档描述了原生编辑器有序列表和无序列表功能的优化实现。核心目标是提供完整的列表创建、切换、转换、继承和取消功能，确保与小米笔记 XML 格式兼容，并保证列表与标题格式的互斥性。

### 设计原则

1. **附件渲染**：列表符号使用 NSTextAttachment 子类渲染，确保符号作为整体处理
2. **格式互斥**：列表格式与标题格式互斥，列表始终使用正文字体大小
3. **XML 兼容**：严格遵循小米笔记 XML 格式规范
4. **状态同步**：菜单栏和工具栏状态与编辑器内容保持同步

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        MenuActionHandler                         │
│                    (菜单动作入口)                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FormatStateManager                          │
│                    (格式状态管理)                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     NativeEditorContext                          │
│                    (编辑器上下文)                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       ListFormatHandler                          │
│                    (列表格式处理器 - 新增)                        │
├─────────────────────────────────────────────────────────────────┤
│  - applyBulletList()      应用无序列表                           │
│  - applyOrderedList()     应用有序列表                           │
│  - removeListFormat()     移除列表格式                           │
│  - toggleListFormat()     切换列表格式                           │
│  - convertListType()      转换列表类型                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│     BulletAttachment      │   │     OrderAttachment       │
│   (无序列表项目符号)       │   │   (有序列表编号)          │
└───────────────────────────┘   └───────────────────────────┘
```

## Components and Interfaces

### 1. ListFormatHandler（新增组件）

列表格式处理器，负责所有列表相关的格式操作。

```swift
/// 列表格式处理器
/// 负责处理列表格式的应用、切换、转换和移除
/// _Requirements: 1.1-1.3, 2.1-2.3, 3.1-3.3, 4.1-4.3, 5.1-5.3_
@MainActor
public struct ListFormatHandler {
    
    // MARK: - 列表应用
    
    /// 应用无序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    /// _Requirements: 1.1, 2.1, 6.1_
    public static func applyBulletList(
        to textStorage: NSTextStorage,
        range: NSRange,
        indent: Int = 1
    )
    
    /// 应用有序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - number: 起始编号（默认为 1）
    ///   - indent: 缩进级别（默认为 1）
    /// _Requirements: 1.2, 2.2, 6.2_
    public static func applyOrderedList(
        to textStorage: NSTextStorage,
        range: NSRange,
        number: Int = 1,
        indent: Int = 1
    )
    
    // MARK: - 列表移除
    
    /// 移除列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    /// _Requirements: 3.1, 3.2, 3.3_
    public static func removeListFormat(
        from textStorage: NSTextStorage,
        range: NSRange
    )
    
    // MARK: - 列表切换
    
    /// 切换无序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    /// _Requirements: 3.1, 4.2_
    public static func toggleBulletList(
        to textStorage: NSTextStorage,
        range: NSRange
    )
    
    /// 切换有序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    /// _Requirements: 3.2, 4.1_
    public static func toggleOrderedList(
        to textStorage: NSTextStorage,
        range: NSRange
    )
    
    // MARK: - 列表类型转换
    
    /// 转换列表类型
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - targetType: 目标列表类型
    /// _Requirements: 4.1, 4.2, 4.3_
    public static func convertListType(
        in textStorage: NSTextStorage,
        range: NSRange,
        to targetType: ListType
    )
    
    // MARK: - 格式互斥处理
    
    /// 处理列表与标题的互斥
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    /// _Requirements: 5.1, 5.2, 5.3_
    public static func handleListHeadingMutualExclusion(
        in textStorage: NSTextStorage,
        range: NSRange
    )
    
    // MARK: - 列表检测
    
    /// 检测当前行的列表类型
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 光标位置
    /// - Returns: 列表类型
    public static func detectListType(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> ListType
    
    /// 检测当前行是否为空列表项
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 光标位置
    /// - Returns: 是否为空列表项
    public static func isEmptyListItem(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool
}
```

### 2. NewLineHandler 扩展

扩展现有的 NewLineHandler 以支持列表换行逻辑。

```swift
extension NewLineHandler {
    
    /// 处理列表行换行
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    /// - Returns: 是否已处理
    /// _Requirements: 7.1, 7.2, 7.3, 8.1, 8.2, 8.3_
    public static func handleListNewLine(
        context: NewLineContext,
        textView: NSTextView
    ) -> Bool
    
    /// 处理空列表项回车
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 是否已处理
    /// _Requirements: 8.1, 8.2, 8.3_
    public static func handleEmptyListItemEnter(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool
}
```

### 3. XML 转换器扩展

扩展 AttributedStringToASTConverter 和 ASTToAttributedStringConverter 以支持列表格式。

```swift
// AttributedStringToASTConverter 扩展
extension AttributedStringToASTConverter {
    
    /// 检测并转换列表行
    /// - Parameters:
    ///   - lineRange: 行范围
    ///   - textStorage: 文本存储
    /// - Returns: 列表节点（如果是列表行）
    /// _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
    func convertListLine(
        lineRange: NSRange,
        textStorage: NSTextStorage
    ) -> (any BlockNode)?
}

// ASTToAttributedStringConverter 扩展
extension ASTToAttributedStringConverter {
    
    /// 转换无序列表节点
    /// - Parameter node: 无序列表节点
    /// - Returns: NSAttributedString
    /// _Requirements: 9.1, 9.4_
    func convertBulletList(_ node: BulletListNode) -> NSAttributedString
    
    /// 转换有序列表节点
    /// - Parameter node: 有序列表节点
    /// - Returns: NSAttributedString
    /// _Requirements: 9.2, 9.3, 9.4_
    func convertOrderedList(_ node: OrderedListNode) -> NSAttributedString
}
```

## Data Models

### 列表类型枚举（已存在）

```swift
/// 列表类型
enum ListType: Equatable {
    case bullet     // 无序列表
    case ordered    // 有序列表
    case checkbox   // 复选框列表
    case none       // 非列表
}
```

### 自定义属性键（已存在）

```swift
extension NSAttributedString.Key {
    /// 列表类型属性键
    static let listType = NSAttributedString.Key("listType")
    
    /// 列表缩进级别属性键
    static let listIndent = NSAttributedString.Key("listIndent")
    
    /// 列表编号属性键
    static let listNumber = NSAttributedString.Key("listNumber")
}
```

### BulletAttachment（已存在）

```swift
/// 项目符号附件 - 用于渲染无序列表的项目符号
final class BulletAttachment: NSTextAttachment, ThemeAwareAttachment {
    /// 缩进级别
    var indent: Int = 1
    
    /// 项目符号大小
    var bulletSize: CGFloat = 6
    
    /// 附件总宽度
    var attachmentWidth: CGFloat = 20
}
```

### OrderAttachment（已存在）

```swift
/// 有序列表附件 - 用于渲染有序列表的编号
final class OrderAttachment: NSTextAttachment, ThemeAwareAttachment {
    /// 列表编号
    var number: Int = 1
    
    /// 输入编号（对应 XML 中的 inputNumber 属性）
    var inputNumber: Int = 0
    
    /// 缩进级别
    var indent: Int = 1
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: 列表创建使用正确的附件类型

*For any* 空行或有内容的行，当应用无序列表格式时，行首应该包含 BulletAttachment；当应用有序列表格式时，行首应该包含 OrderAttachment。

**Validates: Requirements 1.1, 1.2, 2.1, 2.2, 6.1, 6.2**

### Property 2: 列表转换保留文本内容

*For any* 有文本内容的行，当转换为列表格式时，原有文本内容应该完整保留，且行应该具有正确的 listType 属性。

**Validates: Requirements 2.1, 2.2, 2.3**

### Property 3: 列表切换（取消）正确移除格式

*For any* 列表行，当再次应用相同类型的列表格式时，列表格式应该被移除，文本内容应该保留，且行应该恢复为正文格式。

**Validates: Requirements 3.1, 3.2, 3.3**

### Property 4: 列表类型转换正确替换附件

*For any* 列表行，当应用不同类型的列表格式时，列表附件应该被正确替换，listType 属性应该更新为新类型。

**Validates: Requirements 4.1, 4.2, 4.3**

### Property 5: 列表与标题格式互斥

*For any* 行，列表格式和标题格式不能同时存在。当应用列表格式时，标题格式应该被移除；当应用标题格式时，列表格式应该被移除。列表行的字体大小应该始终为正文大小（14pt）。

**Validates: Requirements 5.1, 5.2, 5.3**

### Property 6: 列表中回车正确继承格式

*For any* 有内容的列表行，当按下回车时，新行应该继承列表格式和缩进级别。对于有序列表，编号应该自动递增。新行应该清除内联格式但保留列表格式。

**Validates: Requirements 7.1, 7.2, 7.3**

### Property 7: 空列表回车正确取消格式

*For any* 空的列表行，当按下回车时，列表格式应该被取消而非换行，当前行应该恢复为普通正文格式。

**Validates: Requirements 8.1, 8.2, 8.3**

### Property 8: XML 列表往返转换一致性

*For any* 有效的列表 NSAttributedString，转换为 XML 再转换回 NSAttributedString 后，列表类型、缩进级别、编号和文本内容应该保持一致。

**Validates: Requirements 9.1, 9.2, 9.3, 9.4, 10.1, 10.2, 10.3, 10.4, 10.5**

## Error Handling

### 边界条件处理

1. **空文档**：在空文档中应用列表格式时，创建新的列表行
2. **文档末尾**：在文档末尾的列表行按回车时，正确处理换行或取消格式
3. **选择跨多行**：当选择范围跨越多行时，对每行分别应用列表格式
4. **无效位置**：当光标位置无效时，不执行任何操作

### 错误恢复

1. **附件创建失败**：如果附件创建失败，回退到使用文本字符（"•" 或 "1."）
2. **XML 解析失败**：如果 XML 解析失败，记录错误日志并使用纯文本回退
3. **格式应用失败**：如果格式应用失败，保持原有内容不变

## Testing Strategy

### 单元测试

1. **ListFormatHandler 测试**
   - 测试空行创建列表
   - 测试有内容行转换为列表
   - 测试列表切换（取消）
   - 测试列表类型转换
   - 测试列表与标题互斥

2. **NewLineHandler 列表测试**
   - 测试有内容列表行回车继承
   - 测试空列表行回车取消
   - 测试有序列表编号递增

3. **XML 转换测试**
   - 测试无序列表 XML 生成
   - 测试有序列表 XML 生成
   - 测试 inputNumber 规则
   - 测试列表内联格式转换

### 属性测试

使用 Swift 的属性测试框架（如 SwiftCheck）验证正确性属性：

- 最小 100 次迭代
- 每个属性测试引用设计文档中的属性编号
- 标签格式：**Feature: list-format-enhancement, Property {number}: {property_text}**

### 集成测试

1. **端到端列表操作测试**
   - 创建列表 → 编辑内容 → 保存 → 重新加载 → 验证内容
   
2. **菜单状态同步测试**
   - 移动光标到不同格式的行 → 验证菜单状态更新
