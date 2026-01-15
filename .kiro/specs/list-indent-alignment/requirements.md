# 需求文档

## 简介

优化有序列表和无序列表的显示效果，解决列表序号/项目符号左边间距过大、与其他文本没有对齐的问题。当前列表标记（序号如"1."或项目符号"•"）作为一个整体附件渲染，其左边留出的间距过大，导致列表内容与普通正文的左边缘不对齐。

## 术语表

- **List_Attachment**: 列表附件，包括 BulletAttachment（无序列表项目符号）和 OrderAttachment（有序列表编号）
- **List_Marker**: 列表标记，指项目符号（•）或编号（1.、2.）
- **Content_Area**: 内容区域，列表标记之后的文本区域
- **First_Line_Head_Indent**: 首行缩进，段落第一行的左边距
- **Head_Indent**: 悬挂缩进，段落后续行的左边距
- **Native_Editor**: 原生编辑器，基于 NSTextView 的富文本编辑器

## 需求

### 需求 1：列表标记左对齐

**用户故事：** 作为用户，我希望列表的项目符号或编号与普通正文的左边缘对齐，以便获得整洁一致的视觉效果。

#### 验收标准

1. WHEN 应用无序列表格式 THEN Native_Editor SHALL 将项目符号的左边缘与普通正文的左边缘对齐
2. WHEN 应用有序列表格式 THEN Native_Editor SHALL 将编号的左边缘与普通正文的左边缘对齐
3. WHEN 应用复选框列表格式 THEN Native_Editor SHALL 将复选框的左边缘与普通正文的左边缘对齐
4. THE List_Attachment SHALL 使用最小必要的左边距（0 或接近 0）

### 需求 2：列表内容区域对齐

**用户故事：** 作为用户，我希望列表内容文本在多行时能够正确对齐，以便阅读体验更好。

#### 验收标准

1. WHEN 列表项内容换行 THEN Native_Editor SHALL 将后续行与第一行内容对齐（悬挂缩进）
2. THE Head_Indent SHALL 等于 List_Marker 宽度加上适当的间距
3. WHEN 列表项只有一行 THEN Native_Editor SHALL 正确显示标记和内容的间距

### 需求 3：缩进级别支持

**用户故事：** 作为用户，我希望嵌套列表能够正确显示缩进层级，以便清晰展示层次结构。

#### 验收标准

1. WHEN 列表缩进级别为 1 THEN Native_Editor SHALL 将标记左边缘与正文左边缘对齐
2. WHEN 列表缩进级别大于 1 THEN Native_Editor SHALL 按照缩进单位递增左边距
3. THE 缩进单位 SHALL 保持一致（当前为 20pt）

### 需求 4：附件尺寸优化

**用户故事：** 作为用户，我希望列表标记的尺寸合适，不会占用过多空间。

#### 验收标准

1. THE BulletAttachment 宽度 SHALL 足够容纳项目符号但不过大
2. THE OrderAttachment 宽度 SHALL 足够容纳最大编号（如 "99."）但不过大
3. THE List_Attachment SHALL 在垂直方向上与文本基线对齐

### 需求 5：视觉一致性

**用户故事：** 作为用户，我希望列表在不同主题下都能保持良好的视觉效果。

#### 验收标准

1. WHEN 切换深色/浅色主题 THEN Native_Editor SHALL 保持列表对齐效果不变
2. THE List_Marker 颜色 SHALL 与文本颜色协调
3. THE 列表间距 SHALL 与正文段落间距保持一致
