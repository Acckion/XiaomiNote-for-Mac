# Implementation Plan: XML Debug Editor

## Overview

实现 XML 调试编辑器功能，允许开发者直接查看和编辑笔记的原始 XML 数据。采用增量开发方式，先实现核心功能，再添加增强功能。

## Tasks

- [x] 1. 创建 XMLDebugEditorView 组件
  - [x] 1.1 创建基础视图结构
    - 创建 `Sources/View/SwiftUIViews/XMLDebugEditorView.swift`
    - 实现 TextEditor 显示 XML 内容
    - 使用等宽字体 (`.monospaced`)
    - 支持深色/浅色模式
    - _Requirements: 2.1, 2.2, 6.5_
  - [x] 1.2 实现空内容占位符
    - 当 XML 内容为空时显示 "无 XML 内容"
    - _Requirements: 2.4_
  - [x] 1.3 实现内容编辑功能
    - 支持实时编辑 XML 内容
    - 保留换行和缩进
    - _Requirements: 3.1, 3.4_

- [x] 2. 集成到 NoteDetailView
  - [x] 2.1 添加调试模式状态
    - 添加 `isDebugMode` 状态变量
    - 添加 `debugXMLContent` 状态变量
    - _Requirements: 1.1, 1.2_
  - [x] 2.2 实现视图切换逻辑
    - 根据 `isDebugMode` 显示不同编辑器
    - 切换时同步内容
    - _Requirements: 1.1, 1.2, 1.4, 6.2_
  - [x] 2.3 添加调试模式切换按钮
    - 在工具栏添加切换按钮
    - 显示当前模式状态
    - 无笔记时禁用按钮
    - _Requirements: 1.3, 1.5, 6.1_

- [x] 3. 实现保存功能
  - [x] 3.1 实现保存逻辑
    - 更新 Note.content
    - 触发本地数据库保存
    - 调度云端同步
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - [x] 3.2 实现保存状态指示
    - 显示 "保存中..." 状态
    - 显示 "已保存" 状态
    - 显示错误信息
    - _Requirements: 4.5, 4.6, 4.7_
  - [x] 3.3 实现未保存状态检测
    - 内容修改时标记为未保存
    - _Requirements: 3.3_

- [x] 4. 实现快捷键支持
  - [x] 4.1 实现 Cmd+S 保存快捷键
    - 在调试模式下触发保存
    - _Requirements: 5.1_
  - [x] 4.2 实现 Cmd+Shift+D 切换快捷键
    - 切换调试模式开/关
    - _Requirements: 5.2_

- [x] 5. 实现笔记切换处理
  - [x] 5.1 处理笔记切换时的内容加载
    - 切换笔记时加载新笔记的 XML 内容
    - 保持调试模式状态
    - _Requirements: 6.4_

- [ ] 6. Checkpoint - 功能验证
  - 确保所有基本功能正常工作
  - 手动测试模式切换、编辑、保存流程
  - 如有问题请告知

- [ ]* 7. 编写属性测试
  - [ ]* 7.1 Property 1: 调试模式显示正确的 XML 内容
    - **Property 1: 调试模式显示正确的 XML 内容**
    - **Validates: Requirements 1.1, 2.1**
  - [ ]* 7.2 Property 2: 模式切换往返保留内容
    - **Property 2: 模式切换往返保留内容**
    - **Validates: Requirements 1.2, 1.4**
  - [ ]* 7.3 Property 4: 保存操作更新笔记内容
    - **Property 4: 保存操作更新笔记内容**
    - **Validates: Requirements 4.1, 4.2**
  - [ ]* 7.4 Property 6: 换行和缩进保留
    - **Property 6: 换行和缩进保留**
    - **Validates: Requirements 3.4**

- [ ] 8. Final Checkpoint - 完成验证
  - 确保所有测试通过
  - 验证与现有功能的兼容性
  - 如有问题请告知

## Notes

- 任务标记 `*` 的为可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- 检查点用于确保增量验证
- 属性测试验证通用正确性属性
