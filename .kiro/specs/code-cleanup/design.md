# 设计文档：代码清理

## 概述

本设计文档描述了清理项目中旧版代码、多余代码和临时调试代码的方案。目标是提高代码质量和可维护性，减少代码复杂度，消除冗余实现。

## 架构

代码清理工作分为以下几个层次：

```
┌─────────────────────────────────────────────────────────────┐
│                    文件系统层清理                              │
│  - 删除 References/Old 目录                                   │
│  - 移动分析文档到 docs 目录                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    代码文件层清理                              │
│  - 删除未使用的文件（NoteEditorCoordinator.swift）            │
│  - 清理占位符代码（EditorProtocol.swift）                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    代码内容层清理                              │
│  - 删除重复工具栏代码（NoteDetailView.swift）                  │
│  - 清理 TODO 方法（MainWindowController.swift）               │
│  - 清理已弃用 API（PrivateNotesPasswordManager.swift）        │
└─────────────────────────────────────────────────────────────┘
```

## 组件和接口

### 1. 文件系统清理

#### 1.1 删除 References/Old 目录

**当前状态分析：**
- `References/Old` 目录包含完整的旧版项目副本
- 目录结构：
  - `.build/` - 构建产物
  - `.cursor/` - 编辑器配置
  - `.swiftpm/` - Swift 包管理器配置
  - `MiNoteMac.xcodeproj/` - 旧版 Xcode 项目
  - `Sources/` - 旧版源代码
  - 其他配置文件和文档

**清理方案：**
- 直接删除整个 `References/Old` 目录
- 保留其他 References 子目录（CotEditor、NetNewsWire、STTextView 等参考项目）

#### 1.2 移动分析文档

**当前状态：**
- `Sources/Web/ckeditor-vs-current-analysis.md` 是技术分析文档
- 不应该放在源代码目录中

**清理方案：**
- 创建 `docs/` 目录（如果不存在）
- 将文件移动到 `docs/ckeditor-vs-current-analysis.md`

### 2. 代码文件清理

#### 2.1 删除 NoteEditorCoordinator.swift

**当前状态分析：**
- 文件位置：`Sources/View/Bridge/NoteEditorCoordinator.swift`
- 代码搜索结果显示该类仅在以下位置被引用：
  - 自身文件定义
  - `project.pbxproj` 构建配置
  - 设计文档和需求文档
  - `README.md` 文档说明
- **结论：该类未被任何实际业务代码使用**

**清理方案：**
- 删除 `Sources/View/Bridge/NoteEditorCoordinator.swift` 文件
- 更新 `project.yml` 移除对该文件的引用（如果有）
- 重新生成 Xcode 项目

#### 2.2 清理 EditorProtocol.swift 中的占位符代码

**当前状态分析：**
- 文件包含以下内容：
  - `EditorProtocol` 协议定义 ✓ 保留
  - `EditorCreationError` 枚举 ✓ 保留
  - `EditorFactory` 类 ✓ 保留
  - `EditorInfo` 结构体 ✓ 保留
  - `NativeEditor` 类 ✗ 占位符实现，需删除
  - `WebEditor` 类 ✗ 占位符实现，需删除

**占位符代码问题：**
- `NativeEditor` 和 `WebEditor` 是占位符实现
- 实际编辑器实现在 `NativeEditorContext` 和 `WebEditorContext` 中
- `EditorFactory.createEditorSafely` 方法返回这些占位符类，导致功能不正确

**清理方案：**
- 删除 `NativeEditor` 类
- 删除 `WebEditor` 类
- 修改 `EditorFactory.createEditorSafely` 方法，使其抛出错误而不是返回占位符

### 3. 代码内容清理

#### 3.1 删除 NoteDetailView.swift 中的重复工具栏代码

**当前状态分析：**
- `NoteDetailView.swift` 包含完整的工具栏实现（约 200+ 行代码）
- `MainWindowToolbarDelegate` 已经实现了相同的工具栏功能
- 两套实现导致代码重复和维护困难

**需要删除的代码：**
```swift
// 工具栏内容属性
private var toolbarContent: some ToolbarContent { ... }

// 工具栏按钮定义
private var undoButton: some View { ... }
private var redoButton: some View { ... }
private var formatMenu: some View { ... }
private var checkboxButton: some View { ... }
private var horizontalRuleButton: some View { ... }
private var imageButton: some View { ... }
private var indentButtons: some View { ... }
private var debugModeToggleButton: some View { ... }
private var newNoteButton: some View { ... }
private func shareAndMoreButtons(for note: Note) -> some View { ... }

// FormatMenuPopoverContent 视图（如果在其他地方已实现）
struct FormatMenuPopoverContent: View { ... }

// .toolbar 修饰符调用
.toolbar { toolbarContent }
```

**清理方案：**
- 删除上述所有工具栏相关代码
- 保留 `MainWindowToolbarDelegate` 作为唯一的工具栏管理方式
- 确保应用程序编译通过并正常运行

#### 3.2 清理 MainWindowController.swift 中的 TODO 方法

