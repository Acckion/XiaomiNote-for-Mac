# 设计文档

## 概述

本设计文档描述了如何在原生编辑器中实现复选框列表支持。复选框列表的核心逻辑复用现有的 `ListBehaviorHandler` 和 `ListFormatHandler`，仅需扩展以支持 `.checkbox` 类型。

## 架构

### 组件关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        工具栏按钮                                │
│                    toggleCheckbox(_:)                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FormatManager                               │
│                  toggleCheckboxList()                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ListFormatHandler                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ applyCheckbox   │  │ removeCheckbox  │  │ toggleCheckbox  │  │
│  │     List()      │  │     List()      │  │     List()      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ListBehaviorHandler                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ handleEnterKey  │  │handleBackspace  │  │ toggleCheckbox  │  │
│  │      ()         │  │     Key()       │  │    State()      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              InteractiveCheckboxAttachment                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   isChecked     │  │   handleClick   │  │  createImage    │  │
│  │                 │  │      ()         │  │      ()         │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 数据流

```
用户点击工具栏按钮
        │
        ▼
MainWindowController.toggleCheckbox(_:)
        │
        ▼
FormatManager.toggleCheckboxList()
        │
        ├─── 检测当前行列表类型
        │
        ├─── 如果是复选框 → 移除格式
        │
        ├─── 如果是其他列表 → 转换为复选框
        │
        └─── 如果不是列表 → 应用复选框格式
                    │
                    ▼
            ListFormatHandler.applyCheckboxList()
                    │
                    ├─── 处理标题互斥
                    │
                    ├─── 创建 InteractiveCheckboxAttachment
                    │
                    ├─── 插入附件到行首
                    │
                    └─── 设置列表属性和段落样式
```

## 组件和接口

### ListFormatHandler 扩展

```swift
/// 应用复选框列表格式
/// 
/// 在行首插入 InteractiveCheckboxAttachment，设置列表类型属性
/// 
/// - Parameters:
///   - textStorage: 文本存储
///   - range: 应用范围
///   - indent: 缩进级别（默认为 1）
/// _Requirements: 1.1, 1.4, 1.5_
public static func applyCheckboxList(
    to textStorage: NSTextStorage,
    range: NSRange,
    indent: Int = 1
) {
    let lineRange = (textStorage.string as NSString).lineRange(for: range)
    
    // 先处理列表与标题的互斥
    handleListHeadingMutualExclusion(in: textStorage, range: lineRange)
    
    textStorage.beginEditing()
    
    // 创建 InteractiveCheckboxAttachment（默认未勾选）
    let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: 3, indent: indent)
    let attachmentString = NSAttributedString(attachment: checkboxAttachment)
    
    // 在行首插入附件
    let lineStart = lineRange.location
    textStorage.insert(attachmentString, at: lineStart)
    
    // 更新行范围
    let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)
    
    // 设置列表类型属性
    textStorage.addAttribute(.listType, value: ListType.checkbox, range: newLineRange)
    textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)
    textStorage.addAttribute(.checkboxLevel, value: 3, range: newLineRange)
    textStorage.addAttribute(.checkboxChecked, value: false, range: newLineRange)
    
    // 设置段落样式
    let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: checkboxWidth)
    textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
    
    // 确保使用正文字体大小
    applyBodyFontSizePreservingTraits(to: textStorage, range: newLineRange)
    
    textStorage.endEditing()
}

/// 切换复选框列表格式
/// 
/// 如果当前行是复选框列表，则移除；否则应用复选框列表
/// 如果当前行是有序/无序列表，则转换为复选框列表
/// 
/// - Parameters:
///   - textStorage: 文本存储
///   - range: 应用范围
/// _Requirements: 1.2, 1.3_
public static func toggleCheckboxList(
    to textStorage: NSTextStorage,
    range: NSRange
) {
    let currentType = detectListType(in: textStorage, at: range.location)
    
    switch currentType {
    case .checkbox:
        // 已经是复选框列表，移除格式
        removeCheckboxList(from: textStorage, range: range)
        
    case .bullet, .ordered:
        // 是其他列表，先移除再应用复选框
        removeListFormat(from: textStorage, range: range)
        applyCheckboxList(to: textStorage, range: range)
        
    case .none:
        // 不是列表，应用复选框列表
        applyCheckboxList(to: textStorage, range: range)
    }
}

/// 移除复选框列表格式
/// 
/// 移除复选框附件和列表类型属性，保留文本内容
/// 
/// - Parameters:
///   - textStorage: 文本存储
///   - range: 应用范围
/// _Requirements: 1.2_
public static func removeCheckboxList(
    from textStorage: NSTextStorage,
    range: NSRange
) {
    let lineRange = (textStorage.string as NSString).lineRange(for: range)
    
    textStorage.beginEditing()
    
    // 查找并移除复选框附件
    var attachmentRange: NSRange?
    textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
        if value is InteractiveCheckboxAttachment {
            attachmentRange = attrRange
            stop.pointee = true
        }
    }
    
    // 移除附件
    if let range = attachmentRange {
        textStorage.deleteCharacters(in: range)
    }
    
    // 重新计算行范围
    let newLineRange: NSRange
    if let range = attachmentRange {
        newLineRange = NSRange(location: lineRange.location, length: lineRange.length - range.length)
    } else {
        newLineRange = lineRange
    }
    
    // 移除列表相关属性
    if newLineRange.length > 0 {
        textStorage.removeAttribute(.listType, range: newLineRange)
        textStorage.removeAttribute(.listIndent, range: newLineRange)
        textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
        textStorage.removeAttribute(.checkboxChecked, range: newLineRange)
        
        // 重置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
    }
    
    textStorage.endEditing()
}
```

