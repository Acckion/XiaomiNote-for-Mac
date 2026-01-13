# 实现计划：光标格式状态同步

## 概述

本实现计划将创建统一的 `CursorFormatManager` 来协调格式检测、工具栏同步和输入格式继承（typingAttributes）。

## 任务

- [x] 1. 创建 CursorFormatManager 核心类
  - [x] 1.1 创建 CursorFormatManager.swift 文件，实现单例模式和基础结构
    - 定义属性：textView、editorContext、debounceTimer、currentFormatState
    - 实现 register/unregister 方法
    - _Requirements: 6.1, 6.4_
  - [x] 1.2 实现格式检测方法 detectFormatState(at:)
    - 获取光标前一个字符的属性
    - 处理边界条件（位置为 0、空文档）
    - 返回 FormatState
    - _Requirements: 1.1-1.6, 5.1-5.5_
  - [x] 1.3 实现防抖机制
    - 使用 Timer 实现 50ms 防抖
    - 合并快速连续的光标位置变化
    - _Requirements: 6.5_

- [x] 2. 实现 FormatAttributesBuilder
  - [x] 2.1 创建 FormatAttributesBuilder.swift 文件
    - 实现 build(from:) 方法
    - 处理字体属性（加粗、斜体）
    - 处理装饰属性（下划线、删除线、高亮）
    - _Requirements: 2.1-2.6, 3.1_
  - [x] 2.2 编写属性构建器单元测试
    - 测试各种格式组合的属性构建
    - 测试边界条件
    - _Requirements: 2.1-2.6_

- [x] 3. 实现 typingAttributes 同步
  - [x] 3.1 实现 syncTypingAttributes(with:) 方法
    - 使用 FormatAttributesBuilder 构建属性字典
    - 更新 NSTextView 的 typingAttributes
    - _Requirements: 3.1, 3.4_
  - [ ] 3.2 编写 typingAttributes 同步属性测试
    - **Property 5: typingAttributes 同步**
    - **Validates: Requirements 3.1**

- [x] 4. 实现工具栏状态更新
  - [x] 4.1 实现 updateToolbarState(with:) 方法
    - 更新 NativeEditorContext 的 currentFormats 和 toolbarButtonStates
    - _Requirements: 1.1-1.6, 4.6_
  - [ ]* 4.2 编写工具栏状态同步属性测试
    - **Property 1: 单一格式工具栏状态同步**
    - **Property 2: 多格式工具栏状态同步**
    - **Validates: Requirements 1.1-1.6**

- [x] 5. 实现 FormatStateManager 集成
  - [x] 5.1 实现 notifyFormatStateManager(with:) 方法
    - 发送格式状态变化通知
    - 确保菜单栏状态同步
    - _Requirements: 6.6_
  - [ ]* 5.2 编写 FormatStateManager 集成测试
    - **Property 10: FormatStateManager 集成**
    - **Validates: Requirements 6.6**

- [-] 6. 实现光标位置变化处理
  - [x] 6.1 实现 handleSelectionChange(_:) 方法
    - 检测是否为光标模式（无选择）
    - 调用格式检测、工具栏更新、typingAttributes 同步
    - _Requirements: 3.1, 6.2_
  - [ ]* 6.2 编写光标位置变化属性测试
    - **Property 8: 统一管理器协调**
    - **Validates: Requirements 6.2**

- [x] 7. 实现工具栏格式切换处理
  - [x] 7.1 实现 handleToolbarFormatToggle(_:) 方法
    - 更新 currentFormatState
    - 同步 typingAttributes
    - 更新工具栏状态
    - _Requirements: 4.1-4.6, 6.3_
  - [ ]* 7.2 编写工具栏格式切换属性测试
    - **Property 6: 工具栏格式切换同步**
    - **Validates: Requirements 3.4, 4.1-4.6**

- [x] 8. 集成到 NativeEditorView
  - [x] 8.1 在 NativeEditorView.Coordinator 中注册 CursorFormatManager
    - 在 makeNSView 中调用 register
    - 在 dismantleNSView 中调用 unregister
    - _Requirements: 6.4_
  - [x] 8.2 修改 textViewDidChangeSelection 方法
    - 调用 CursorFormatManager.handleSelectionChange
    - 移除原有的格式状态更新逻辑
    - _Requirements: 6.2_
  - [x] 8.3 修改格式应用逻辑
    - 调用 CursorFormatManager.handleToolbarFormatToggle
    - 确保格式切换后 typingAttributes 正确更新
    - _Requirements: 6.3_

- [ ] 9. Checkpoint - 确保所有测试通过
  - 运行所有单元测试和属性测试
  - 如有问题请询问用户

- [ ] 10. 编写输入格式继承属性测试
  - [ ]* 10.1 编写单一格式输入继承测试
    - **Property 3: 单一格式输入继承**
    - **Validates: Requirements 2.1-2.5**
  - [ ]* 10.2 编写多格式输入继承测试
    - **Property 4: 多格式输入继承**
    - **Validates: Requirements 2.6**

- [ ] 11. 编写边界条件和集成测试
  - [ ]* 11.1 编写格式交界处行为测试
    - **Property 7: 格式交界处行为**
    - **Validates: Requirements 5.2, 5.3**
  - [ ]* 11.2 编写防抖机制测试
    - **Property 9: 防抖机制**
    - **Validates: Requirements 6.5**
  - [ ]* 11.3 编写边界条件单元测试
    - 测试空文档、文档开头等边界情况
    - **Validates: Requirements 3.2, 3.3, 5.1, 5.4, 5.5**

- [ ] 12. Final Checkpoint - 确保所有测试通过
  - 运行完整测试套件
  - 验证功能正常工作
  - 如有问题请询问用户

## 注意事项

- 标记为 `*` 的任务是可选的，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以确保可追溯性
- 属性测试验证通用的正确性属性
- 单元测试验证具体的示例和边界条件
