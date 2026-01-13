# 需求文档

## 简介

本文档定义了原生编辑器中光标位置格式状态同步功能的需求。该功能确保当光标放置在已有格式文字末尾时，工具栏能正确显示该位置的格式状态，并且新输入的文字能继承光标前一个字符的格式。

核心目标是建立一个统一的格式状态管理逻辑，集中处理格式检测、工具栏同步和输入格式继承。

## 术语表

- **Native_Editor**: 基于 NSTextView 的原生富文本编辑器组件
- **Format_State**: 当前光标或选择处的格式状态，包括加粗、斜体、下划线、删除线、高亮等
- **Toolbar**: 工具栏，显示当前格式状态并提供格式切换功能
- **Typing_Attributes**: NSTextView 的 typingAttributes 属性，决定新输入文字的格式
- **Cursor_Position**: 光标在文本中的位置
- **Character_Attributes**: 文本中某个字符的格式属性
- **Cursor_Format_Manager**: 统一的光标格式管理器，负责协调格式检测、工具栏同步和输入格式继承

## 需求

### 需求 1：光标模式下的格式状态检测

**用户故事：** 作为用户，我希望当光标放在已有格式文字末尾时，工具栏能正确显示该位置的格式状态，以便我知道继续输入时会使用什么格式。

#### 验收标准

1. WHEN 光标放置在加粗文字末尾且没有选中文字 THEN Toolbar SHALL 显示加粗按钮为激活状态
2. WHEN 光标放置在斜体文字末尾且没有选中文字 THEN Toolbar SHALL 显示斜体按钮为激活状态
3. WHEN 光标放置在下划线文字末尾且没有选中文字 THEN Toolbar SHALL 显示下划线按钮为激活状态
4. WHEN 光标放置在删除线文字末尾且没有选中文字 THEN Toolbar SHALL 显示删除线按钮为激活状态
5. WHEN 光标放置在高亮文字末尾且没有选中文字 THEN Toolbar SHALL 显示高亮按钮为激活状态
6. WHEN 光标放置在具有多种格式（如加粗+斜体）的文字末尾 THEN Toolbar SHALL 同时显示所有对应格式按钮为激活状态

### 需求 2：光标模式下的输入格式继承

**用户故事：** 作为用户，我希望当光标放在已有格式文字末尾时，继续输入的新文字能自动继承前一个字符的格式，以便我能连续输入相同格式的内容。

#### 验收标准

1. WHEN 光标放置在加粗文字末尾且用户输入新字符 THEN Native_Editor SHALL 将新字符应用加粗格式
2. WHEN 光标放置在斜体文字末尾且用户输入新字符 THEN Native_Editor SHALL 将新字符应用斜体格式
3. WHEN 光标放置在下划线文字末尾且用户输入新字符 THEN Native_Editor SHALL 将新字符应用下划线格式
4. WHEN 光标放置在删除线文字末尾且用户输入新字符 THEN Native_Editor SHALL 将新字符应用删除线格式
5. WHEN 光标放置在高亮文字末尾且用户输入新字符 THEN Native_Editor SHALL 将新字符应用高亮格式
6. WHEN 光标放置在具有多种格式的文字末尾且用户输入新字符 THEN Native_Editor SHALL 将新字符应用所有对应格式

### 需求 3：Typing Attributes 同步

**用户故事：** 作为开发者，我希望 NSTextView 的 typingAttributes 能与光标位置的格式状态保持同步，以确保新输入文字的格式正确。

#### 验收标准

1. WHEN 光标位置变化且没有选中文字 THEN Native_Editor SHALL 将 Typing_Attributes 更新为光标前一个字符的 Character_Attributes
2. WHEN 光标位于文档开头（位置为 0） THEN Native_Editor SHALL 使用默认的 Typing_Attributes
3. WHEN 光标位于空文档中 THEN Native_Editor SHALL 使用默认的 Typing_Attributes
4. WHEN 用户通过工具栏切换格式状态 THEN Native_Editor SHALL 更新 Typing_Attributes 以反映新的格式状态

### 需求 4：格式状态与工具栏的双向同步

**用户故事：** 作为用户，我希望工具栏的格式按钮状态与实际输入格式保持一致，以便我能准确了解当前的编辑状态。

#### 验收标准

1. WHEN 用户点击工具栏的加粗按钮 THEN Native_Editor SHALL 更新 Typing_Attributes 并在后续输入中应用加粗格式
2. WHEN 用户点击工具栏的斜体按钮 THEN Native_Editor SHALL 更新 Typing_Attributes 并在后续输入中应用斜体格式
3. WHEN 用户点击工具栏的下划线按钮 THEN Native_Editor SHALL 更新 Typing_Attributes 并在后续输入中应用下划线格式
4. WHEN 用户点击工具栏的删除线按钮 THEN Native_Editor SHALL 更新 Typing_Attributes 并在后续输入中应用删除线格式
5. WHEN 用户点击工具栏的高亮按钮 THEN Native_Editor SHALL 更新 Typing_Attributes 并在后续输入中应用高亮格式
6. WHEN Typing_Attributes 变化 THEN Toolbar SHALL 更新对应格式按钮的激活状态

### 需求 5：边界条件处理

**用户故事：** 作为用户，我希望在各种边界情况下编辑器都能正常工作，不会出现格式错乱或崩溃。

#### 验收标准

1. WHEN 光标位于文档开头（位置为 0）且前面没有字符 THEN Native_Editor SHALL 使用默认格式状态
2. WHEN 光标位于两种不同格式文字的交界处 THEN Native_Editor SHALL 使用光标前一个字符的格式
3. WHEN 光标位于普通文字和格式文字的交界处 THEN Native_Editor SHALL 使用光标前一个字符的格式
4. WHEN 文档内容为空 THEN Native_Editor SHALL 使用默认格式状态
5. IF 格式状态检测失败 THEN Native_Editor SHALL 使用默认格式状态并记录错误日志

### 需求 6：统一的格式状态管理

**用户故事：** 作为开发者，我希望有一个统一的管理器来协调格式检测、工具栏同步和输入格式继承，以便代码更易维护和扩展。

#### 验收标准

1. THE Cursor_Format_Manager SHALL 作为单一入口点处理所有光标位置相关的格式状态管理
2. WHEN 光标位置变化 THEN Cursor_Format_Manager SHALL 自动执行格式检测、工具栏更新和 Typing_Attributes 同步
3. WHEN 用户通过工具栏切换格式 THEN Cursor_Format_Manager SHALL 同步更新 Format_State 和 Typing_Attributes
4. THE Cursor_Format_Manager SHALL 提供统一的 API 供 NativeEditorContext 和 NativeEditorView 调用
5. THE Cursor_Format_Manager SHALL 支持防抖机制以避免频繁的状态更新影响性能
6. THE Cursor_Format_Manager SHALL 与现有的 FormatStateManager 集成，确保菜单栏格式状态同步
