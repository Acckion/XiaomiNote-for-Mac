# Implementation Plan: 列表行为优化

## Overview

本实现计划基于设计文档，专注于优化原生编辑器的列表行为，包括光标位置限制、回车键文本分割、删除键行合并、有序列表编号更新以及勾选框状态切换。支持三种列表类型：无序列表（•）、有序列表（1. 2. 3.）和勾选框列表（☐/☑）。实现将扩展现有的 `NativeTextView` 和 `ListFormatHandler`，并新增 `ListBehaviorHandler` 组件。

## Tasks

- [x] 1. 创建 ListBehaviorHandler 组件
  - [x] 1.1 创建 ListBehaviorHandler.swift 文件
    - 实现 `getContentStartPosition()` 方法，获取列表项内容区域起始位置
    - 实现 `isInListMarkerArea()` 方法，检查位置是否在列表标记区域
    - 实现 `adjustCursorPosition()` 方法，调整光标位置确保不在标记区域
    - 实现 `getListItemInfo()` 方法，获取列表项完整信息
    - _Requirements: 1.1, 1.3, 1.4_

  - [x] 1.2 编写 ListBehaviorHandler 光标位置限制单元测试
    - 测试 getContentStartPosition 返回正确位置
    - 测试 isInListMarkerArea 正确检测标记区域
    - 测试 adjustCursorPosition 正确调整位置
    - _Requirements: 1.1, 1.3, 1.4_

- [x] 2. 实现光标位置限制
  - [x] 2.1 扩展 NativeTextView 重写光标移动方法
    - 重写 `setSelectedRange()` 方法，限制光标位置
    - 重写 `moveLeft()` 方法，处理左移光标到上一行
    - 重写 `moveToBeginningOfLine()` 方法，移动到内容起始位置
    - 重写 `moveWordLeft()` 方法，处理 Option+左方向键
    - _Requirements: 1.1, 1.2, 1.4_

  - [x] 2.2 编写光标位置限制属性测试
    - **Property 1: 光标位置限制**
    - **Validates: Requirements 1.1, 1.2, 1.4**

- [x] 3. Checkpoint - 确保光标限制功能正常
  - 运行所有单元测试和属性测试 ✓ (35 个测试全部通过)
  - 验证光标不能移动到列表标记左侧 ✓
  - 如有问题，询问用户

- [x] 4. 实现回车键文本分割
  - [x] 4.1 在 ListBehaviorHandler 中实现回车键处理
    - 实现 `handleEnterKey()` 方法，统一处理回车键
    - 实现 `splitTextAtCursor()` 方法，在光标位置分割文本
    - 实现 `createNewListItem()` 方法，创建新列表项
    - 处理边界情况：光标在行首、行尾
    - 勾选框列表：新建项默认为未勾选状态（☐）
    - _Requirements: 2.1, 2.2, 2.3, 2.6, 2.7, 2.8_

  - [x] 4.2 更新 NativeTextView 的 keyDown 方法
    - 修改回车键处理逻辑，调用 ListBehaviorHandler
    - 确保文本分割后光标位置正确
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 4.3 编写文本分割属性测试
    - **Property 2: 文本分割正确性**
    - **Validates: Requirements 2.1, 2.2, 2.3**

- [x] 5. 实现格式继承
  - [x] 5.1 完善新列表项的格式继承逻辑
    - 确保新列表项继承列表类型（无序、有序或勾选框）
    - 确保新列表项继承缩进级别
    - 确保有序列表编号正确递增
    - 确保勾选框列表新项为未勾选状态
    - _Requirements: 2.4, 2.5, 2.6_

  - [x] 5.2 编写格式继承属性测试
    - **Property 3: 格式继承正确性**
    - **Validates: Requirements 2.4, 2.5, 2.6**

- [x] 6. 优化空列表项回车行为
  - [x] 6.1 更新空列表项检测和处理逻辑
    - 优化 `isEmptyListItem()` 方法，正确检测空列表项
    - 确保空列表项回车取消格式而非换行
    - 确保光标保持在当前行
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 6.2 编写空列表回车属性测试
    - **Property 4: 空列表回车取消格式**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4**

- [x] 7. Checkpoint - 确保回车键功能正常
  - 运行所有单元测试和属性测试
  - 验证文本分割、格式继承、空列表取消功能
  - 如有问题，询问用户

