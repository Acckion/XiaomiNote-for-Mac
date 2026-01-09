# 原生编辑器工具栏与渲染问题修复设计文档

## 概述

本文档描述修复原生编辑器工具栏集成和渲染问题的技术设计方案。

## 问题分析

### 问题 1：工具栏格式菜单硬编码使用 WebFormatMenuView

**根本原因**：`MainWindowController.swift` 中的 `showFormatMenu(_:)` 方法（第 1707 行）硬编码创建 `WebFormatMenuView`，没有检查当前是否使用原生编辑器。

```swift
// 当前代码（错误）
let formatMenuView = WebFormatMenuView(context: webEditorContext) { ... }
```

**解决方案**：修改 `showFormatMenu(_:)` 方法，根据 `isUsingNativeEditor` 状态选择显示 `NativeFormatMenuView` 或 `WebFormatMenuView`。

### 问题 2：斜体文本无法正确渲染

**根本原因**：`XiaoMiFormatConverter.swift` 中的 `NSFont.italic()` 扩展方法使用 `fontDescriptor.withSymbolicTraits(.italic)`，当系统字体（如 Helvetica）没有斜体变体时，会返回原始字体。

```swift
// 当前代码（可能失败）
func italic() -> NSFont {
    let fontDescriptor = self.fontDescriptor
    let italicDescriptor = fontDescriptor.withSymbolicTraits(.italic)
    return NSFont(descriptor: italicDescriptor, size: self.pointSize) ?? self
}
```

**解决方案**：
1. 优先尝试获取字体的斜体变体
2. 如果失败，使用 `NSFontManager` 查找斜体字体
3. 如果仍然失败，使用仿斜体（通过 `NSAffineTransform` 倾斜）

### 问题 3：列表格式使用纯文本而非附件

**根本原因**：`XiaoMiFormatConverter.swift` 中的 `processBulletElement` 和 `processOrderElement` 方法将列表转换为纯文本（如 "• content" 和 "1. content"），而不是使用 `BulletAttachment` 和 `OrderAttachment`。

```swift
// 当前代码（使用纯文本）
private func processBulletElement(_ line: String) throws -> AttributedString {
    var result = AttributedString("• \(content)")  // 纯文本符号
    ...
}
```

**解决方案**：修改这些方法，使用 `CustomRenderer.shared` 创建对应的附件。

## 技术设计

### 1. 工具栏格式菜单集成

#### 1.1 修改 MainWindowController.showFormatMenu

**文件**：`Sources/Window/MainWindowController.swift`

```swift
@objc func showFormatMenu(_ sender: Any?) {
    print("显示格式菜单")
    
    // 如果 popover 已经显示，则关闭它
    if let popover = formatMenuPopover, popover.isShown {
        popover.performClose(sender)
        formatMenuPopover = nil
        return
    }
    
    // 检查是否使用原生编辑器
    let isUsingNativeEditor = viewModel?.isUsingNativeEditor ?? false
    
    let hostingController: NSViewController
    
    if isUsingNativeEditor {
        // 使用原生编辑器格式菜单
        guard let nativeEditorContext = viewModel?.nativeEditorContext else {
            print("无法获取 NativeEditorContext")
            return
        }
        
        let formatMenuView = NativeFormatMenuView(context: nativeEditorContext) { [weak self] in
            self?.formatMenuPopover?.performClose(nil)
            self?.formatMenuPopover = nil
        }
        hostingController = NSHostingController(rootView: formatMenuView)
    } else {
        // 使用 Web 编辑器格式菜单
        guard let webEditorContext = getCurrentWebEditorContext() else {
            print("无法获取 WebEditorContext")
            return
        }
        
        let formatMenuView = WebFormatMenuView(context: webEditorContext) { [weak self] _ in
            self?.formatMenuPopover?.performClose(nil)
            self?.formatMenuPopover = nil
        }
        hostingController = NSHostingController(rootView: formatMenuView)
    }
    
    // 创建并显示 popover
    // ...
}
```

