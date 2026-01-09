# 设计文档：复选框同步修复

## 概述

本设计文档描述了如何修复原生编辑器中复选框的同步问题。核心改动是将 `processCheckboxElement` 和 `processCheckboxElementToNSAttributedString` 方法从使用 Unicode 字符改为使用 `InteractiveCheckboxAttachment`（NSTextAttachment 子类）。

## 架构

### 当前问题

```
XML 输入: <input type="checkbox" indent="1" level="3" />待办事项

当前实现（错误）:
processCheckboxElement() -> AttributedString("☐ 待办事项")
                                              ↑
                                        Unicode 字符，无法交互

期望实现（正确）:
processCheckboxElementToNSAttributedString() -> NSAttributedString([Attachment] + "待办事项")
                                                                      ↑
                                                        InteractiveCheckboxAttachment，可交互
```

### 修复后的数据流

```
┌─────────────────────────────────────────────────────────────────────┐
│                        XML 解析流程                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  XML: <input type="checkbox" indent="1" level="3" />待办事项          │
│                           │                                          │
│                           ▼                                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ processCheckboxElementToNSAttributedString()                 │    │
│  │                                                              │    │
│  │  1. 提取属性: indent=1, level=3                              │    │
│  │  2. 提取内容: "待办事项"                                      │    │
│  │  3. 创建 InteractiveCheckboxAttachment(level=3, indent=1)    │    │
│  │  4. 创建 NSAttributedString(attachment: checkbox)            │    │
│  │  5. 追加文本内容                                              │    │
│  │  6. 设置段落样式（缩进）                                       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                           │                                          │
│                           ▼                                          │
│  NSAttributedString: [\u{FFFC}] + "待办事项"                         │
│                         ↑                                            │
│            InteractiveCheckboxAttachment                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        XML 导出流程                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  NSAttributedString: [\u{FFFC}] + "待办事项"                         │
│                           │                                          │
│                           ▼                                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ convertNSLineToXML()                                         │    │
│  │                                                              │    │
│  │  1. 检测到 attachment 属性                                    │    │
│  │  2. 识别为 InteractiveCheckboxAttachment                     │    │
│  │  3. 调用 convertAttachmentToXML()                            │    │
│  │  4. 生成: <input type="checkbox" indent="1" level="3" />     │    │
│  │  5. 追加后续文本内容                                          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                           │                                          │
│                           ▼                                          │
│  XML: <input type="checkbox" indent="1" level="3" />待办事项          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 组件和接口

### 1. XiaoMiFormatConverter 修改

需要修改以下方法：

#### processCheckboxElementToNSAttributedString (主要修改)

```swift
/// 处理 <input type="checkbox"> 元素并返回 NSAttributedString
/// 
/// 关键修复：直接创建 NSAttributedString 并使用 InteractiveCheckboxAttachment
/// 而不是使用 Unicode 字符
private func processCheckboxElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
    // 1. 提取属性
    let indent = Int(extractAttribute("indent", from: line) ?? "1") ?? 1
    let level = Int(extractAttribute("level", from: line) ?? "3") ?? 3
    
    // 2. 提取复选框后的文本内容
    let content = extractContentAfterElement(from: line, elementName: "input")
    
    // 3. 创建复选框附件
    let checkboxAttachment = CustomRenderer.shared.createCheckboxAttachment(
        checked: false,  // XML 中不保存选中状态，默认未选中
        level: level,
        indent: indent
    )
    
    // 4. 创建包含附件的 NSAttributedString
    let result = NSMutableAttributedString(attachment: checkboxAttachment)
    
    // 5. 追加文本内容（如果有）
    if !content.isEmpty {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        result.append(NSAttributedString(string: content, attributes: textAttributes))
    }
    
    // 6. 设置段落样式
    let paragraphStyle = createParagraphStyle(indent: indent)
    result.addAttribute(.paragraphStyle, value: paragraphStyle, 
                       range: NSRange(location: 0, length: result.length))
    
    return result
}
```

#### processCheckboxElement (保持兼容性)

```swift
/// 处理 <input type="checkbox"> 元素
/// 
/// 注意：此方法返回 AttributedString，但 AttributedString 不能很好地保留
/// 自定义 NSTextAttachment 子类。建议使用 processCheckboxElementToNSAttributedString
private func processCheckboxElement(_ line: String) throws -> AttributedString {
    // 调用 NSAttributedString 版本并转换
    let nsAttributedString = try processCheckboxElementToNSAttributedString(line)
    return AttributedString(nsAttributedString)
}
```

#### convertNSLineToXML (修改以支持复选框行)

```swift
/// 将单行 NSAttributedString 转换为 XML
private func convertNSLineToXML(_ lineAttributedString: NSAttributedString) throws -> String {
    var content = ""
    var indent = 1
    var alignment: NSTextAlignment = .left
    var isCheckboxLine = false
    var checkboxXML = ""
    
    let fullRange = NSRange(location: 0, length: lineAttributedString.length)
    
    lineAttributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
        // 检查是否是附件
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            // 检查是否是复选框附件
            if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
                isCheckboxLine = true
                checkboxXML = "<input type=\"checkbox\" indent=\"\(checkboxAttachment.indent)\" level=\"\(checkboxAttachment.level)\" />"
                return
            }
            
            // 其他附件类型
            do {
                content = try convertAttachmentToXML(attachment)
            } catch {
                print("[XiaoMiFormatConverter] 附件转换失败: \(error)")
            }
            return
        }
        
        // 获取文本内容
        let text = (lineAttributedString.string as NSString).substring(with: range)
        
        // 处理富文本属性
        let taggedText = processNSAttributesToXMLTags(text, attributes: attributes)
        content += taggedText
        
        // 提取缩进级别和对齐方式
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            indent = Int(paragraphStyle.firstLineHeadIndent / 20) + 1
            alignment = paragraphStyle.alignment
        }
    }
    
    // 如果是复选框行，返回复选框格式
    if isCheckboxLine {
        return checkboxXML + content
    }
    
    // 检查是否整行是附件
    if content.hasPrefix("<hr") || content.hasPrefix("<img") || 
       content.hasPrefix("<bullet") || content.hasPrefix("<order") {
        return content
    }
    
    // 处理对齐方式
    switch alignment {
    case .center:
        content = "<center>\(content)</center>"
    case .right:
        content = "<right>\(content)</right>"
    default:
        break
    }
    
    return "<text indent=\"\(indent)\">\(content)</text>"
}
```

### 2. 已有组件（无需修改）

以下组件已经正确实现，无需修改：

- **InteractiveCheckboxAttachment**: 自定义复选框附件类，支持渲染和交互
- **CustomRenderer.createCheckboxAttachment()**: 创建复选框附件的工厂方法
- **convertAttachmentToXML()**: 将附件转换为 XML 的方法（已支持 InteractiveCheckboxAttachment）

## 数据模型

### InteractiveCheckboxAttachment 属性

```swift
class InteractiveCheckboxAttachment: NSTextAttachment {
    var isChecked: Bool = false      // 选中状态（仅本地显示，不保存到 XML）
    var level: Int = 3               // 级别（对应 XML 中的 level 属性）
    var indent: Int = 1              // 缩进（对应 XML 中的 indent 属性）
    var checkboxSize: CGFloat = 16   // 复选框大小
    var isDarkMode: Bool = false     // 深色模式适配
    var onToggle: ((Bool) -> Void)?  // 状态切换回调
}
```

### XML 格式

```xml
<!-- 复选框格式（小米笔记规范） -->
<input type="checkbox" indent="1" level="3" />待办事项内容

