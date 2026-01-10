# Implementation Plan: Dynamic Toolbar Visibility

## Overview

实现类似 Apple Notes 的工具栏动态显示功能，使用 macOS 15 的 `NSToolbarItem.hidden` 属性。根据视图模式、文件夹选择和笔记选择状态动态控制工具栏项可见性。

## Tasks

- [x] 1. 更新项目最低系统要求
  - 修改 project.yml 中的 deploymentTarget 为 macOS 15.0
  - 更新 README.md 中的系统要求说明
  - _Requirements: 前置条件_

- [x] 2. 创建 ToolbarVisibilityManager 核心组件
  - [x] 2.1 创建 ToolbarVisibilityManager.swift 文件
    - 定义工具栏项分类常量（editorItemIdentifiers, noteActionItemIdentifiers, contextItemIdentifiers）
    - 实现初始化方法，接收 toolbar 和 viewModel 引用
    - _Requirements: 1.3, 5.4_

  - [x] 2.2 实现状态监听逻辑
    - 使用 Combine 监听 ViewOptionsManager.viewMode 变化
    - 监听 NotesViewModel.selectedFolder 变化
    - 监听 NotesViewModel.selectedNote 变化
    - 监听 NotesViewModel.isPrivateNotesUnlocked 变化
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 2.3 实现可见性更新逻辑
    - 实现 updateToolbarVisibility() 方法
    - 实现 updateItemVisibility() 方法，根据项类别设置 isHidden
    - _Requirements: 1.1, 1.2, 2.1, 3.1, 3.2, 3.3, 4.1, 4.2_

- [x] 3. 集成到 MainWindowController
  - [x] 3.1 在 MainWindowController 中创建 ToolbarVisibilityManager 实例
    - 在 setupToolbar() 方法中初始化 visibilityManager
    - 保持对 visibilityManager 的强引用
    - _Requirements: 5.4_

  - [x] 3.2 在工具栏项添加时设置初始可见性
    - 修改 toolbarWillAddItem 方法，调用 visibilityManager 更新新添加项的可见性
    - _Requirements: 6.3_

- [x] 4. 更新 MiNoteToolbarItem 验证逻辑
  - [x] 4.1 修改 validate() 方法
    - 确保隐藏的工具栏项不会被错误地启用
    - 隐藏状态优先于启用状态
    - _Requirements: 2.2, 2.3_

- [x] 5. Checkpoint - 确保基础功能正常
  - [x] 编译项目，确保没有错误
  - 手动测试视图模式切换时工具栏项的显示/隐藏
  - 确保所有测试通过，如有问题请询问用户

- [ ]* 6. 编写属性测试
  - [ ]* 6.1 编写 Property 1 测试：编辑器项可见性一致性
    - **Property 1: Editor Items Visibility Consistency**
    - **Validates: Requirements 1.1, 1.2, 2.1**

  - [ ]* 6.2 编写 Property 2 测试：锁按钮可见性一致性
    - **Property 2: Lock Button Visibility Consistency**
    - **Validates: Requirements 3.1, 3.2, 3.3**

  - [ ]* 6.3 编写 Property 3 测试：笔记操作项可见性一致性
    - **Property 3: Note Action Items Visibility Consistency**
    - **Validates: Requirements 4.1, 4.2**

- [x] 7. Final Checkpoint - 确保所有功能正常
  - [x] 确保所有测试通过
  - [x] 验证自定义工具栏界面中隐藏项显示为虚线框
  - [x] 如有问题请询问用户

- [x] 8. 修复画廊视图中多个连续空白间距问题
  - [x] 8.1 添加 editorItemGroup 工具栏标识符
    - 在 ToolbarIdentifiers.swift 中添加 .editorItemGroup 标识符
  - [x] 8.2 创建编辑器工具栏项组
    - 在 MainWindowToolbarDelegate 中实现 createEditorItemGroup 方法
    - 使用 NSToolbarItemGroup 将编辑器项组合在一起
  - [x] 8.3 更新默认工具栏配置
    - 修改 toolbarDefaultItemIdentifiers 使用 editorItemGroup 替代单独的编辑器项
  - [x] 8.4 更新 ToolbarVisibilityManager
    - 在 editorItemIdentifiers 中添加 .editorItemGroup
  - _Requirements: 1.4（新增）- 编辑器项隐藏时不应出现多个连续空白间距_

## Notes

- 任务标记 `*` 的为可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- Checkpoint 任务用于确保增量验证
- 属性测试验证通用正确性属性
