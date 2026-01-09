# Implementation Plan: 视图状态同步

## Overview

本实现计划将设计文档中的架构转化为具体的编码任务。实现顺序遵循依赖关系：先创建核心数据模型和协调器，然后修改现有视图以集成新的状态管理机制，最后添加动画支持和测试。

## Tasks

- [x] 1. 创建核心数据模型和状态协调器
  - [x] 1.1 创建 ViewState 和 StateTransition 数据模型
    - 在 `Sources/ViewModel/` 目录下创建 `ViewState.swift`
    - 实现 ViewState 结构体，包含 selectedFolderId、selectedNoteId、timestamp
    - 实现 isConsistent 方法验证状态一致性
    - 实现 StateTransition 结构体记录状态转换
    - _Requirements: 4.1, 4.3_
  - [x] 1.2 创建 NoteUpdateEvent 枚举
    - 在 `Sources/ViewModel/` 目录下创建 `NoteUpdateEvent.swift`
    - 实现各种更新事件类型
    - 实现 requiresListAnimation 和 shouldPreserveSelection 属性
    - _Requirements: 2.1, 1.1_
  - [x] 1.3 创建 ViewStateCoordinator 类
    - 在 `Sources/ViewModel/` 目录下创建 `ViewStateCoordinator.swift`
    - 实现 selectFolder 方法，包含保存检查和状态更新逻辑
    - 实现 selectNote 方法，包含归属验证逻辑
    - 实现 updateNoteContent 方法，不触发选择变化
    - 实现 validateStateConsistency 和 synchronizeState 方法
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  - [ ]* 1.4 编写 ViewStateCoordinator 属性测试
    - **Property 6: 状态不一致时自动修复**
    - **Validates: Requirements 3.4, 4.4**
  - [ ]* 1.5 编写 ViewStateCoordinator 属性测试
    - **Property 9: 笔记选择验证归属关系**
    - **Validates: Requirements 4.3**

- [x] 2. 扩展 NotesViewModel 支持精确更新
  - [x] 2.1 实现 updateNoteInPlace 方法
    - 在 `Sources/ViewModel/NotesViewModel.swift` 中添加方法
    - 只更新 notes 数组中对应笔记的属性
    - 不触发整个数组的重新发布
    - _Requirements: 5.1_
  - [x] 2.2 实现 batchUpdateNotes 方法
    - 支持批量更新笔记，带动画
    - 使用 withAnimation 包装更新操作
    - _Requirements: 2.3_
  - [ ]* 2.3 编写 NotesViewModel 属性测试
    - **Property 10: 笔记更新使用原地更新**
    - **Validates: Requirements 5.1**

- [ ] 3. Checkpoint - 确保核心组件测试通过
  - 运行所有属性测试，确保通过
  - 如有问题，询问用户

- [x] 4. 修改 NoteRow 视图优化重建逻辑
  - [x] 4.1 创建 NoteDisplayProperties 结构体
    - 在 `Sources/View/SwiftUIViews/NotesListView.swift` 中添加
    - 实现 Equatable 协议
    - 只包含影响显示的属性
    - _Requirements: 5.3, 5.4_
  - [x] 4.2 修改 NoteRow 使用 NoteDisplayProperties 进行比较
    - 使用 equatable 修饰符优化重建
    - 移除不必要的 id 修饰符
    - _Requirements: 5.2, 5.4_
  - [ ]* 4.3 编写 NoteRow 属性测试
    - **Property 11: 非显示属性变化不触发重建**
    - **Validates: Requirements 5.4**

- [x] 5. 修改 NotesListView 添加动画支持
  - [x] 5.1 添加列表项移动动画
    - 使用 animation 修饰符
    - 设置 300ms 动画持续时间
    - 使用 easeInOut 动画曲线
    - _Requirements: 2.1, 2.4_
  - [x] 5.2 添加分组变化动画
    - 使用 transition 修饰符
    - 实现淡入淡出效果
    - _Requirements: 2.2_

- [x] 6. 集成 ViewStateCoordinator 到现有视图
  - [x] 6.1 修改 NotesViewModel 集成 ViewStateCoordinator
    - 添加 coordinator 属性
    - 修改 selectedFolder 和 selectedNote 的 setter
    - 通过 coordinator 进行状态更新
    - _Requirements: 4.1, 4.2_
  - [x] 6.2 修改 SidebarView 使用 coordinator
    - 修改文件夹选择逻辑
    - 调用 coordinator.selectFolder
    - _Requirements: 3.1, 3.2, 3.3_
  - [x] 6.3 修改 NotesListView 使用 coordinator
    - 修改笔记选择逻辑
    - 调用 coordinator.selectNote
    - _Requirements: 1.1, 1.2_
  - [x] 6.4 修改 NoteDetailView 使用 coordinator
    - 修改内容更新逻辑
    - 调用 coordinator.updateNoteContent
    - _Requirements: 1.1, 1.2, 1.3_
  - [ ]* 6.5 编写状态同步属性测试
    - **Property 1: 笔记更新时选择状态保持不变**
    - **Validates: Requirements 1.1, 1.2**
  - [ ]* 6.6 编写状态同步属性测试
    - **Property 3: 文件夹切换后笔记列表正确过滤**
    - **Validates: Requirements 3.1**

- [ ] 7. Checkpoint - 确保集成测试通过
  - 运行所有属性测试，确保通过
  - 如有问题，询问用户

- [x] 8. 实现文件夹切换时的保存逻辑
  - [x] 8.1 修改 ViewStateCoordinator.selectFolder 添加保存检查
    - 检查 hasUnsavedContent 标志
    - 如果有未保存内容，先触发保存
    - 等待保存完成后再切换
    - _Requirements: 3.5, 6.1, 6.2_
  - [x] 8.2 修改 NoteDetailView 更新 hasUnsavedContent 标志
    - 在内容变化时设置为 true
    - 在保存完成后设置为 false
    - _Requirements: 6.1_
  - [ ]* 8.3 编写保存逻辑属性测试
    - **Property 7: 文件夹切换前保存内容**
    - **Validates: Requirements 3.5, 6.1**
  - [ ]* 8.4 编写状态更新顺序属性测试
    - **Property 8: 状态更新顺序正确**
    - **Validates: Requirements 4.2, 6.2**

- [x] 9. 修改 NotesListHostingController 优化刷新逻辑
  - [x] 9.1 移除不必要的强制刷新
    - 移除 selectedNote 变化时的强制刷新
    - 移除 notes 变化时的强制刷新
    - 依赖 SwiftUI 的自动更新机制
    - _Requirements: 5.2_
  - [x] 9.2 保留必要的刷新逻辑
    - 保留 selectedFolder 变化时的刷新
    - 保留 searchText 变化时的刷新
    - _Requirements: 3.1_

- [ ] 10. 实现状态恢复逻辑
  - [ ] 10.1 修改 ViewStateCoordinator 添加状态恢复
    - 在视图重建后恢复选择状态
    - 使用 UserDefaults 或内存缓存保存状态
    - _Requirements: 1.4_
  - [ ]* 10.2 编写状态恢复属性测试
    - **Property 2: 视图重建后选择状态恢复**
    - **Validates: Requirements 1.4**

- [ ] 11. Final Checkpoint - 确保所有测试通过
  - 运行所有属性测试，确保通过
  - 运行所有单元测试，确保通过
  - 如有问题，询问用户

## Notes

- 任务标记 `*` 的为可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求，确保可追溯性
- Checkpoint 任务用于验证阶段性成果
- 属性测试验证通用正确性属性，覆盖多种输入情况