**当前状态分析：**
需要清理的方法列表：
| 方法名 | 当前实现 | 是否被菜单调用 | 清理方案 |
|--------|----------|----------------|----------|
| `toggleBlockQuote` | print + TODO | 是 | 添加用户提示 |
| `markAsChecked` | print + TODO | 是 | 添加用户提示 |
| `checkAll` | print + TODO | 是 | 添加用户提示 |
| `uncheckAll` | print + TODO | 是 | 添加用户提示 |
| `moveCheckedToBottom` | print + TODO | 是 | 添加用户提示 |
| `deleteCheckedItems` | print + TODO | 是 | 添加用户提示 |
| `moveItemUp` | print + TODO | 是 | 添加用户提示 |
| `moveItemDown` | print + TODO | 是 | 添加用户提示 |
| `toggleLightBackground` | print + TODO | 是 | 添加用户提示 |
| `toggleHighlight` | print + TODO | 是 | 添加用户提示 |
| `expandSection` | print + TODO | 是 | 添加用户提示 |
| `expandAllSections` | print + TODO | 是 | 添加用户提示 |
| `collapseSection` | print + TODO | 是 | 添加用户提示 |
| `collapseAllSections` | print + TODO | 是 | 添加用户提示 |

**清理方案：**
- 这些方法都被菜单调用，不能直接删除
- 将 `print` + `TODO` 替换为用户提示（使用 `NSAlert`）
- 提示内容："此功能暂未实现"

#### 3.3 清理已弃用的 API

**当前状态分析：**
- `PrivateNotesPasswordManager.swift` 中的 `authenticateWithTouchIDWithDialog` 方法已标记为 `@available(*, deprecated)`
- 代码搜索显示该方法仅在自身文件中定义，未被其他代码调用

**清理方案：**
- 删除 `authenticateWithTouchIDWithDialog` 方法

#### 3.4 清理 NotesListViewController.swift 中的 moveNote 方法

**当前状态分析：**
- `NotesListViewController.swift` 中的 `moveNote` 方法仅包含 `TODO` 注释和 `print` 语句
- 该方法被右键菜单调用
- 移动笔记功能已在 `NoteMoveHelper` 和 `MoveNoteMenuView` 中实现

**清理方案：**
- 实现 `moveNote` 方法，调用 `NoteMoveHelper.moveNote` 或显示移动笔记菜单

#### 3.5 评估 WebEditorWrapper 使用情况

**当前状态分析：**
- `WebEditorWrapper.swift` 被以下代码使用：
  - `UnifiedEditorWrapper.swift` - 内部使用
  - `NewNoteView.swift` - 直接使用

**结论：**
- `WebEditorWrapper` 有明确的使用场景
- 保留当前结构，不进行清理

#### 3.6 清理 MenuActionHandler.swift 中的 TODO 注释

**当前状态分析：**
- 仅有一处 TODO 注释：
  ```swift
  // TODO: 未来可以通过 JavaScript 桥接获取 Web 编辑器的格式状态
  ```
- 这是一个合理的未来改进说明，不需要删除

**清理方案：**
- 保留该 TODO 注释，因为它描述了合理的未来改进方向

## 数据模型

本次清理不涉及数据模型变更。

## 正确性属性

*正确性属性是指在系统所有有效执行中都应该保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

由于代码清理主要是删除和重构操作，大多数验收标准是具体的示例测试，而非通用属性。以下是可以形式化的正确性属性：

### Property 1: 编译正确性
*对于任何*代码清理操作完成后，项目 SHALL 能够成功编译，无编译错误。
**验证: 需求 2.6**

### Property 2: 功能完整性
*对于任何*被删除的重复代码，其功能 SHALL 由保留的代码提供，用户体验不变。
**验证: 需求 2.5, 2.6**

### Property 3: 引用完整性
*对于任何*被删除的文件或代码，项目中 SHALL 不存在对其的引用（除文档说明外）。
**验证: 需求 3.1, 3.3**

## 错误处理

### 清理过程中的错误处理

1. **文件删除失败**
   - 检查文件权限
   - 确保文件未被其他进程占用
   - 记录错误并继续处理其他文件

2. **编译失败**
   - 回滚最近的更改
   - 分析编译错误
   - 修复依赖问题后重试

3. **功能回归**
   - 运行应用程序验证功能
   - 如发现问题，回滚相关更改
   - 分析原因并调整清理方案

## 测试策略

### 验证方法

由于代码清理主要是删除操作，测试策略以验证为主：

1. **编译验证**
   - 每次清理后运行 `xcodegen generate`
   - 运行 `xcodebuild build` 确保编译通过

2. **功能验证**
   - 运行应用程序
   - 验证工具栏功能正常
   - 验证菜单功能正常
   - 验证编辑器功能正常

3. **代码搜索验证**
   - 使用 `grep` 搜索确认删除的代码不再存在
   - 确认没有悬空引用

### 测试检查清单

- [ ] 项目编译成功
- [ ] 应用程序启动正常
- [ ] 工具栏按钮功能正常
- [ ] 菜单项功能正常
- [ ] 编辑器加载和编辑正常
- [ ] 无控制台错误输出