#### 1.2 添加 NativeEditorContext 访问

**文件**：`Sources/ViewModel/NotesViewModel.swift`

确保 `NotesViewModel` 提供 `nativeEditorContext` 属性供工具栏访问。

### 2. 斜体字体修复

#### 2.1 改进 NSFont.italic() 扩展

**文件**：`Sources/Service/XiaoMiFormatConverter.swift`

```swift
extension NSFont {
    /// 获取斜体版本（带降级处理）
    func italic() -> NSFont {
        // 方法 1：尝试使用 fontDescriptor.withSymbolicTraits
        let fontDescriptor = self.fontDescriptor
        if let italicDescriptor = fontDescriptor.withSymbolicTraits(.italic) as NSFontDescriptor?,
           let italicFont = NSFont(descriptor: italicDescriptor, size: self.pointSize) {
            // 验证是否真的是斜体
            if italicFont.fontDescriptor.symbolicTraits.contains(.italic) {
                return italicFont
            }
        }
        
        // 方法 2：使用 NSFontManager 查找斜体
        let fontManager = NSFontManager.shared
        if let italicFont = fontManager.convert(self, toHaveTrait: .italicFontMask) as NSFont?,
           italicFont != self {
            return italicFont
        }
        
        // 方法 3：尝试使用已知的斜体字体族
        let italicFamilies = ["Helvetica Neue", "SF Pro Text", "Times New Roman", "Georgia"]
        for family in italicFamilies {
            if let font = NSFont(name: "\(family) Italic", size: self.pointSize) {
                return font
            }
        }
        
        // 方法 4：返回原字体（日志警告）
        print("⚠️ 无法获取字体 '\(self.fontName)' 的斜体版本")
        return self
    }
}
```

### 3. 列表附件渲染

#### 3.1 修改 processBulletElement 方法

**文件**：`Sources/Service/XiaoMiFormatConverter.swift`

```swift
/// 处理 <bullet> 元素并返回 NSAttributedString（使用附件）
private func processBulletElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
    let indent = Int(extractAttribute("indent", from: line) ?? "1") ?? 1
    let content = extractContentAfterElement(from: line, elementName: "bullet")
    
    // 创建项目符号附件
    let bulletAttachment = BulletAttachment(indent: indent)
    
    // 创建结果字符串
    let result = NSMutableAttributedString()
    
    // 添加附件
    result.append(NSAttributedString(attachment: bulletAttachment))
    
    // 添加内容（处理内联格式）
    let contentAttributedString = try processInlineFormats(content)
    result.append(contentAttributedString)
    
    // 设置段落样式
    let paragraphStyle = createNSParagraphStyle(indent: indent)
    result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
    
    return result
}
```

#### 3.2 修改 processOrderElement 方法

**文件**：`Sources/Service/XiaoMiFormatConverter.swift`

```swift
/// 处理 <order> 元素并返回 NSAttributedString（使用附件）
private func processOrderElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
    let indent = Int(extractAttribute("indent", from: line) ?? "1") ?? 1
    let inputNumber = Int(extractAttribute("inputNumber", from: line) ?? "0") ?? 0
    let content = extractContentAfterElement(from: line, elementName: "order")
    
    // 计算显示编号
    let displayNumber: Int
    if inputNumber == 0 {
        displayNumber = currentOrderedListNumber
        currentOrderedListNumber += 1
    } else {
        displayNumber = inputNumber + 1
        currentOrderedListNumber = displayNumber + 1
    }
    
    // 创建有序列表附件
    let orderAttachment = OrderAttachment(number: displayNumber, inputNumber: inputNumber, indent: indent)
    
    // 创建结果字符串
    let result = NSMutableAttributedString()
    
    // 添加附件
    result.append(NSAttributedString(attachment: orderAttachment))
    
    // 添加内容（处理内联格式）
    let contentAttributedString = try processInlineFormats(content)
    result.append(contentAttributedString)
    
    // 设置段落样式
    let paragraphStyle = createNSParagraphStyle(indent: indent)
    result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
    
    return result
}
```