<!-- 带富文本的复选框 -->
<input type="checkbox" indent="1" level="3" /><b>重要</b>待办事项
```

## 正确性属性

*正确性属性是系统应该满足的通用规则，用于验证实现的正确性。每个属性都是一个可以通过属性测试验证的规则。*

### Property 1: 复选框解析正确性

*For any* 有效的复选框 XML 字符串（格式为 `<input type="checkbox" indent="N" level="M" />内容`），解析后的 NSAttributedString 应该：
1. 包含一个 InteractiveCheckboxAttachment 类型的附件
2. 附件的 indent 属性等于 XML 中的 indent 值
3. 附件的 level 属性等于 XML 中的 level 值
4. 附件后的文本内容等于 XML 中的内容部分

**Validates: Requirements 1.1, 1.2, 1.3**

### Property 2: 复选框导出正确性

*For any* 包含 InteractiveCheckboxAttachment 的 NSAttributedString，导出的 XML 应该：
1. 以 `<input type="checkbox"` 开头
2. 包含正确的 indent 属性
3. 包含正确的 level 属性
4. 附件后的文本内容正确追加在 XML 标签之后

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

### Property 3: 复选框往返转换一致性

*For any* 有效的复选框 XML 字符串，经过解析（XML → NSAttributedString）和导出（NSAttributedString → XML）往返转换后，生成的 XML 应该与原始 XML 等价（忽略空白字符差异）。

**Validates: Requirements 3.1**

### Property 4: 选中状态不影响导出

*For any* InteractiveCheckboxAttachment，无论其 isChecked 属性为 true 还是 false，导出的 XML 格式应该相同（不包含选中状态信息）。

**Validates: Requirements 4.5**

### Property 5: 新插入复选框默认未选中

*For any* 通过 CustomRenderer.createCheckboxAttachment() 创建的复选框附件，其 isChecked 属性应该为 false。

**Validates: Requirements 5.2**

## 错误处理

### 解析错误

1. **无效的 XML 格式**: 如果 XML 格式不正确，抛出 `ConversionError.invalidXML` 错误
2. **缺少必要属性**: 如果缺少 indent 或 level 属性，使用默认值（indent=1, level=3）
3. **属性值无效**: 如果属性值不是有效的整数，使用默认值

### 导出错误

1. **附件类型未知**: 如果遇到未知的附件类型，记录警告日志并跳过
2. **文本内容为空**: 如果复选框后没有文本内容，只导出复选框标签

## 测试策略

### 单元测试

1. **解析测试**
   - 测试基本复选框 XML 解析
   - 测试带有不同 indent 和 level 值的解析
   - 测试带有富文本内容的解析
   - 测试缺少属性时的默认值处理

2. **导出测试**
   - 测试基本复选框导出
   - 测试带有文本内容的导出
   - 测试选中状态不影响导出

3. **交互测试**
   - 测试点击复选框切换状态
   - 测试状态切换回调

### 属性测试

使用 Swift 的属性测试框架（如 SwiftCheck）验证正确性属性：

```swift
// Property 1: 解析正确性
func testCheckboxParsingProperty() {
    property("解析后的附件属性应该与 XML 属性一致") <- forAll { (indent: Int, level: Int, content: String) in
        let xml = "<input type=\"checkbox\" indent=\"\(indent)\" level=\"\(level)\" />\(content)"
        let result = try? converter.xmlToNSAttributedString(xml)
        // 验证附件属性
        return verifyCheckboxAttachment(result, expectedIndent: indent, expectedLevel: level, expectedContent: content)
    }
}

// Property 3: 往返转换一致性
func testCheckboxRoundTripProperty() {
    property("往返转换应该保持等价") <- forAll { (indent: Int, level: Int, content: String) in
        let originalXML = "<input type=\"checkbox\" indent=\"\(indent)\" level=\"\(level)\" />\(content)"
        let parsed = try? converter.xmlToNSAttributedString(originalXML)
        let exported = try? converter.nsAttributedStringToXML(parsed!)
        return isEquivalentXML(originalXML, exported!)
    }
}
```

### 测试配置

- 每个属性测试运行至少 100 次迭代
- 使用随机生成的 indent（1-5）、level（1-5）和 content（随机字符串）
- 测试边界情况：空内容、特殊字符、富文本标签