- [x] 8. 实现删除键行合并
  - [x] 8.1 在 ListBehaviorHandler 中实现删除键处理
    - 实现 `handleBackspaceKey()` 方法，处理删除键
    - 实现 `mergeWithPreviousLine()` 方法，合并到上一行
    - 处理上一行是列表项的情况
    - 处理上一行是普通文本的情况
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 8.2 更新 NativeTextView 的 keyDown 方法
    - 添加删除键处理逻辑，调用 ListBehaviorHandler
    - 确保合并后光标位置正确
    - _Requirements: 4.1, 4.2_

  - [x] 8.3 编写删除键合并属性测试
    - **Property 5: 删除键合并行为**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4**
    - ✅ 6 个属性测试全部通过（100 次迭代/测试）

- [x] 9. 实现选择行为限制
  - [x] 9.1 扩展 NativeTextView 重写选择方法
    - 重写 `moveLeftAndModifySelection()` 方法
    - 重写 `moveToBeginningOfLineAndModifySelection()` 方法
    - 确保选择不包含列表标记
    - _Requirements: 5.1, 5.2_

  - [x] 9.2 编写选择行为属性测试
    - **Property 6: 选择行为限制**
    - **Validates: Requirements 5.1, 5.2**

- [-] 10. 实现有序列表编号更新
  - [x] 10.1 在 ListBehaviorHandler 中实现编号更新
    - 实现 `updateOrderedListNumbers()` 方法
    - 在插入新列表项后更新后续编号
    - 在删除列表项后更新后续编号
    - 确保编号从 1 开始连续递增
    - _Requirements: 6.1, 6.2, 6.4_

  - [x] 10.2 集成编号更新到回车和删除操作
    - 在 handleEnterKey 后调用编号更新
    - 在 handleBackspaceKey 后调用编号更新
    - _Requirements: 6.1, 6.2_

  - [ ] 10.3 编写编号连续性属性测试
    - **Property 7: 编号连续性**
    - **Validates: Requirements 6.1, 6.2, 6.4**

- [ ] 11. Checkpoint - 确保所有功能正常
  - 运行所有单元测试和属性测试
  - 验证删除键合并、选择限制、编号更新功能
  - 如有问题，询问用户

- [-] 12. 实现勾选框状态切换
  - [x] 12.1 在 ListBehaviorHandler 中实现勾选框处理
    - 实现 `toggleCheckboxState()` 方法，切换勾选状态
    - 实现 `isInCheckboxArea()` 方法，检测勾选框区域
    - 确保切换后光标位置不变
    - 确保切换后内容不变
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x] 12.2 扩展 NativeTextView 处理勾选框点击
    - 重写 `mouseDown()` 方法，检测勾选框点击
    - 点击勾选框时切换状态而非移动光标
    - 添加快捷键支持（Cmd+Shift+U）
    - _Requirements: 1.5, 7.1, 7.2, 7.5_

  - [ ] 12.3 编写勾选框状态切换属性测试
    - **Property 8: 勾选框状态切换**
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4**

- [ ] 13. Checkpoint - 确保勾选框功能正常
  - 运行所有单元测试和属性测试
  - 验证勾选框点击切换、快捷键切换功能
  - 如有问题，询问用户

- [ ] 14. 集成测试和验证
  - [ ] 14.1 编写端到端集成测试
    - 测试完整的列表编辑流程
    - 测试光标限制 → 文本分割 → 格式继承 → 编号更新
    - 测试空列表取消 → 删除键合并
    - 测试勾选框点击切换 → 新建勾选框项
    - _Requirements: 1.1-7.5_

  - [ ] 14.2 验证与现有功能的兼容性
    - 确保不影响现有的列表创建、切换、转换功能
    - 确保不影响 XML 格式转换
    - 确保不影响菜单状态同步
    - _Requirements: 1.1-7.5_

- [-] 15. Final Checkpoint - 确保所有测试通过
  - 运行所有单元测试、属性测试和集成测试
  - 验证所有需求已满足
  - 如有问题，询问用户

## Notes

- 每个任务引用了具体的需求以便追溯
- 检查点确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
- 实现需要与现有的 ListFormatHandler 和 NewLineHandler 协调工作
- 支持三种列表类型：无序列表、有序列表和勾选框列表
- 勾选框列表的行为与其他列表类型一致，额外支持点击切换状态

