# 需求文档

## 简介

清理项目中的旧版代码、多余代码和临时调试代码，提高代码质量和可维护性。

## 术语表

- **Code_Cleanup_System**: 代码清理系统，负责识别和删除项目中的冗余代码
- **References_Old**: References/Old 目录，包含完整的旧版项目副本
- **Debug_Code**: 调试代码，包括 print 语句和调试工具
- **TODO_Placeholder**: TODO 占位符，未实现的函数存根
- **Deprecated_API**: 已弃用的 API 调用
- **Duplicate_Toolbar**: 重复的工具栏代码，NoteDetailView 中已被 MainWindowToolbarDelegate 替代的工具栏
- **Unused_Coordinator**: 未使用的协调器类，NoteEditorCoordinator 未被任何代码使用
- **Placeholder_Editor**: 占位符编辑器类，EditorProtocol 中的 NativeEditor 和 WebEditor 占位符实现

## 需求

### 需求 1：删除旧版项目副本

**用户故事：** 作为开发者，我希望删除 References/Old 目录中的旧版项目副本，以减少磁盘空间占用和避免版本混淆。

#### 验收标准

1. THE Code_Cleanup_System SHALL 删除 References/Old 目录及其所有内容
2. WHEN 删除完成后 THEN Code_Cleanup_System SHALL 验证目录已被完全移除
3. THE Code_Cleanup_System SHALL 保留其他 References 目录（CotEditor、NetNewsWire 等参考项目）

### 需求 2：删除 NoteDetailView 中的重复工具栏代码

**用户故事：** 作为开发者，我希望删除 NoteDetailView 中已被 MainWindowToolbarDelegate 替代的工具栏代码，以避免代码重复和维护困难。

#### 验收标准

1. THE Code_Cleanup_System SHALL 删除 NoteDetailView.swift 中的 toolbarContent 属性及其相关代码
2. THE Code_Cleanup_System SHALL 删除 NoteDetailView.swift 中的所有工具栏按钮定义（undoButton、redoButton、formatMenu、checkboxButton、horizontalRuleButton、imageButton、indentButtons、debugModeToggleButton、newNoteButton、shareAndMoreButtons 等）
3. THE Code_Cleanup_System SHALL 删除 NoteDetailView.swift 中的 .toolbar 修饰符调用
4. THE Code_Cleanup_System SHALL 删除 NoteDetailView.swift 中的 FormatMenuPopoverContent 视图（如果已在其他地方实现）
5. THE Code_Cleanup_System SHALL 保留 MainWindowToolbarDelegate 中的工具栏实现作为唯一的工具栏管理方式
6. WHEN 删除完成后 THEN 应用程序 SHALL 仍能正常运行，工具栏功能由 MainWindowToolbarDelegate 提供

### 需求 3：删除未使用的 NoteEditorCoordinator 类

**用户故事：** 作为开发者，我希望删除未被任何代码使用的 NoteEditorCoordinator 类，以减少代码复杂度。

#### 验收标准

1. THE Code_Cleanup_System SHALL 验证 NoteEditorCoordinator 类未被任何代码使用（仅在自身文件中引用）
2. THE Code_Cleanup_System SHALL 删除 Sources/View/Bridge/NoteEditorCoordinator.swift 文件
3. THE Code_Cleanup_System SHALL 更新 project.yml 移除对该文件的引用（如果有）

### 需求 4：清理 EditorProtocol 中的占位符代码

**用户故事：** 作为开发者，我希望清理 EditorProtocol.swift 中未使用的 NativeEditor 和 WebEditor 占位符类，因为实际实现在 NativeEditorContext 和 WebEditorContext 中。

#### 验收标准

1. THE Code_Cleanup_System SHALL 删除 EditorProtocol.swift 中的 NativeEditor 类（占位符实现）
2. THE Code_Cleanup_System SHALL 删除 EditorProtocol.swift 中的 WebEditor 类（占位符实现）
3. THE Code_Cleanup_System SHALL 保留 EditorProtocol 协议定义、EditorFactory 类和相关枚举
4. THE Code_Cleanup_System SHALL 更新 EditorFactory.createEditorSafely 方法，使其返回实际的编辑器上下文或抛出错误

