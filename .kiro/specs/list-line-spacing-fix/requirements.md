# 需求文档

## 简介

优化原生编辑器中列表样式（复选框、有序列表、无序列表）的行间距显示效果，使其与普通正文保持一致。当前列表项的行间距比普通正文窄，影响阅读体验和视觉一致性。

## 术语表

- **List_Paragraph_Style**: 列表段落样式，用于控制列表项的缩进、行间距等排版属性
- **Line_Spacing**: 行间距，段落内行与行之间的垂直间距
- **Paragraph_Spacing**: 段落间距，段落与段落之间的垂直间距
- **Native_Editor**: 原生编辑器，使用 NSTextView 实现的富文本编辑器
- **Body_Text**: 正文文本，普通段落的默认文本样式

## 需求

### 需求 1：列表行间距与正文一致

**用户故事：** 作为用户，我希望列表项的行间距与普通正文相同，以便获得一致的阅读体验。

#### 验收标准

1. WHEN 创建无序列表段落样式 THEN List_Paragraph_Style SHALL 设置 lineSpacing 为 4（与正文相同）
2. WHEN 创建有序列表段落样式 THEN List_Paragraph_Style SHALL 设置 lineSpacing 为 4（与正文相同）
3. WHEN 创建复选框列表段落样式 THEN List_Paragraph_Style SHALL 设置 lineSpacing 为 4（与正文相同）
4. WHEN 创建任意列表段落样式 THEN List_Paragraph_Style SHALL 设置 paragraphSpacing 为 8（与正文相同）

### 需求 2：统一段落样式常量

**用户故事：** 作为开发者，我希望行间距和段落间距使用统一的常量定义，以便于维护和修改。

#### 验收标准

1. THE Native_Editor SHALL 定义统一的 lineSpacing 常量值
2. THE Native_Editor SHALL 定义统一的 paragraphSpacing 常量值
3. WHEN 创建任意段落样式 THEN Native_Editor SHALL 使用统一的常量值

### 需求 3：保持现有缩进和制表位功能

**用户故事：** 作为用户，我希望修复行间距后，列表的缩进和制表位功能保持正常工作。

#### 验收标准

1. WHEN 修改列表段落样式后 THEN List_Paragraph_Style SHALL 保持原有的 firstLineHeadIndent 设置
2. WHEN 修改列表段落样式后 THEN List_Paragraph_Style SHALL 保持原有的 headIndent 设置
3. WHEN 修改列表段落样式后 THEN List_Paragraph_Style SHALL 保持原有的 tabStops 设置
