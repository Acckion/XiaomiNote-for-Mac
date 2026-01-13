# 需求文档

## 简介

统一格式管理器（UnifiedFormatManager）用于整合原生编辑器中所有格式处理逻辑，确保加粗、斜体、下划线、删除线、高亮等内联格式以及标题、列表、引用等块级格式使用完全统一的处理流程。

## 术语表

- **Unified_Format_Manager**: 统一格式管理器，负责协调所有格式的应用、检测和换行继承
- **Inline_Format**: 内联格式，包括加粗、斜体、下划线、删除线、高亮，作用于字符级别
- **Block_Format**: 块级格式，包括标题、列表、引用等，作用于整行
- **Typing_Attributes**: NSTextView 的输入属性，决定新输入文字的格式
- **Format_State**: 当前光标位置或选中文字的格式状态
- **Newline_Inheritance**: 换行继承规则，决定新行是否继承当前行的格式

## 需求

### 需求 1：内联格式统一处理

**用户故事：** 作为用户，我希望加粗、斜体、下划线、删除线、高亮这五个格式使用完全相同的处理逻辑，以确保行为一致。

#### 验收标准

1. WHEN 用户应用任意内联格式 THEN Unified_Format_Manager SHALL 使用统一的 `applyInlineFormat` 方法处理
2. WHEN 用户切换内联格式状态 THEN Unified_Format_Manager SHALL 同步更新 Typing_Attributes
3. WHEN 光标位置变化 THEN Unified_Format_Manager SHALL 检测并更新所有内联格式的状态
4. THE Unified_Format_Manager SHALL 支持多个内联格式同时应用（如加粗+斜体+下划线）
5. WHEN 斜体格式应用于不支持斜体的字体 THEN Unified_Format_Manager SHALL 使用 obliqueness 属性作为后备方案

### 需求 2：内联格式换行不继承

**用户故事：** 作为用户，我希望换行后新行不继承加粗、斜体、下划线、删除线、高亮格式，以便快速输入普通文本。

#### 验收标准

1. WHEN 用户在加粗文本后按回车 THEN 新行 SHALL 不继承加粗格式
2. WHEN 用户在斜体文本后按回车 THEN 新行 SHALL 不继承斜体格式
3. WHEN 用户在下划线文本后按回车 THEN 新行 SHALL 不继承下划线格式
4. WHEN 用户在删除线文本后按回车 THEN 新行 SHALL 不继承删除线格式
5. WHEN 用户在高亮文本后按回车 THEN 新行 SHALL 不继承高亮格式
6. WHEN 用户在同时具有多个内联格式的文本后按回车 THEN 新行 SHALL 清除所有内联格式

### 需求 3：块级格式整行属性

**用户故事：** 作为用户，我希望标题、列表等块级格式作用于整行，不能在同一行内混合使用。

#### 验收标准

1. THE 大标题格式 SHALL 作用于整行，不能与其他块级格式混合
2. THE 二级标题格式 SHALL 作用于整行，不能与其他块级格式混合
3. THE 三级标题格式 SHALL 作用于整行，不能与其他块级格式混合
4. THE 有序列表格式 SHALL 作用于整行，不能与其他块级格式混合
5. THE 无序列表格式 SHALL 作用于整行，不能与其他块级格式混合
6. THE Checkbox 格式 SHALL 作用于整行，不能与其他块级格式混合
7. WHEN 用户在标题行应用列表格式 THEN Unified_Format_Manager SHALL 先移除标题格式再应用列表格式

### 需求 4：标题格式换行不继承

**用户故事：** 作为用户，我希望在标题行按回车后，新行变为普通正文。

#### 验收标准

1. WHEN 用户在大标题行末尾按回车 THEN 新行 SHALL 变为普通正文格式
2. WHEN 用户在二级标题行末尾按回车 THEN 新行 SHALL 变为普通正文格式
3. WHEN 用户在三级标题行末尾按回车 THEN 新行 SHALL 变为普通正文格式
4. WHEN 用户在标题行中间按回车 THEN 新行 SHALL 变为普通正文格式

