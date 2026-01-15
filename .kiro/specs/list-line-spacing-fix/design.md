# 设计文档

## 概述

本设计解决原生编辑器中列表样式（复选框、有序列表、无序列表）行间距与普通正文不一致的问题。通过在列表段落样式创建方法中添加 `lineSpacing` 和 `paragraphSpacing` 属性，使列表项的行间距与正文保持一致。

## 架构

### 当前问题

当前代码中，`ASTToAttributedStringConverter` 为正文设置了默认段落样式：
- `lineSpacing = 4`
- `paragraphSpacing = 8`

但列表段落样式创建方法（`createListParagraphStyle`）只设置了缩进和制表位，没有设置行间距属性，导致列表项使用系统默认的行间距（0），显得比正文紧凑。

### 解决方案

在所有 `createListParagraphStyle` 方法中添加行间距设置，并定义统一的常量。

## 组件和接口

### 需要修改的文件

1. **ListFormatHandler.swift**
   - 修改 `createListParagraphStyle` 方法
   - 添加 `lineSpacing` 和 `paragraphSpacing` 设置

2. **BlockFormatHandler.swift**
   - 修改 `createListParagraphStyle` 方法
   - 添加 `lineSpacing` 和 `paragraphSpacing` 设置

3. **FormatManager.swift**
   - 修改 `createListParagraphStyle` 方法
   - 添加 `lineSpacing` 和 `paragraphSpacing` 设置

4. **ListBehaviorHandler.swift**
   - 修改直接创建段落样式的代码
   - 添加 `lineSpacing` 和 `paragraphSpacing` 设置

### 常量定义

在 `ListFormatHandler.swift` 中定义统一的常量（其他文件可以使用相同的值）：

```swift
/// 默认行间距（与正文一致）
private static let defaultLineSpacing: CGFloat = 4

/// 默认段落间距（与正文一致）
private static let defaultParagraphSpacing: CGFloat = 8
```

## 数据模型

无需修改数据模型，只需修改段落样式的创建逻辑。

## 正确性属性

*正确性属性是一种特征或行为，应该在系统的所有有效执行中保持为真——本质上是关于系统应该做什么的正式声明。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 列表段落样式行间距一致性

*对于任意* 列表类型（无序、有序、复选框）和任意缩进级别，创建的段落样式的 `lineSpacing` 应等于 4。

**Validates: Requirements 1.1, 1.2, 1.3**

### Property 2: 列表段落样式段落间距一致性

*对于任意* 列表类型和任意缩进级别，创建的段落样式的 `paragraphSpacing` 应等于 8。

**Validates: Requirements 1.4**

### Property 3: 列表缩进计算正确性

*对于任意* 列表类型、任意缩进级别（1-10）和任意项目符号宽度，创建的段落样式应满足：
- `firstLineHeadIndent = (indent - 1) * indentUnit`
- `headIndent = (indent - 1) * indentUnit + bulletWidth`
- `tabStops` 包含正确位置的制表位

**Validates: Requirements 3.1, 3.2, 3.3**

## 错误处理

本修改不涉及错误处理逻辑的变更。段落样式创建是纯计算操作，不会产生运行时错误。

## 测试策略

### 单元测试

- 测试各个 `createListParagraphStyle` 方法返回的段落样式属性是否正确

### 属性测试

使用 Swift 的 XCTest 框架进行属性测试：

1. **行间距属性测试**：生成随机的列表类型和缩进级别，验证 `lineSpacing` 始终为 4
2. **段落间距属性测试**：生成随机的列表类型和缩进级别，验证 `paragraphSpacing` 始终为 8
3. **缩进计算属性测试**：生成随机的缩进级别和项目符号宽度，验证缩进计算公式正确

### 视觉验证

- 在编辑器中创建各种列表类型，目视确认行间距与正文一致
