# Requirements Document

## Introduction

本文档定义了原生编辑器有序列表和无序列表功能的优化需求。目标是实现完整的列表创建、切换、转换、继承和取消功能，确保与小米笔记 XML 格式兼容，并保证列表与标题格式的互斥性。

## Glossary

- **Native_Editor**: 原生富文本编辑器，基于 NSTextView 实现
- **Format_Manager**: 格式管理器，负责处理富文本格式的应用和检测
- **List_Handler**: 列表处理器，负责列表格式的应用、切换和继承
- **Bullet_List**: 无序列表，使用项目符号（•）标记
- **Ordered_List**: 有序列表，使用数字编号（1. 2. 3.）标记
- **List_Attachment**: 列表附件，用于渲染列表符号的 NSTextAttachment 子类
- **Heading**: 标题格式，包括大标题（23pt）、二级标题（20pt）、三级标题（17pt）
- **Body_Text**: 正文格式，使用默认字体大小（14pt）
- **XML_Converter**: XML 转换器，负责 AttributedString 与小米笔记 XML 格式之间的转换

## Requirements

### Requirement 1: 空行创建列表

**User Story:** 作为用户，我希望在空行上点击列表格式时能创建新列表，以便快速开始列表输入。

#### Acceptance Criteria

1. WHEN 光标位于空行且用户点击无序列表格式 THEN List_Handler SHALL 在当前行创建无序列表并显示项目符号附件
2. WHEN 光标位于空行且用户点击有序列表格式 THEN List_Handler SHALL 在当前行创建有序列表并显示编号附件（从 1 开始）
3. WHEN 列表创建完成 THEN Native_Editor SHALL 将光标定位到列表符号后的输入位置

### Requirement 2: 有内容行转换为列表

**User Story:** 作为用户，我希望将已有文本内容的行转换为列表，以便快速组织现有内容。

#### Acceptance Criteria

1. WHEN 光标位于有文本内容的行且用户点击无序列表格式 THEN List_Handler SHALL 在行首插入项目符号附件并保留原有文本内容
2. WHEN 光标位于有文本内容的行且用户点击有序列表格式 THEN List_Handler SHALL 在行首插入编号附件并保留原有文本内容
3. WHEN 行转换为列表 THEN Format_Manager SHALL 为整行设置列表类型属性（listType）

### Requirement 3: 列表切换（取消）

**User Story:** 作为用户，我希望再次点击相同列表类型时能取消列表格式，以便恢复为普通文本。

#### Acceptance Criteria

1. WHEN 光标位于无序列表行且用户点击无序列表格式 THEN List_Handler SHALL 移除列表格式并删除项目符号附件
2. WHEN 光标位于有序列表行且用户点击有序列表格式 THEN List_Handler SHALL 移除列表格式并删除编号附件
3. WHEN 列表格式被移除 THEN Native_Editor SHALL 保留原有文本内容并恢复为正文格式

### Requirement 4: 列表类型转换

**User Story:** 作为用户，我希望能在有序列表和无序列表之间切换，以便灵活调整列表样式。

#### Acceptance Criteria

1. WHEN 光标位于无序列表行且用户点击有序列表格式 THEN List_Handler SHALL 将无序列表转换为有序列表
2. WHEN 光标位于有序列表行且用户点击无序列表格式 THEN List_Handler SHALL 将有序列表转换为无序列表
3. WHEN 列表类型转换 THEN List_Handler SHALL 替换列表附件并更新列表类型属性

### Requirement 5: 列表与标题互斥

**User Story:** 作为用户，我希望列表和标题格式互斥，以便保持文档格式的一致性。

#### Acceptance Criteria

1. WHEN 光标位于标题行且用户应用列表格式 THEN Format_Manager SHALL 先移除标题格式再应用列表格式
2. WHEN 光标位于列表行且用户应用标题格式 THEN Format_Manager SHALL 先移除列表格式再应用标题格式
3. THE List_Handler SHALL 确保列表行始终使用正文字体大小（14pt）