### 需求 5：列表和 Checkbox 格式换行继承

**用户故事：** 作为用户，我希望在列表项按回车后，新行继承列表格式，方便连续输入列表项。

#### 验收标准

1. WHEN 用户在有序列表项末尾按回车且当前项有内容 THEN 新行 SHALL 继承有序列表格式且序号递增
2. WHEN 用户在无序列表项末尾按回车且当前项有内容 THEN 新行 SHALL 继承无序列表格式
3. WHEN 用户在 Checkbox 项末尾按回车且当前项有内容 THEN 新行 SHALL 继承 Checkbox 格式
4. WHEN 用户在空的有序列表项按回车 THEN 当前行 SHALL 变为普通正文（不换行）
5. WHEN 用户在空的无序列表项按回车 THEN 当前行 SHALL 变为普通正文（不换行）
6. WHEN 用户在空的 Checkbox 项按回车 THEN 当前行 SHALL 变为普通正文（不换行）

### 需求 6：引用格式换行继承

**用户故事：** 作为用户，我希望在引用块按回车后，新行继承引用格式。

#### 验收标准

1. WHEN 用户在引用块行末尾按回车 THEN 新行 SHALL 继承引用格式
2. WHEN 用户在引用块行中间按回车 THEN 新行 SHALL 继承引用格式

### 需求 7：对齐属性换行继承

**用户故事：** 作为用户，我希望换行后新行继承当前行的对齐方式。

#### 验收标准

1. WHEN 用户在居中对齐的行按回车 THEN 新行 SHALL 继承居中对齐
2. WHEN 用户在右对齐的行按回车 THEN 新行 SHALL 继承右对齐
3. WHEN 用户在左对齐的行按回车 THEN 新行 SHALL 保持左对齐（默认）

### 需求 8：统一的换行处理入口

**用户故事：** 作为开发者，我希望所有换行逻辑通过统一的入口处理，便于维护和扩展。

#### 验收标准

1. THE Unified_Format_Manager SHALL 提供统一的 `handleNewLine` 方法处理所有换行逻辑
2. WHEN 用户按回车键 THEN NativeTextView SHALL 调用 Unified_Format_Manager.handleNewLine
3. THE handleNewLine 方法 SHALL 根据当前行格式类型决定换行行为
4. THE handleNewLine 方法 SHALL 返回是否已处理换行（用于阻止默认行为）

### 需求 9：格式应用统一入口

**用户故事：** 作为开发者，我希望所有格式应用通过统一的入口处理，确保行为一致。

#### 验收标准

1. THE Unified_Format_Manager SHALL 提供统一的 `applyFormat` 方法处理所有格式应用
2. WHEN 用户通过工具栏应用格式 THEN Unified_Format_Manager.applyFormat SHALL 被调用
3. WHEN 用户通过菜单应用格式 THEN Unified_Format_Manager.applyFormat SHALL 被调用
4. WHEN 用户通过快捷键应用格式 THEN Unified_Format_Manager.applyFormat SHALL 被调用
5. THE applyFormat 方法 SHALL 自动区分内联格式和块级格式并使用对应的处理逻辑

### 需求 10：Typing_Attributes 统一同步

**用户故事：** 作为开发者，我希望 Typing_Attributes 的同步逻辑集中管理，避免分散在多处。

#### 验收标准

1. THE Unified_Format_Manager SHALL 提供统一的 `syncTypingAttributes` 方法
2. WHEN 光标位置变化 THEN Unified_Format_Manager SHALL 自动同步 Typing_Attributes
3. WHEN 格式应用完成 THEN Unified_Format_Manager SHALL 自动同步 Typing_Attributes
4. WHEN 换行完成 THEN Unified_Format_Manager SHALL 根据继承规则设置新行的 Typing_Attributes