### 需求 5：清理 MainWindowController 中的未实现 TODO 方法

**用户故事：** 作为开发者，我希望清理 MainWindowController 中仅有 print 语句和 TODO 注释的空方法，以减少代码噪音。

#### 验收标准

1. THE Code_Cleanup_System SHALL 识别 MainWindowController.swift 中所有仅包含 print 和 TODO 的方法
2. IF 方法未被菜单或其他地方调用 THEN Code_Cleanup_System SHALL 删除该方法
3. IF 方法被菜单调用但未实现 THEN Code_Cleanup_System SHALL 在方法中添加"功能暂未实现"的用户提示
4. THE Code_Cleanup_System SHALL 清理以下方法：toggleBlockQuote、markAsChecked、checkAll、uncheckAll、moveCheckedToBottom、deleteCheckedItems、moveItemUp、moveItemDown、toggleLightBackground、toggleHighlight、expandSection、expandAllSections、collapseSection、collapseAllSections

### 需求 6：清理已弃用的 API

**用户故事：** 作为开发者，我希望清理已弃用的 API 调用，以保持代码现代化。

#### 验收标准

1. THE Code_Cleanup_System SHALL 检查 PrivateNotesPasswordManager.swift 中的 authenticateWithTouchIDWithDialog 方法
2. IF 该方法未被任何代码调用 THEN Code_Cleanup_System SHALL 删除该方法
3. IF 该方法仍在使用 THEN Code_Cleanup_System SHALL 将调用迁移到 authenticateWithTouchID 方法

### 需求 7：清理分析文档

**用户故事：** 作为开发者，我希望整理技术分析文档，将其移到适当的位置。

#### 验收标准

1. THE Code_Cleanup_System SHALL 将 Sources/Web/ckeditor-vs-current-analysis.md 移到项目根目录的 docs 目录
2. WHEN 移动完成后 THEN Code_Cleanup_System SHALL 更新任何引用该文件的代码或文档

### 需求 8：清理 NotesListViewController 中的未实现方法

**用户故事：** 作为开发者，我希望清理 NotesListViewController 中仅有 TODO 注释的空方法。

#### 验收标准

1. THE Code_Cleanup_System SHALL 检查 NotesListViewController.swift 中的 moveNote 方法
2. IF 该方法被右键菜单使用 THEN Code_Cleanup_System SHALL 实现该方法或添加用户提示
3. THE Code_Cleanup_System SHALL 确保右键菜单功能正常工作

### 需求 9：评估 WebEditorWrapper 使用情况

**用户故事：** 作为开发者，我希望评估 WebEditorWrapper 是否与 UnifiedEditorWrapper 功能重复，并进行适当清理。

#### 验收标准

1. THE Code_Cleanup_System SHALL 分析 WebEditorWrapper.swift 和 UnifiedEditorWrapper.swift 的功能
2. WHEN WebEditorWrapper 仅被 UnifiedEditorWrapper 和 NewNoteView 使用 THEN Code_Cleanup_System SHALL 保留当前结构
3. THE Code_Cleanup_System SHALL 记录 WebEditorWrapper 的用途（被 UnifiedEditorWrapper 内部使用，以及 NewNoteView 直接使用）

### 需求 10：清理 MenuActionHandler 中的 TODO 注释

**用户故事：** 作为开发者，我希望清理 MenuActionHandler 中的 TODO 注释，或实现相关功能。

#### 验收标准

1. THE Code_Cleanup_System SHALL 检查 MenuActionHandler.swift 中的 TODO 注释
2. IF TODO 功能已在其他地方实现 THEN Code_Cleanup_System SHALL 删除 TODO 注释
3. IF TODO 功能未实现且不需要 THEN Code_Cleanup_System SHALL 删除相关代码或添加说明
