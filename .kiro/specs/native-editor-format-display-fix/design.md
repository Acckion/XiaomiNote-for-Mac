# 设计文档

## 概述

本设计文档描述了修复原生编辑器在切换笔记时格式不显示问题的解决方案。问题的根本原因是 SwiftUI 的 `NSViewRepresentable` 机制无法可靠地检测 `NSAttributedString` 的属性变化，导致当笔记切换时，即使内容已经更新到 `NativeEditorContext.nsAttributedText`，`NativeEditorView` 的 `updateNSView` 方法可能不会被触发或不会正确更新 `NSTextView` 的内容。

## 架构

### 当前架构问题

```
┌─────────────────────────────────────────────────────────────────┐
│                    笔记切换流程（当前）                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 用户点击笔记列表                                              │
│         │                                                       │
│         ▼                                                       │
│  2. NoteDetailView.handleSelectedNoteChange()                   │
│         │                                                       │
│         ▼                                                       │
│  3. quickSwitchToNote() → loadNoteContentFromCache()            │
│         │                                                       │
│         ▼                                                       │
│  4. UnifiedEditorWrapper.handleXMLContentChange()               │
│         │                                                       │
│         ▼                                                       │
│  5. NativeEditorContext.loadFromXML()                           │
│         │                                                       │
│         ▼                                                       │
│  6. nsAttributedText = mutableAttributed  ← 内容已更新           │
│         │                                                       │
│         ▼                                                       │
│  7. SwiftUI 检测 @Published 变化                                 │
│         │                                                       │
│         ▼                                                       │
│  8. NativeEditorView.updateNSView()  ← 可能不触发或比较失败       │
│         │                                                       │
│         ▼                                                       │
│  9. textStorage.setAttributedString()  ← 可能不执行              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 问题分析

1. **SwiftUI 的 @Published 机制限制**：`NSAttributedString` 是引用类型，SwiftUI 可能无法正确检测其内容变化
2. **updateNSView 比较逻辑不完整**：只比较字符串内容和长度，不比较格式属性
3. **缺少强制刷新机制**：没有在笔记切换时强制刷新 `NSTextView` 的显示

### 解决方案架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    笔记切换流程（修复后）                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 用户点击笔记列表                                              │
│         │                                                       │
│         ▼                                                       │
│  2. NoteDetailView.handleSelectedNoteChange()                   │
│         │                                                       │
│         ▼                                                       │
│  3. quickSwitchToNote() → loadNoteContentFromCache()            │
│         │                                                       │
│         ▼                                                       │
│  4. UnifiedEditorWrapper.handleXMLContentChange()               │
│         │                                                       │
│         ▼                                                       │
│  5. NativeEditorContext.loadFromXML()                           │
│         │                                                       │
│         ├──────────────────────────────────────┐                │
│         ▼                                      ▼                │
│  6. nsAttributedText = mutableAttributed   contentVersion += 1  │
│         │                                      │                │
│         ▼                                      ▼                │
│  7. contentChangeSubject.send()  ← 新增：发送内容变化通知         │
│         │                                                       │
│         ▼                                                       │
│  8. Coordinator.handleExternalContentUpdate()  ← 直接更新        │
│         │                                                       │
│         ▼                                                       │
│  9. textStorage.setAttributedString()  ← 强制执行                │
│         │                                                       │
│         ▼                                                       │
│  10. textView.needsDisplay = true  ← 强制刷新显示                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 组件和接口

### 1. NativeEditorContext 修改

```swift
/// 原生编辑器上下文
@MainActor
public class NativeEditorContext: ObservableObject {
    // 新增：内容版本号，用于强制触发视图更新
    @Published var contentVersion: Int = 0
    
    /// 从 XML 加载内容
    func loadFromXML(_ xml: String) {
        // ... 现有转换逻辑 ...
        
        // 更新内容
        nsAttributedText = mutableAttributed
        
        // 新增：递增版本号，强制触发视图更新
        contentVersion += 1
        
        // 新增：发送内容变化通知，确保 Coordinator 收到更新
        contentChangeSubject.send(mutableAttributed)
        
        hasUnsavedChanges = false
    }
}
```

### 2. NativeEditorView 修改

```swift
struct NativeEditorView: NSViewRepresentable {
    @ObservedObject var editorContext: NativeEditorContext
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        
        // 更新可编辑状态
        textView.isEditable = isEditable
        textView.textColor = .labelColor
        
