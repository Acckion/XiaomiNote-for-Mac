# Requirements Document

## Introduction

本文档定义了原生编辑器列表行为优化的需求。目标是修复现有列表功能中不符合主流编辑器操作习惯的问题，包括光标位置限制、回车键行为优化、以及文本分割逻辑。参考了 Apple Notes、Google Docs、Notion 等主流编辑器的列表行为规范。

## Glossary

- **Native_Editor**: 原生富文本编辑器，基于 NSTextView 实现
- **List_Item**: 列表项，包含列表符号（序号、项目符号或勾选框）和文本内容
- **List_Marker**: 列表标记，指列表项开头的序号（如 "1."）、项目符号（如 "•"）或勾选框（☐/☑）
- **Bullet_List**: 无序列表，使用项目符号（•）标记
- **Ordered_List**: 有序列表，使用数字编号（1. 2. 3.）标记
- **Checkbox_List**: 勾选框列表，使用勾选框（☐/☑）标记，支持勾选和取消勾选
- **Cursor**: 光标/插入点，用户输入文本的位置
- **Content_Area**: 内容区域，列表标记之后的可编辑文本区域
- **Empty_List_Item**: 空列表项，只有列表标记没有实际文本内容的列表项
- **Text_Split**: 文本分割，在光标位置将文本分成两部分的操作

## Requirements

### Requirement 1: 光标位置限制

**User Story:** 作为用户，我希望光标不能移动到列表序号/项目符号/勾选框的左边，以便获得与主流编辑器一致的操作体验。

#### Acceptance Criteria

1. WHEN 用户尝试将光标移动到列表标记（序号、项目符号或勾选框）左侧 THEN Native_Editor SHALL 将光标限制在列表标记右侧的内容区域起始位置
2. WHEN 用户使用左方向键从内容区域起始位置继续向左移动 THEN Native_Editor SHALL 将光标移动到上一行的末尾（如果存在上一行）
3. WHEN 用户使用鼠标点击列表标记区域（包括勾选框区域） THEN Native_Editor SHALL 将光标定位到内容区域起始位置
4. WHEN 用户使用 Home 键或 Cmd+左方向键 THEN Native_Editor SHALL 将光标定位到内容区域起始位置而非行首
5. WHEN 用户点击勾选框本身 THEN Native_Editor SHALL 切换勾选状态（☐ ↔ ☑）而非移动光标

### Requirement 2: 有内容列表项的回车行为

**User Story:** 作为用户，我希望在有内容的列表项（无序列表、有序列表或勾选框列表）中按下回车时能正确分割文本并创建新列表项，以便高效地编辑列表内容。

#### Acceptance Criteria

1. WHEN 用户在有内容的列表项中任意位置按下回车 THEN Native_Editor SHALL 在光标位置分割文本并创建新的列表项
2. WHEN 文本被分割 THEN Native_Editor SHALL 将光标前的文本保留在当前列表项中
3. WHEN 文本被分割 THEN Native_Editor SHALL 将光标后的文本移动到新创建的列表项中
4. WHEN 新列表项创建 THEN Native_Editor SHALL 继承当前列表项的列表类型（无序、有序或勾选框）和缩进级别
5. WHEN 新列表项创建且为有序列表 THEN Native_Editor SHALL 自动递增编号
6. WHEN 新列表项创建且为勾选框列表 THEN Native_Editor SHALL 创建未勾选状态（☐）的新勾选框
7. WHEN 光标在列表项末尾按下回车 THEN Native_Editor SHALL 创建空的新列表项（光标后无文本）
8. WHEN 光标在列表项开头（内容区域起始位置）按下回车 THEN Native_Editor SHALL 在当前项之前插入空列表项，当前内容保持不变

### Requirement 3: 空列表项的回车行为

**User Story:** 作为用户，我希望在空列表项（无序、有序或勾选框）中按下回车时能取消列表格式，以便快速结束列表输入。

#### Acceptance Criteria

1. WHEN 用户在空的列表项中按下回车 THEN Native_Editor SHALL 取消当前行的列表格式而非创建新列表项
2. WHEN 列表格式被取消 THEN Native_Editor SHALL 移除列表标记（序号、项目符号或勾选框）
3. WHEN 列表格式被取消 THEN Native_Editor SHALL 将当前行恢复为普通正文格式
4. WHEN 列表格式被取消 THEN Native_Editor SHALL 保持光标在当前行

### Requirement 4: 删除键行为优化

**User Story:** 作为用户，我希望在列表项（无序、有序或勾选框）内容区域起始位置按删除键时能正确合并列表项，以便高效地编辑列表。

#### Acceptance Criteria

1. WHEN 用户在列表项内容区域起始位置按下删除键（Backspace） THEN Native_Editor SHALL 将当前列表项的内容合并到上一行
2. WHEN 列表项合并 THEN Native_Editor SHALL 移除当前行的列表标记（序号、项目符号或勾选框）
3. WHEN 上一行也是列表项 THEN Native_Editor SHALL 将当前内容追加到上一行列表项的末尾
4. WHEN 上一行是普通文本 THEN Native_Editor SHALL 将当前内容追加到上一行末尾并取消列表格式

### Requirement 5: 选择行为优化

**User Story:** 作为用户，我希望选择操作不会选中列表标记（序号、项目符号或勾选框），以便获得一致的编辑体验。

#### Acceptance Criteria

1. WHEN 用户使用 Shift+左方向键从内容区域起始位置向左选择 THEN Native_Editor SHALL 扩展选择到上一行而非选中列表标记
2. WHEN 用户使用 Cmd+Shift+左方向键选择到行首 THEN Native_Editor SHALL 选择到内容区域起始位置而非列表标记
3. WHEN 用户双击列表项中的单词 THEN Native_Editor SHALL 只选中该单词而非包含列表标记
4. WHEN 用户三击选择整行 THEN Native_Editor SHALL 选择整个列表项内容但不包含列表标记（包括勾选框）

### Requirement 6: 有序列表编号更新

**User Story:** 作为用户，我希望有序列表的编号能在列表项增删时自动更新，以便保持编号的连续性。

#### Acceptance Criteria

1. WHEN 新的有序列表项被插入 THEN Native_Editor SHALL 更新后续所有列表项的编号
2. WHEN 有序列表项被删除 THEN Native_Editor SHALL 更新后续所有列表项的编号
3. WHEN 有序列表项被移动 THEN Native_Editor SHALL 更新所有受影响列表项的编号
4. THE Native_Editor SHALL 确保同一连续有序列表中的编号始终从 1 开始递增

### Requirement 7: 勾选框状态切换

**User Story:** 作为用户，我希望能够通过点击勾选框来切换其勾选状态，以便快速标记任务完成状态。

#### Acceptance Criteria

1. WHEN 用户点击未勾选的勾选框（☐） THEN Native_Editor SHALL 将其切换为已勾选状态（☑）
2. WHEN 用户点击已勾选的勾选框（☑） THEN Native_Editor SHALL 将其切换为未勾选状态（☐）
3. WHEN 勾选状态切换 THEN Native_Editor SHALL 保持光标位置不变
4. WHEN 勾选状态切换 THEN Native_Editor SHALL 保持列表项内容不变
5. THE Native_Editor SHALL 支持通过快捷键（如 Cmd+Shift+U）切换当前行勾选框状态

