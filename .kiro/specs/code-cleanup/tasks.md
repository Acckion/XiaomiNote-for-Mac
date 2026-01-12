# 实现计划：代码清理

## 概述

本实现计划将代码清理工作分解为可执行的任务，按照依赖关系和风险级别排序。每个任务完成后都需要验证编译通过。

## 任务

- [x] 1. 删除旧版项目副本
  - 删除 `References/Old` 目录及其所有内容
  - 验证其他 References 子目录（CotEditor、NetNewsWire 等）仍然存在
  - _需求: 1.1, 1.2, 1.3_

- [x] 2. 删除未使用的 NoteEditorCoordinator 类
  - [x] 2.1 删除 `Sources/View/Bridge/NoteEditorCoordinator.swift` 文件
    - _需求: 3.2_
  - [x] 2.2 更新 `project.yml` 移除对该文件的引用（如果有）
    - _需求: 3.3_
  - [x] 2.3 重新生成 Xcode 项目并验证编译通过
    - 运行 `xcodegen generate`
    - 运行 `xcodebuild build`
    - _需求: 3.1, 3.2, 3.3_

- [x] 3. 清理 EditorProtocol.swift 中的占位符代码
  - [x] 3.1 删除 `NativeEditor` 占位符类
    - _需求: 4.1_
  - [x] 3.2 删除 `WebEditor` 占位符类
    - _需求: 4.2_
  - [x] 3.3 修改 `EditorFactory.createEditorSafely` 方法
    - 移除对占位符类的引用
    - 使方法抛出错误而不是返回占位符
    - _需求: 4.4_
  - [x] 3.4 验证编译通过
    - _需求: 4.3_

- [x] 4. 检查点 - 确保所有测试通过
  - 运行 `xcodebuild test`
  - 如有问题，询问用户

- [x] 5. 删除 NoteDetailView.swift 中的重复工具栏代码
  - [x] 5.1 删除 `toolbarContent` 属性
    - _需求: 2.1_
  - [x] 5.2 删除所有工具栏按钮定义
    - 删除 `undoButton`、`redoButton`、`formatMenu`、`checkboxButton`
    - 删除 `horizontalRuleButton`、`imageButton`、`indentButtons`
    - 删除 `debugModeToggleButton`、`newNoteButton`、`shareAndMoreButtons`
    - _需求: 2.2_
  - [x] 5.3 删除 `.toolbar` 修饰符调用
    - _需求: 2.3_
  - [x] 5.4 检查并删除 `FormatMenuPopoverContent` 视图（如果已在其他地方实现）
    - _需求: 2.4_
  - [x] 5.5 验证编译通过并测试工具栏功能
    - _需求: 2.5, 2.6_

- [x] 6. 清理 MainWindowController.swift 中的 TODO 方法
  - [x] 6.1 修改 `toggleBlockQuote` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.2 修改 `markAsChecked` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.3 修改 `checkAll` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.4 修改 `uncheckAll` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.5 修改 `moveCheckedToBottom` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.6 修改 `deleteCheckedItems` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.7 修改 `moveItemUp` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.8 修改 `moveItemDown` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.9 修改 `toggleLightBackground` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.10 修改 `toggleHighlight` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.11 修改 `expandSection` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.12 修改 `expandAllSections` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.13 修改 `collapseSection` 方法添加用户提示
    - _需求: 5.3_
  - [x] 6.14 修改 `collapseAllSections` 方法添加用户提示
    - _需求: 5.3, 5.4_

- [x] 7. 清理已弃用的 API
  - [x] 7.1 删除 `PrivateNotesPasswordManager.swift` 中的 `authenticateWithTouchIDWithDialog` 方法
    - _需求: 6.1, 6.2_
  - [x] 7.2 验证编译通过
    - _需求: 6.1_

- [x] 8. 实现 NotesListViewController.swift 中的 moveNote 方法
  - [x] 8.1 实现 `moveNote` 方法，显示移动笔记菜单
    - _需求: 8.1, 8.2_
  - [x] 8.2 验证右键菜单功能正常
    - _需求: 8.3_

- [x] 9. 移动分析文档
  - [x] 9.1 创建 `docs/` 目录（如果不存在）
    - _需求: 7.1_
  - [x] 9.2 将 `Sources/Web/ckeditor-vs-current-analysis.md` 移动到 `docs/` 目录
    - _需求: 7.1_
  - [x] 9.3 检查并更新任何引用该文件的代码或文档
    - _需求: 7.2_

- [x] 10. 最终检查点 - 确保所有测试通过
  - 运行完整测试套件
  - 运行应用程序验证功能
  - 如有问题，询问用户

## 注意事项

- 每个任务完成后都需要验证编译通过
- 如果删除代码导致编译失败，需要分析依赖关系并调整清理方案
- 保留 `WebEditorWrapper` 和 `MenuActionHandler` 中的 TODO 注释（根据设计决策）
- 记录 `WebEditorWrapper` 的用途：被 `UnifiedEditorWrapper` 内部使用，以及 `NewNoteView` 直接使用
