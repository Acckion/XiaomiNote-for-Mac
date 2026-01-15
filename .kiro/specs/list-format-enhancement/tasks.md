# Implementation Plan: 列表格式增强

## Overview

本实现计划基于现有代码库的分析，专注于完善列表格式的创建、切换、转换、继承和取消功能。现有代码已经实现了基础的列表附件（BulletAttachment、OrderAttachment）、格式管理器（FormatManager）、块级格式处理器（BlockFormatHandler）和换行处理器（NewLineHandler）。本计划将补充缺失的功能并确保与小米笔记 XML 格式的完全兼容。

## Tasks

- [x] 1. 创建 ListFormatHandler 组件
  - [x] 1.1 创建 ListFormatHandler.swift 文件，实现列表格式处理器
    - 实现 `applyBulletList()` 方法，在行首插入 BulletAttachment
    - 实现 `applyOrderedList()` 方法，在行首插入 OrderAttachment
    - 实现 `removeListFormat()` 方法，移除列表附件和属性
    - 实现 `toggleBulletList()` 和 `toggleOrderedList()` 方法
    - 实现 `convertListType()` 方法，在有序/无序列表之间转换
    - 实现 `detectListType()` 方法，检测当前行的列表类型
    - 实现 `isEmptyListItem()` 方法，检测空列表项
    - _Requirements: 1.1-1.3, 2.1-2.3, 3.1-3.3, 4.1-4.3_

  - [x] 1.2 编写 ListFormatHandler 单元测试
    - 测试空行创建列表
    - 测试有内容行转换为列表
    - 测试列表切换（取消）
    - 测试列表类型转换
    - _Requirements: 1.1-1.3, 2.1-2.3, 3.1-3.3, 4.1-4.3_

- [x] 2. 实现列表与标题格式互斥
  - [x] 2.1 在 ListFormatHandler 中实现 `handleListHeadingMutualExclusion()` 方法
    - 应用列表格式时先移除标题格式
    - 应用标题格式时先移除列表格式
    - 确保列表行始终使用正文字体大小（14pt）
    - _Requirements: 5.1, 5.2, 5.3_

  - [x] 2.2 更新 BlockFormatHandler 的互斥逻辑
    - 确保标题和列表格式互斥
    - 在 `apply()` 方法中添加列表与标题的互斥处理
    - _Requirements: 5.1, 5.2, 5.3_

  - [x] 2.3 编写列表与标题互斥的属性测试
    - **Property 5: 列表与标题格式互斥**
    - **Validates: Requirements 5.1, 5.2, 5.3**

- [x] 3. 完善列表附件渲染
  - [x] 3.1 验证 BulletAttachment 渲染逻辑
    - 确保项目符号作为整体渲染
    - 验证删除时删除整个附件
    - _Requirements: 6.1, 6.3_

  - [x] 3.2 验证 OrderAttachment 渲染逻辑
    - 确保编号和点号作为整体渲染
    - 验证删除时删除整个附件
    - _Requirements: 6.2, 6.3_

- [x] 4. 扩展 NewLineHandler 支持列表换行
  - [x] 4.1 完善 `handleListNewLine()` 方法
    - 使用 BulletAttachment 替代文本符号 "• "
    - 使用 OrderAttachment 替代文本编号 "1. "
    - 确保有序列表编号自动递增
    - 清除内联格式但保留列表格式
    - _Requirements: 7.1, 7.2, 7.3_

  - [x] 4.2 完善 `handleEmptyListItem()` 方法
    - 空列表项回车时取消列表格式
    - 移除列表附件
    - 恢复为普通正文格式
    - _Requirements: 8.1, 8.2, 8.3_

  - [x] 4.3 编写列表换行的属性测试
    - **Property 6: 列表中回车正确继承格式**
    - **Property 7: 空列表回车正确取消格式**
    - **Validates: Requirements 7.1-7.3, 8.1-8.3**

- [x] 5. Checkpoint - 确保所有测试通过
  - 运行所有单元测试和属性测试
  - 确保列表创建、切换、转换功能正常
  - 如有问题，询问用户

- [x] 6. 完善 XML 转换器的列表支持
  - [x] 6.1 验证 ASTToAttributedStringConverter 的列表加载
    - 确保正确创建 BulletAttachment 和 OrderAttachment
    - 确保正确设置缩进级别
    - 确保有序列表编号根据 inputNumber 正确计算
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [x] 6.2 验证 AttributedStringToASTConverter 的列表保存
    - 确保正确检测 BulletAttachment 和 OrderAttachment
    - 确保生成正确的 XML 格式
    - 确保 inputNumber 规则正确（第一项为实际值减1，后续项为0）
    - 确保不使用 `<text>` 标签包裹列表内容
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [x]* 6.3 编写 XML 列表往返转换的属性测试（跳过 - 已有足够的单元测试覆盖）
    - **Property 8: XML 列表往返转换一致性**
    - **Validates: Requirements 9.1-9.4, 10.1-10.5**

- [x] 7. 实现菜单状态同步
  - [x] 7.1 更新 NativeEditorContext 的列表格式检测
    - 确保 `detectListFormats()` 正确检测 BulletAttachment 和 OrderAttachment
    - 确保光标移动时正确更新菜单状态
    - _Requirements: 11.1, 11.2, 11.3_

  - [x] 7.2 更新 FormatStateManager 的列表状态同步
    - 确保菜单栏和工具栏状态与编辑器内容同步
    - _Requirements: 11.1, 11.2, 11.3_

- [x] 8. 集成测试和验证
  - [x] 8.1 集成 ListFormatHandler 到 NativeEditorContext
    - 更新 `applyFormat()` 方法使用 ListFormatHandler
    - 确保菜单操作和工具栏操作使用相同逻辑
    - _Requirements: 1.1-1.3, 2.1-2.3, 3.1-3.3, 4.1-4.3_

  - [x] 8.2 编写端到端集成测试
    - 测试创建列表 → 编辑内容 → 保存 → 重新加载 → 验证内容
    - 测试菜单状态同步
    - _Requirements: 9.1-9.4, 10.1-10.5, 11.1-11.3_

- [x] 9. Final Checkpoint - 确保所有测试通过
  - 运行所有单元测试、属性测试和集成测试
  - 验证所有需求已满足
  - 如有问题，询问用户

## Notes

- 任务标记 `*` 的为可选任务，可以跳过以加快 MVP 开发
- 每个任务引用了具体的需求以便追溯
- 检查点确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