### 4. 列表格式检测

#### 4.1 更新 NativeEditorContext.detectListFormats

**文件**：`Sources/View/Bridge/NativeEditorContext.swift`

```swift
/// 检测当前位置的列表格式
func detectListFormats() -> ListFormatState {
    guard let textView = textView,
          let textStorage = textView.textStorage else {
        return ListFormatState()
    }
    
    let selectedRange = textView.selectedRange()
    guard selectedRange.location != NSNotFound else {
        return ListFormatState()
    }
    
    // 获取当前行的范围
    let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: selectedRange.location, length: 0))
    
    // 检查行首是否有列表附件
    var state = ListFormatState()
    
    textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, range, stop in
        if let _ = value as? BulletAttachment {
            state.isBulletList = true
            stop.pointee = true
        } else if let _ = value as? OrderAttachment {
            state.isOrderedList = true
            stop.pointee = true
        } else if let checkbox = value as? InteractiveCheckboxAttachment {
            state.isCheckboxList = true
            state.isChecked = checkbox.isChecked
            stop.pointee = true
        }
    }
    
    return state
}
```

### 5. 列表自动续行

#### 5.1 添加列表续行处理

**文件**：`Sources/View/NativeEditor/FormatManager.swift`

```swift
/// 处理 Enter 键按下时的列表续行
func handleEnterInList() -> Bool {
    guard let textView = textView,
          let textStorage = textView.textStorage else {
        return false
    }
    
    let selectedRange = textView.selectedRange()
    let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: selectedRange.location, length: 0))
    
    // 检测当前行的列表类型
    var listAttachment: NSTextAttachment?
    var attachmentRange: NSRange?
    
    textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, range, stop in
        if value is BulletAttachment || value is OrderAttachment || value is InteractiveCheckboxAttachment {
            listAttachment = value as? NSTextAttachment
            attachmentRange = range
            stop.pointee = true
        }
    }
    
    guard let attachment = listAttachment else {
        return false  // 不是列表项，不处理
    }
    
    // 检查是否是空列表项（只有附件，没有内容）
    let contentStart = (attachmentRange?.upperBound ?? lineRange.location)
    let contentRange = NSRange(location: contentStart, length: lineRange.upperBound - contentStart - 1)
    let content = (textStorage.string as NSString).substring(with: contentRange).trimmingCharacters(in: .whitespaces)
    
    if content.isEmpty {
        // 空列表项，移除列表格式
        removeListFormat(at: lineRange)
        return true
    }
    
    // 创建新的列表项
    insertNewListItem(after: selectedRange.location, basedOn: attachment)
    return true
}
```

## 文件修改清单

| 文件 | 修改内容 |
|------|----------|
| `Sources/Window/MainWindowController.swift` | 修改 `showFormatMenu` 方法，支持原生编辑器 |
| `Sources/Service/XiaoMiFormatConverter.swift` | 改进斜体字体获取，修改列表处理使用附件 |
| `Sources/View/Bridge/NativeEditorContext.swift` | 更新列表格式检测方法 |
| `Sources/View/NativeEditor/FormatManager.swift` | 添加列表自动续行处理 |
| `Sources/ViewModel/NotesViewModel.swift` | 确保提供 `nativeEditorContext` 访问 |

## 测试计划

1. **工具栏集成测试**
   - 验证原生编辑器模式下格式菜单显示正确
   - 验证 Web 编辑器模式下格式菜单显示正确
   - 验证编辑器切换后工具栏行为正确

2. **斜体渲染测试**
   - 验证各种字体的斜体渲染
   - 验证斜体与其他格式的组合
   - 验证降级处理正常工作

3. **列表渲染测试**
   - 验证无序列表使用 BulletAttachment 渲染
   - 验证有序列表使用 OrderAttachment 渲染
   - 验证列表格式检测正确

4. **列表续行测试**
   - 验证在列表项末尾按 Enter 创建新列表项
   - 验证在空列表项按 Enter 结束列表
   - 验证有序列表编号自动递增