### ListBehaviorHandler 现有支持

`ListBehaviorHandler` 已经完整支持复选框列表的行为处理：

1. **光标限制** - `getContentStartPosition()` 和 `adjustCursorPosition()` 已支持 `InteractiveCheckboxAttachment`
2. **回车键处理** - `handleEnterKey()` 已支持 `.checkbox` 类型，`createNewListItem()` 会创建未勾选的新复选框
3. **删除键处理** - `handleBackspaceKey()` 已支持复选框列表的合并和取消
4. **勾选状态切换** - `toggleCheckboxState()` 已实现

### XML 格式转换

复选框的 XML 格式：
```xml
<input type="checkbox" indent="1" level="3" />待办事项
<input type="checkbox" indent="1" level="3" checked="true" />已完成事项
```

`XiaoMiFormatConverter` 已支持：
- 解析：`processCheckboxElementToNSAttributedString()` 创建 `InteractiveCheckboxAttachment`
- 导出：`convertNSLineToXML()` 检测 `InteractiveCheckboxAttachment` 并生成正确的 XML

## 数据模型

### ListType 枚举

```swift
/// 列表类型枚举
public enum ListType: Int, Codable {
    case none = 0      // 非列表
    case bullet = 1    // 无序列表
    case ordered = 2   // 有序列表
    case checkbox = 3  // 复选框列表
}
```

### NSAttributedString.Key 扩展

```swift
extension NSAttributedString.Key {
    /// 列表类型
    static let listType = NSAttributedString.Key("listType")
    
    /// 列表缩进级别
    static let listIndent = NSAttributedString.Key("listIndent")
    
    /// 列表编号（仅有序列表）
    static let listNumber = NSAttributedString.Key("listNumber")
    
    /// 复选框级别
    static let checkboxLevel = NSAttributedString.Key("checkboxLevel")
    
    /// 复选框勾选状态
    static let checkboxChecked = NSAttributedString.Key("checkboxChecked")
}
```

### InteractiveCheckboxAttachment 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| isChecked | Bool | 勾选状态 |
| level | Int | 级别（对应 XML 中的 level 属性，默认 3） |
| indent | Int | 缩进值（对应 XML 中的 indent 属性，默认 1） |
| checkboxSize | CGFloat | 复选框大小（默认 16） |

## 错误处理

### 边界情况

1. **空文档** - 在空文档中应用复选框格式时，创建包含复选框附件的新行
2. **文档末尾** - 在文档最后一行（无换行符）应用复选框格式时，正确处理行范围
3. **多行选择** - 当选择跨越多行时，只对第一行应用复选框格式
4. **嵌套列表** - 复选框列表支持缩进，但不支持嵌套其他列表类型

### 错误恢复

1. **附件创建失败** - 如果 `InteractiveCheckboxAttachment` 创建失败，回退到普通文本
2. **属性设置失败** - 使用 `beginEditing()`/`endEditing()` 确保原子操作



## 正确性属性

*正确性属性是一种特征或行为，应该在系统的所有有效执行中保持为真——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 复选框格式应用正确性

