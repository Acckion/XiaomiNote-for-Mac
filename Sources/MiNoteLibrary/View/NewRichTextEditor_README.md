# NewRichTextEditor - 全新富文本编辑器

## 概述

`NewRichTextEditor` 是一个全新的富文本编辑器实现，参考 RichTextKit Demo，提供完善的编辑功能。

## 主要特性

### 1. 完整的格式工具栏（macOS）
- 内置 `RichTextFormat.Toolbar`，提供丰富的格式选项
- 支持字体、字号、样式（加粗、斜体、下划线等）
- 支持文本对齐、缩进、行间距等高级格式

### 2. Inspector 侧边栏（格式面板）
- 内置 `RichTextFormat.Sidebar`，提供详细的格式控制
- 支持颜色选择器（前景色、背景色）
- 支持字体选择器（macOS）
- 可通过工具栏按钮切换显示/隐藏

### 3. 图片附件支持
- 使用 `archivedData` 格式，完美支持图片附件
- 支持粘贴图片（Cmd+V）
- 支持拖拽图片
- 自动调整图片大小（最大 600x800pt）

### 4. 撤销/重做支持
- 内置撤销/重做功能（Cmd+Z / Cmd+Shift+Z）
- 通过 NSTextView 的 UndoManager 自动管理

### 5. 与现有系统兼容
- 支持 RTF 数据（archivedData 格式）
- 支持 XML 内容转换（向后兼容）
- 与现有保存逻辑完全兼容

## 使用方法

### 基本用法

```swift
NewRichTextEditor(
    rtfData: $editedRTFData,
    isEditable: $isEditable,
    noteRawData: noteRawData,
    xmlContent: xmlContent,
    onContentChange: { newRTFData in
        // 处理内容变化
        guard !isInitializing, let rtfData = newRTFData else {
            return
        }
        
        // 检查内容是否真的变化了
        if let lastSaved = lastSavedRTFData, lastSaved == rtfData {
            editedRTFData = rtfData
            return
        }
        
        editedRTFData = rtfData
        
        // 触发保存
        onContentChange?(rtfData)
    }
)
```

### 在 NoteDetailView 中使用

替换现有的 `RichTextEditorWrapper`：

```swift
private var bodyEditorView: some View {
    NewRichTextEditor(
        rtfData: $editedRTFData,
        isEditable: $isEditable,
        noteRawData: viewModel.selectedNote?.rawData,
        xmlContent: viewModel.selectedNote?.primaryXMLContent,
        onContentChange: { newRTFData in
            // ... 保存逻辑
        }
    )
    .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
}
```

## 与现有编辑器的对比

### 优势

1. **更简洁的 API**：不需要手动管理 RichTextContext
2. **内置格式工具栏**：无需额外实现格式按钮
3. **内置 Inspector**：提供专业的格式面板
4. **更好的图片支持**：使用 archivedData 格式，完美支持图片附件
5. **与 Demo 一致**：功能完善，参考官方 Demo 实现

### 注意事项

1. **Context 管理**：新编辑器内部管理自己的 RichTextContext，不需要外部传入
2. **格式工具栏**：macOS 上自动显示在顶部，iOS 上使用键盘工具栏
3. **Inspector 侧边栏**：可通过工具栏按钮切换显示/隐藏

## 技术细节

### 数据格式

- **主要格式**：`archivedData`（支持图片附件）
- **兼容格式**：XML（向后兼容，自动转换）

### 图片处理

- 使用 `RichTextImageAttachment` 处理图片
- 支持 JPEG、PNG 等常见格式
- 自动压缩和调整大小

### 格式配置

- 颜色选择器：前景色、背景色
- 字体选择器：macOS 支持
- 格式工具栏：可配置显示哪些选项

## 参考

- RichTextKit Demo: `RichTextKit-1.2/Demo/Demo/DemoEditorScreen.swift`
- RichTextKit 文档: `RichTextKit-1.2/Sources/RichTextKit/RichTextKit.docc/`

