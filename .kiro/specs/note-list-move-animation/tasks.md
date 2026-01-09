# Implementation Plan: Note List Move Animation

## Overview

为 NotesListView 添加笔记位置变化的移动动画。实现非常简洁，只需添加动画配置枚举和一行动画修饰符。

## Tasks

- [x] 1. 添加列表动画支持
  - [x] 1.1 在 NotesListView.swift 中添加 ListAnimationConfig 枚举
    - 定义 `moveAnimation` 静态属性，配置 `.easeInOut(duration: 0.3)`
    - _Requirements: 1.2_
  - [x] 1.2 在 notesListContent 的 Group 上添加 animation 修饰符
    - 使用 `.animation(ListAnimationConfig.moveAnimation, value: viewModel.filteredNotes.map(\.id))`
    - 监听笔记 ID 数组变化触发动画
    - _Requirements: 1.1, 1.3_

- [ ] 2. 手动验证
  - 编辑笔记内容，观察笔记是否平滑移动到顶部
  - 确认选中状态在动画期间保持不变
  - _Requirements: 1.1, 1.4_

## Notes

- 实现非常简洁，核心代码只有约 10 行
- 选中状态保持已由现有的 ViewStateCoordinator 处理，无需额外代码
- 属性测试已由 view-state-sync spec 覆盖，无需重复添加
