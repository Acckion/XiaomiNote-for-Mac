# 设计文档

## 概述

本设计文档描述如何优化有序列表和无序列表的显示效果，解决列表标记左边间距过大的问题。核心思路是调整列表附件的尺寸和位置，以及段落样式的缩进设置，使列表标记与普通正文左边缘对齐。

## 架构

### 当前架构问题

```
当前列表渲染结构：
┌─────────────────────────────────────────────────────────┐
│ [firstLineHeadIndent] [Attachment(20-24pt)] [Content]   │
│                       ↑                                  │
│                       附件内部有额外空白                   │
└─────────────────────────────────────────────────────────┘

问题：
1. firstLineHeadIndent 为 0，但附件内部左侧有大量空白
2. BulletAttachment 宽度 20pt，但符号只有 6pt，居中渲染
3. OrderAttachment 宽度 24pt，编号右对齐，左侧空白
```

### 目标架构

```
优化后的列表渲染结构：
┌─────────────────────────────────────────────────────────┐
│ [Marker][Gap][Content]                                   │
│ ↑       ↑    ↑                                          │
│ 左对齐  固定  内容起始                                    │
└─────────────────────────────────────────────────────────┘

改进：
1. 列表标记左对齐渲染（不居中或右对齐）
2. 附件宽度 = 标记宽度 + 固定间距
3. headIndent = 附件宽度（悬挂缩进）
```

## 组件和接口

### 1. BulletAttachment 修改

```swift
// 修改前
var bulletSize: CGFloat = 6
var attachmentWidth: CGFloat = 20  // 过大

// 修改后
var bulletSize: CGFloat = 6
var attachmentWidth: CGFloat = 16  // 符号 + 间距
// 符号左对齐渲染，而非居中
```

### 2. OrderAttachment 修改

```swift
// 修改前
var attachmentWidth: CGFloat = 24  // 过大，编号右对齐

// 修改后
var attachmentWidth: CGFloat = 20  // 足够容纳 "99." + 间距
// 编号左对齐渲染，而非右对齐
```

### 3. ListFormatHandler 修改

```swift
// 修改前
public static let bulletWidth: CGFloat = 24
public static let orderNumberWidth: CGFloat = 28

// 修改后
public static let bulletWidth: CGFloat = 16
public static let orderNumberWidth: CGFloat = 20

// 段落样式调整
private static func createListParagraphStyle(indent: Int, bulletWidth: CGFloat) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    let baseIndent = CGFloat(indent - 1) * indentUnit
    
    // 首行缩进 = 基础缩进（嵌套级别）
    style.firstLineHeadIndent = baseIndent
    // 悬挂缩进 = 基础缩进 + 标记宽度
    style.headIndent = baseIndent + bulletWidth
    
    return style
}
```

### 4. InteractiveCheckboxAttachment 修改

```swift
// 修改前
var attachmentWidth: CGFloat = 20  // 可能过大

// 修改后
var attachmentWidth: CGFloat = 18  // 复选框 + 间距
// 复选框左对齐渲染
```

## 数据模型

本次修改不涉及数据模型变更，仅调整渲染参数。

### 常量定义

```swift
// ListFormatHandler 中的常量
public static let indentUnit: CGFloat = 20        // 缩进单位（保持不变）
public static let bulletWidth: CGFloat = 16       // 项目符号宽度（减小）
public static let orderNumberWidth: CGFloat = 20  // 有序列表编号宽度（减小）
public static let checkboxWidth: CGFloat = 18     // 复选框宽度（减小）
```



## 正确性属性

*正确性属性是应该在系统所有有效执行中保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 列表标记位置对齐

*对于任意*列表类型（无序、有序、复选框）和任意缩进级别 n，列表标记的左边缘 x 坐标应该等于 `(n - 1) * indentUnit`，其中 indentUnit = 20pt。

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 3.1, 3.2**

### Property 2: 悬挂缩进正确性

*对于任意*列表项，段落样式的 `headIndent` 值应该等于 `firstLineHeadIndent + markerWidth`，其中 markerWidth 是对应列表类型的标记宽度。

**Validates: Requirements 2.1, 2.2, 2.3**

### Property 3: 附件尺寸合理性

*对于任意*列表附件：
- BulletAttachment 的宽度应该在 [12, 20] pt 范围内
- OrderAttachment 的宽度应该足够容纳 "99." 文本但不超过 24pt
- 附件的垂直位置应该使标记与文本基线对齐

**Validates: Requirements 4.1, 4.2, 4.3**

### Property 4: 间距一致性

*对于任意*列表项，段落样式的 `lineSpacing` 和 `paragraphSpacing` 应该与正文默认值一致（lineSpacing = 4pt, paragraphSpacing = 8pt）。

**Validates: Requirements 5.3**

## 错误处理

### 边界情况

1. **空列表项**：应用列表格式到空行时，仍应正确设置对齐参数
2. **超长编号**：编号超过 99 时（如 100.），附件宽度应能容纳
3. **深层嵌套**：缩进级别超过 5 时，仍应正确计算位置

### 错误恢复

1. 如果附件渲染失败，回退到默认尺寸
2. 如果段落样式设置失败，保持原有样式

## 测试策略

### 单元测试

1. **BulletAttachment 尺寸测试**
   - 验证 attachmentWidth 值
   - 验证 attachmentBounds 返回正确的位置和尺寸

2. **OrderAttachment 尺寸测试**
   - 验证 attachmentWidth 值
   - 验证不同编号长度下的渲染

3. **段落样式测试**
   - 验证 createListParagraphStyle 返回正确的缩进值

### 属性测试

使用 Swift 的 XCTest 框架进行属性测试，每个属性测试运行至少 100 次迭代。

1. **Property 1 测试**：生成随机列表类型和缩进级别，验证标记位置
2. **Property 2 测试**：生成随机列表项，验证悬挂缩进
3. **Property 3 测试**：验证附件尺寸在合理范围内
4. **Property 4 测试**：验证间距值一致性

### 测试标注格式

```swift
// **Feature: list-indent-alignment, Property 1: 列表标记位置对齐**
// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 3.1, 3.2**
func testListMarkerPositionAlignment() {
    // 属性测试实现
}
```