### Requirement 6: 列表附件渲染

**User Story:** 作为用户，我希望列表符号作为整体渲染，以便获得正确的视觉效果和编辑体验。

#### Acceptance Criteria

1. THE Native_Editor SHALL 使用 BulletAttachment 渲染无序列表的项目符号
2. THE Native_Editor SHALL 使用 OrderAttachment 渲染有序列表的编号（数字和点号作为整体）
3. WHEN 用户删除列表符号 THEN Native_Editor SHALL 删除整个附件而非单个字符

### Requirement 7: 列表中回车继承

**User Story:** 作为用户，我希望在列表项中按回车时新行自动继承列表格式，以便连续输入列表内容。

#### Acceptance Criteria

1. WHEN 用户在有内容的无序列表行按下回车 THEN List_Handler SHALL 在新行创建无序列表并继承缩进级别
2. WHEN 用户在有内容的有序列表行按下回车 THEN List_Handler SHALL 在新行创建有序列表并自动递增编号
3. WHEN 新列表行创建 THEN Native_Editor SHALL 清除内联格式（加粗、斜体等）但保留列表格式

### Requirement 8: 空列表回车取消

**User Story:** 作为用户，我希望在空列表项中按回车时取消列表格式，以便结束列表输入。

#### Acceptance Criteria

1. WHEN 用户在空的无序列表行按下回车 THEN List_Handler SHALL 取消列表格式而非换行
2. WHEN 用户在空的有序列表行按下回车 THEN List_Handler SHALL 取消列表格式而非换行
3. WHEN 空列表行取消格式 THEN Native_Editor SHALL 将当前行恢复为普通正文格式

### Requirement 9: XML 格式兼容（加载）

**User Story:** 作为用户，我希望列表能正确加载，以便查看和编辑云端同步的笔记。

#### Acceptance Criteria

1. WHEN 加载无序列表 XML `<bullet indent="N" />内容\n` THEN XML_Converter SHALL 创建 BulletAttachment 并设置正确的缩进级别
2. WHEN 加载有序列表 XML `<order indent="N" inputNumber="M" />内容\n` THEN XML_Converter SHALL 创建 OrderAttachment 并计算正确的显示编号
3. WHEN 加载连续有序列表 THEN XML_Converter SHALL 根据 inputNumber 规则自动递增编号（inputNumber=0 表示继续编号）
4. WHEN 加载列表 THEN XML_Converter SHALL 为列表行设置 listType 和 listIndent 属性

### Requirement 10: XML 格式兼容（保存）

**User Story:** 作为用户，我希望列表能正确保存为小米笔记 XML 格式，以便与云端同步。

#### Acceptance Criteria

1. WHEN 保存无序列表 THEN XML_Converter SHALL 检测 BulletAttachment 并生成 `<bullet indent="N" />内容\n` 格式
2. WHEN 保存有序列表 THEN XML_Converter SHALL 检测 OrderAttachment 并生成 `<order indent="N" inputNumber="M" />内容\n` 格式
3. WHEN 保存连续有序列表 THEN XML_Converter SHALL 遵循 inputNumber 规则：第一项为实际值减 1，后续项为 0
4. WHEN 保存列表 THEN XML_Converter SHALL 不使用 `<text>` 标签包裹列表内容
5. FOR ALL 列表内容 THE XML_Converter SHALL 正确转换内联格式（加粗、斜体等）为对应的 XML 标签

### Requirement 11: 菜单状态同步

**User Story:** 作为用户，我希望格式菜单能正确显示当前列表状态，以便了解当前格式。

#### Acceptance Criteria

1. WHEN 光标位于无序列表行 THEN Format_Menu SHALL 显示无序列表选项为选中状态
2. WHEN 光标位于有序列表行 THEN Format_Menu SHALL 显示有序列表选项为选中状态
3. WHEN 光标移动到不同格式的行 THEN Format_Menu SHALL 立即更新选中状态
