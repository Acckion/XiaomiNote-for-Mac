# 需求文档

## 简介

修复原生编辑器在切换笔记时格式不显示的问题。当用户点击笔记列表切换到另一个笔记时，编辑器显示的内容没有格式（如加粗、斜体、标题等），只有当用户将焦点移动到编辑器内容区域时，格式才会正确显示。

## 术语表

- **Native_Editor**: 原生编辑器，基于 NSTextView 的富文本编辑器
- **NativeEditorContext**: 原生编辑器上下文，管理编辑器状态和内容
- **NativeEditorView**: 原生编辑器视图，NSViewRepresentable 包装的 NSTextView
- **NSAttributedString**: 带有格式属性的字符串
- **TextStorage**: NSTextView 的文本存储，管理富文本内容
- **Format_Attributes**: 格式属性，包括字体、颜色、段落样式等

## 需求

### 需求 1：笔记切换时立即显示格式

**用户故事：** 作为用户，我希望切换笔记后立即看到正确的格式显示，而不需要点击编辑器区域。

#### 验收标准

1. WHEN 用户点击笔记列表中的另一个笔记 THEN Native_Editor SHALL 立即显示该笔记的完整格式（包括加粗、斜体、下划线、标题等）
2. WHEN 笔记内容加载完成 THEN Native_Editor SHALL 在 100ms 内完成格式渲染
3. WHEN 笔记切换时 THEN Native_Editor SHALL 不需要用户交互即可显示正确格式

### 需求 2：格式属性正确传递

**用户故事：** 作为用户，我希望笔记的所有格式属性都能正确显示。

#### 验收标准

1. WHEN XML 内容被转换为 NSAttributedString THEN Format_Attributes SHALL 包含所有原始格式信息
2. WHEN NSAttributedString 被设置到 TextStorage THEN Format_Attributes SHALL 被完整保留
3. WHEN 编辑器视图更新 THEN TextStorage SHALL 立即反映新的格式属性

### 需求 3：视图更新机制优化

**用户故事：** 作为开发者，我希望视图更新机制能够可靠地检测内容和格式变化。

#### 验收标准

1. WHEN NativeEditorContext.nsAttributedText 变化 THEN NativeEditorView SHALL 检测到变化并更新 TextStorage
2. WHEN 内容字符串相同但格式不同 THEN NativeEditorView SHALL 仍然更新 TextStorage
3. WHEN 笔记切换导致内容变化 THEN NativeEditorView SHALL 强制刷新显示

### 需求 4：性能要求

**用户故事：** 作为用户，我希望笔记切换流畅，不会有明显的延迟。

#### 验收标准

1. WHEN 笔记切换时 THEN 格式渲染 SHALL 在 100ms 内完成
2. WHEN 大型笔记（超过 10000 字符）切换时 THEN 格式渲染 SHALL 在 500ms 内完成
3. WHEN 格式渲染进行时 THEN UI SHALL 保持响应
