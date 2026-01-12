# 实现计划：笔记列表排序修复

## 概述

修复笔记列表排序功能的两个问题：按创建时间排序时显示创建时间，以及修复笔记选择时的错误移动问题。

## 任务

- [x] 1. 修改 NoteRow 时间显示逻辑
  - [x] 1.1 在 NoteRow 中添加 ViewOptionsManager 观察
    - 添加 `@ObservedObject var optionsManager: ViewOptionsManager = .shared`
    - _需求: 1.1, 1.2, 1.3_
  - [x] 1.2 添加 displayDate 计算属性
    - 根据 `optionsManager.sortOrder` 返回 `createdAt` 或 `updatedAt`
    - _需求: 1.1, 1.2, 1.3_
  - [x] 1.3 修改时间显示代码
    - 将 `formatDate(note.updatedAt)` 改为 `formatDate(displayDate)`
    - _需求: 1.1, 1.2, 1.3, 1.4_

- [x] 2. 修改 NoteCardView 时间显示逻辑
  - [x] 2.1 在 NoteCardView 中添加 ViewOptionsManager 观察
    - 添加 `@ObservedObject var optionsManager: ViewOptionsManager = .shared`
    - _需求: 1.5_
  - [x] 2.2 添加 displayDate 计算属性
    - 根据 `optionsManager.sortOrder` 返回 `createdAt` 或 `updatedAt`
    - _需求: 1.5_
  - [x] 2.3 修改 dateSection 视图
    - 将 `formatDate(note.updatedAt)` 改为 `formatDate(displayDate)`
    - _需求: 1.5_

- [x] 3. 检查点 - 验证时间显示修复
  - 确保所有修改编译通过
  - 手动测试切换排序方式时时间显示是否正确更新
  - 如有问题请询问用户

- [x] 4. 调查并修复笔记选择移动问题
  - [x] 4.1 分析笔记选择时的状态更新流程
    - 检查 `selectedNote` 更新是否触发不必要的数组变化
    - _需求: 2.1, 2.5_
  - [x] 4.2 检查 List 动画配置
    - 确保选择操作不触发移动动画
    - _需求: 2.1, 2.2, 2.3_
  - [x] 4.3 修复选择状态高亮问题
    - 确保选中的笔记正确显示高亮
    - _需求: 2.2, 2.3_

- [x] 5. 最终检查点
  - 确保所有测试通过
  - 如有问题请询问用户

## 备注

- 任务标记 `*` 为可选任务，可跳过以加快 MVP 开发
- 每个任务引用具体需求以便追溯
- 检查点确保增量验证