        // 检查内容是否需要更新
        if !context.coordinator.isUpdatingFromTextView {
            let currentText = textView.attributedString()
            let newText = editorContext.nsAttributedText
            
            // 修改：增加版本号比较，确保内容变化时强制更新
            let versionChanged = context.coordinator.lastContentVersion != editorContext.contentVersion
            let contentChanged = currentText.string != newText.string
            let lengthChanged = currentText.length != newText.length
            
            if versionChanged || contentChanged || lengthChanged {
                // 更新版本号
                context.coordinator.lastContentVersion = editorContext.contentVersion
                
                // 保存当前选择范围
                let selectedRange = textView.selectedRange()
                
                // 更新内容
                textView.textStorage?.setAttributedString(newText)
                
                // 新增：强制刷新显示
                textView.needsDisplay = true
                
                // 恢复选择范围
                // ...
            }
        }
    }
}
```

### 3. Coordinator 修改

```swift
class Coordinator: NSObject, NSTextViewDelegate {
    // 新增：记录上次的内容版本号
    var lastContentVersion: Int = 0
    
    /// 处理外部内容更新
    private func handleExternalContentUpdate(_ newContent: NSAttributedString) {
        guard let textView = textView else { return }
        guard let textStorage = textView.textStorage else { return }
        guard !isUpdatingFromTextView else { return }
        
        // 修改：移除内容比较，直接更新
        // 因为 loadFromXML 已经确保只在内容真正变化时才发送通知
        
        // 保存当前选择范围
        let selectedRange = textView.selectedRange()
        
        // 标记正在更新
        isUpdatingFromTextView = true
        
        // 更新内容
        textStorage.setAttributedString(newContent)
        
        // 新增：强制刷新显示
        textView.needsDisplay = true
        
        // 恢复选择范围
        // ...
        
        isUpdatingFromTextView = false
    }
}
```

## 数据模型

无需修改数据模型。

## 正确性属性

*正确性属性是系统在所有有效执行中应该保持的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 笔记切换后格式正确显示

*For any* 笔记切换操作，当用户从笔记 A 切换到笔记 B 时，编辑器显示的内容应该包含笔记 B 的所有格式属性（加粗、斜体、下划线、标题等），且不需要用户交互即可显示。

**Validates: Requirements 1.1, 1.3, 3.3**

### Property 2: 格式转换 round-trip

*For any* 有效的 XML 内容，转换为 NSAttributedString 后再转换回 XML，应该产生等效的格式信息。

**Validates: Requirements 2.1, 2.2, 2.3**

### Property 3: 内容变化检测

*For any* 两个不同的 NSAttributedString（即使字符串内容相同但格式不同），NativeEditorView 应该检测到变化并更新 TextStorage。

**Validates: Requirements 3.1, 3.2**

### Property 4: 格式渲染性能

*For any* 笔记切换操作，格式渲染应该在 100ms 内完成（对于普通笔记）或 500ms 内完成（对于超过 10000 字符的大型笔记）。

**Validates: Requirements 1.2, 4.1, 4.2**

## 错误处理

1. **XML 转换失败**：如果 XML 转换失败，清空编辑器内容并记录错误日志
2. **TextStorage 更新失败**：如果 TextStorage 为 nil，记录错误日志并跳过更新
3. **性能超时**：如果格式渲染超过阈值，记录警告日志但不中断操作

## 测试策略

### 单元测试

1. 测试 `loadFromXML` 方法正确更新 `nsAttributedText` 和 `contentVersion`
2. 测试 `contentChangeSubject` 在内容变化时发送通知
3. 测试 `handleExternalContentUpdate` 正确更新 `textStorage`

### 属性测试

1. **Property 1 测试**：生成随机的笔记内容（带有各种格式），模拟笔记切换，验证格式是否正确显示
2. **Property 2 测试**：生成随机的 XML 内容，进行 round-trip 转换，验证格式信息是否保留
3. **Property 3 测试**：生成两个字符串内容相同但格式不同的 NSAttributedString，验证视图是否正确更新
4. **Property 4 测试**：生成不同大小的笔记内容，测量格式渲染时间

### 集成测试

1. 测试完整的笔记切换流程，验证格式显示正确
2. 测试在不同编辑器状态下（有焦点/无焦点）的格式显示
3. 测试大型笔记的格式渲染性能
