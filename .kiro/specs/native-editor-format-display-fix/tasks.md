# 实现计划：原生编辑器格式显示修复

## 概述

修复原生编辑器在切换笔记时格式不显示的问题。通过添加内容版本号、发送内容变化通知和强制刷新显示来确保格式正确渲染。

## 任务

- [x] 1. 修改 NativeEditorContext 添加内容版本号和通知机制
  - [x] 1.1 添加 contentVersion 属性
    - 在 NativeEditorContext 中添加 `@Published var contentVersion: Int = 0`
    - _Requirements: 3.1_
  - [x] 1.2 修改 loadFromXML 方法
    - 在更新 nsAttributedText 后递增 contentVersion
    - 在更新完成后发送 contentChangeSubject.send()
    - _Requirements: 2.1, 2.2, 2.3, 3.1_

- [x] 2. 修改 NativeEditorView 的 Coordinator
  - [x] 2.1 添加 lastContentVersion 属性
    - 在 Coordinator 中添加 `var lastContentVersion: Int = 0`
    - _Requirements: 3.1, 3.2_
  - [x] 2.2 修改 handleExternalContentUpdate 方法
    - 移除不必要的内容比较逻辑
    - 添加 `textView.needsDisplay = true` 强制刷新
    - _Requirements: 1.1, 1.3, 2.3_

- [x] 3. 修改 NativeEditorView 的 updateNSView 方法
  - [x] 3.1 添加版本号比较逻辑
    - 比较 lastContentVersion 和 editorContext.contentVersion
    - 当版本号变化时强制更新内容
    - _Requirements: 3.1, 3.2, 3.3_
  - [x] 3.2 添加强制刷新显示
    - 在更新 textStorage 后设置 `textView.needsDisplay = true`
    - _Requirements: 1.1, 1.3_

- [x] 4. Checkpoint - 验证基本功能
  - 确保所有修改编译通过
  - 手动测试笔记切换时格式是否正确显示
  - 如有问题，询问用户

- [ ]* 5. 编写属性测试
  - [ ]* 5.1 编写 Property 1 测试：笔记切换后格式正确显示
    - **Property 1: 笔记切换后格式正确显示**
    - **Validates: Requirements 1.1, 1.3, 3.3**
  - [ ]* 5.2 编写 Property 3 测试：内容变化检测
    - **Property 3: 内容变化检测**
    - **Validates: Requirements 3.1, 3.2**

- [ ] 6. Final Checkpoint - 确保所有测试通过
  - 运行所有测试，确保通过
  - 如有问题，询问用户

## 备注

- 任务标记 `*` 的是可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追踪
- Checkpoint 确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
