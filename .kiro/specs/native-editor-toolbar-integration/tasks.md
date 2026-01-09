# 实现计划：原生编辑器工具栏集成

## 概述

本实现计划将工具栏功能与原生编辑器集成，使格式菜单、复选框、分割线、附件等工具栏按钮能够正确地与原生编辑器交互。

## 任务

- [x] 1. 在 NotesViewModel 中添加共享的 NativeEditorContext
  - [x] 1.1 在 NotesViewModel 中添加 nativeEditorContext 属性
    - 添加 `@Published var nativeEditorContext = NativeEditorContext()` 属性
    - 确保与现有的 webEditorContext 属性并列
    - _需求: 1.1, 1.3_

  - [ ]* 1.2 编写单元测试验证 NativeEditorContext 初始化
    - 验证 NotesViewModel 初始化后 nativeEditorContext 不为 nil
    - 验证 nativeEditorContext 是 NativeEditorContext 类型
    - _需求: 1.1_

- [x] 2. 修改 NoteDetailView 使用共享的 NativeEditorContext
  - [x] 2.1 修改 NoteDetailView 使用 viewModel 中的 nativeEditorContext
    - 移除 `@StateObject private var nativeEditorContext = NativeEditorContext()`
    - 改为使用 `viewModel.nativeEditorContext`
    - 更新所有引用 nativeEditorContext 的地方
    - _需求: 1.2_

  - [x] 2.2 更新 UnifiedEditorWrapper 以接收共享的 NativeEditorContext
    - 确保 UnifiedEditorWrapper 使用传入的 nativeEditorContext
    - _需求: 1.2_

- [x] 3. 在 MainWindowController 中添加编辑器类型检测和路由方法
  - [x] 3.1 添加 isUsingNativeEditor 计算属性
    - 通过 EditorPreferencesService.shared.selectedEditorType 判断
    - _需求: 7.1_

  - [x] 3.2 添加 getCurrentNativeEditorContext() 方法
    - 从 viewModel 获取 nativeEditorContext
    - _需求: 1.3, 7.2_

  - [ ]* 3.3 编写属性测试验证编辑器类型路由正确性
    - **Property 2: 编辑器类型路由正确性**
    - **验证: 需求 7.2, 7.3, 7.4**

- [-] 4. 实现 toggleCheckbox 工具栏操作
  - [x] 4.1 修改 toggleCheckbox 方法实现
    - 检查是否有选中笔记
    - 根据编辑器类型调用对应的 insertCheckbox 方法
    - _需求: 3.1, 3.2, 3.4_

  - [ ]* 4.2 编写单元测试验证 toggleCheckbox 功能
    - 测试原生编辑器模式下调用 NativeEditorContext.insertCheckbox()
    - 测试 Web 编辑器模式下调用 WebEditorContext.insertCheckbox()
    - _需求: 3.1, 3.2_

- [-] 5. 实现 insertHorizontalRule 工具栏操作
  - [x] 5.1 修改 insertHorizontalRule 方法实现
    - 检查是否有选中笔记
    - 根据编辑器类型调用对应的 insertHorizontalRule 方法
    - _需求: 4.1, 4.2, 4.4_

  - [ ]* 5.2 编写单元测试验证 insertHorizontalRule 功能
    - 测试原生编辑器模式下调用 NativeEditorContext.insertHorizontalRule()
    - 测试 Web 编辑器模式下调用 WebEditorContext.insertHorizontalRule()
    - _需求: 4.1, 4.2_

- [-] 6. 实现 insertAttachment 工具栏操作
  - [x] 6.1 修改 insertAttachment 方法实现
    - 检查是否有选中笔记
    - 显示文件选择对话框
    - 根据编辑器类型调用对应的 insertImage 方法
    - _需求: 5.1, 5.2, 5.3, 5.5_

  - [ ]* 6.2 编写单元测试验证 insertAttachment 功能
    - 测试文件选择对话框显示
    - 测试图片插入流程
    - _需求: 5.1, 5.2, 5.3_

- [x] 7. 实现 showFormatMenu 工具栏操作
  - [x] 7.1 修改 showFormatMenu 方法支持原生编辑器
    - 根据编辑器类型创建 NativeFormatMenuView 或 WebFormatMenuView
    - 使用 AnyView 包装以支持不同类型的视图
    - _需求: 2.1, 2.2_

  - [ ]* 7.2 编写属性测试验证格式状态同步正确性
    - **Property 3: 格式状态同步正确性**
    - **验证: 需求 2.3**

- [x] 8. 实现缩进工具栏操作
  - [x] 8.1 修改 increaseIndent 方法实现
    - 检查是否有选中笔记
    - 根据编辑器类型调用对应的缩进方法
    - _需求: 6.1, 6.3, 6.5_

  - [x] 8.2 修改 decreaseIndent 方法实现
    - 检查是否有选中笔记
    - 根据编辑器类型调用对应的缩进方法
    - _需求: 6.2, 6.4, 6.5_

  - [ ]* 8.3 编写属性测试验证缩进操作正确性
    - **Property 5: 缩进操作正确性**
    - **验证: 需求 6.1, 6.2**

- [ ] 9. 检查点 - 确保所有测试通过
  - 运行所有单元测试和属性测试
  - 确保所有测试通过，如有问题请询问用户

- [ ]* 10. 编写属性测试验证工具栏按钮禁用状态
  - **Property 1: 工具栏按钮禁用状态一致性**
  - 验证没有选中笔记时按钮被禁用
  - 验证有选中笔记时按钮被启用
  - **验证: 需求 3.4, 4.4, 5.5, 6.5**

- [ ] 11. 最终检查点 - 确保所有测试通过
  - 运行所有单元测试和属性测试
  - 确保所有测试通过，如有问题请询问用户

## 注意事项

- 任务标记为 `*` 的是可选的测试任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求，确保可追溯性
- 检查点任务用于验证增量进度
- 属性测试验证通用的正确性属性
- 单元测试验证具体的示例和边界情况