*For any* 普通文本行，应用复选框格式后：
1. 行首应包含一个 `InteractiveCheckboxAttachment` 类型的附件
2. `listType` 属性应为 `.checkbox`
3. `listIndent` 属性应为指定的缩进级别
4. 段落样式的 `headIndent` 应正确设置

**Validates: Requirements 1.1, 1.4, 1.5**

### Property 2: 复选框列表切换行为

*For any* 文本行：
1. 如果是复选框列表，切换后应变为普通正文（无列表附件）
2. 如果是有序/无序列表，切换后应变为复选框列表
3. 如果是普通正文，切换后应变为复选框列表

**Validates: Requirements 1.2, 1.3**

### Property 3: 复选框回车键分割行为

*For any* 有内容的复选框列表项和任意光标位置：
1. 回车后应创建两行，原行保留光标前的内容
2. 新行应包含光标后的内容
3. 新行应有 `InteractiveCheckboxAttachment` 附件
4. 新行的复选框应为未勾选状态
5. 新行应继承原行的缩进级别

**Validates: Requirements 2.1, 2.2, 2.3**

### Property 4: 空复选框回车键取消行为

*For any* 空复选框列表项（只有附件没有内容）：
1. 回车后应移除复选框附件
2. 行应变为普通正文
3. 不应创建新行
4. `listType` 属性应被移除

**Validates: Requirements 2.4, 2.5**

### Property 5: 复选框删除键行为

*For any* 复选框列表项，当光标在内容起始位置按删除键：
1. 如果是空列表项，应只删除复选框标记，保留空行
2. 如果有内容且有上一行，应将内容合并到上一行
3. 合并后光标应位于原上一行末尾位置

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

### Property 6: 复选框光标限制

*For any* 复选框列表项和任意位置：
1. 如果位置在复选框附件范围内，`isInListMarkerArea` 应返回 true
2. `adjustCursorPosition` 应将标记区域内的位置调整到内容起始位置
3. 内容起始位置应等于附件结束位置

**Validates: Requirements 4.1, 4.2**

### Property 7: 复选框勾选状态切换

*For any* 复选框列表项：
1. 调用 `toggleCheckboxState` 后，`isChecked` 状态应取反
2. 切换前后光标位置应保持不变

**Validates: Requirements 5.1, 5.3**

### Property 8: 复选框 XML 解析导出 Round Trip

*For any* 有效的复选框 XML 字符串：
1. 解析后应创建 `InteractiveCheckboxAttachment`
2. 附件的 `indent` 和 `level` 属性应与 XML 中的值匹配
3. 如果 XML 包含 `checked="true"`，附件的 `isChecked` 应为 true
4. 导出后的 XML 应与原始 XML 等价（属性顺序可能不同）

**Validates: Requirements 6.1, 6.2, 6.3, 6.4**

### Property 9: 复选框与标题互斥

*For any* 标题行（字体大小 > 14pt）：
1. 应用复选框格式后，字体大小应变为 14pt
2. 字体特性（加粗、斜体）应保留
3. 行应变为复选框列表

**Validates: Requirements 7.1, 7.3, 7.4**

## 测试策略

### 测试框架

- **单元测试框架**: XCTest
- **属性测试框架**: SwiftCheck（如果可用）或手动实现属性测试

### 双重测试方法

1. **单元测试**: 验证特定示例和边界情况
   - 空文档应用复选框格式
   - 文档末尾应用复选框格式
   - 多行选择时的行为

2. **属性测试**: 验证所有输入的通用属性
   - 每个属性测试至少运行 100 次迭代
   - 使用随机生成的文本内容和光标位置

### 测试配置

- 每个属性测试最少 100 次迭代
- 每个属性测试必须引用设计文档中的属性
- 标签格式: **Feature: checkbox-list-support, Property {number}: {property_text}**

### 测试文件结构

```
Tests/NativeEditorTests/
├── CheckboxListFormatPropertyTests.swift    # Property 1, 2, 9
├── CheckboxListBehaviorPropertyTests.swift  # Property 3, 4, 5, 6, 7
└── CheckboxXMLRoundTripPropertyTests.swift  # Property 8
```

### 现有测试复用

由于复选框列表的行为逻辑与有序/无序列表一致，以下现有测试可以扩展以覆盖复选框：

- `ListBehaviorHandlerTests.swift` - 扩展以测试复选框类型
- `ListFormatHandlerTests.swift` - 扩展以测试复选框格式
- `XMLRoundTripPropertyTests.swift` - 扩展以测试复选框 XML
