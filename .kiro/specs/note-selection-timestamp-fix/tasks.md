# 实现计划：笔记选择时间戳修复

## 概述

修复笔记选择时错误更新时间戳的问题，确保只有在内容真正变化时才更新 `updatedAt` 时间戳，避免笔记在排序列表中错误移动。

## 任务

- [x] 1. 改进 buildUpdatedNote 方法
  - [x] 1.1 添加 shouldUpdateTimestamp 参数
    - 在 `buildUpdatedNote` 方法中添加 `shouldUpdateTimestamp: Bool = true` 参数
    - 根据参数决定使用 `Date()` 还是 `note.updatedAt`
    - _需求: 1.5_
  - [x] 1.2 更新方法调用点
    - 找到所有调用 `buildUpdatedNote` 的地方
    - 根据上下文决定是否传入 `shouldUpdateTimestamp: false`
    - _需求: 1.1, 1.2_

- [x] 2. 创建改进的内容变化检测方法
  - [x] 2.1 实现 hasContentActuallyChanged 方法
    - 创建专门的内容比较方法
    - 标准化内容比较（去除空白字符差异）
    - 同时检查内容和标题变化
    - 添加详细的调试日志
    - _需求: 2.1, 2.2_

- [x] 3. 修复 saveCurrentNoteBeforeSwitching 方法
  - [x] 3.1 使用改进的内容变化检测
    - 替换现有的内容变化检测逻辑
    - 使用 `hasContentActuallyChanged` 方法
    - _需求: 3.1, 3.2_
  - [x] 3.2 条件性调用 buildUpdatedNote
    - 只有在内容真正变化时才调用 `buildUpdatedNote` 并更新时间戳
    - 内容无变化时跳过保存操作
    - 添加相应的日志记录
    - _需求: 3.3, 3.4_

- [x] 4. 修复 ensureNoteHasFullContent 的副作用
  - [x] 4.1 保存原始时间戳
    - 在调用 `updateContent` 前保存原始的 `updatedAt`
    - _需求: 1.4_
  - [x] 4.2 检测内容实际变化
    - 比较更新前后的内容是否真正不同
    - 如果内容无实际变化，恢复原始时间戳
    - _需求: 1.4, 2.3_
  - [x] 4.3 添加调试日志
    - 记录内容变化检测结果
    - 记录时间戳保持或更新的决策
    - _需求: 2.3_

- [x] 5. 同步 lastSavedXMLContent 状态
  - [x] 5.1 修复 loadNoteContent 方法
    - 确保在 `ensureNoteHasFullContent` 后正确更新 `lastSavedXMLContent`
    - 确保在直接加载内容时也正确设置 `lastSavedXMLContent`
    - _需求: 2.2_
  - [x] 5.2 修复其他内容加载点
    - 检查所有更新 `currentXMLContent` 的地方
    - 确保同时更新 `lastSavedXMLContent`
    - _需求: 2.2_

- [x] 6. 更新其他保存方法
  - [x] 6.1 检查 performXMLSave 方法
    - 确保使用改进的内容变化检测
    - 确保正确的时间戳处理
    - _需求: 1.3, 2.4_
  - [x] 6.2 检查 saveTitleAndContent 方法
    - 确保使用改进的内容变化检测
    - 确保正确的时间戳处理
    - _需求: 1.3, 2.4_

- [x] 7. 添加调试和日志
  - [x] 7.1 增强现有日志
    - 在关键的内容变化检测点添加详细日志
    - 记录时间戳更新的决策过程
    - _需求: 3.3_
  - [x] 7.2 添加性能监控
    - 监控笔记切换的性能影响
    - 确保修复不会影响用户体验
    - _需求: 3.5_

- [ ] 8. 检查点 - 验证修复效果
  - 手动测试按编辑时间排序时点击旧笔记
  - 验证笔记位置不再错误移动
  - 验证修改内容时时间戳正确更新
  - 如有问题请询问用户

## 备注

- 所有任务都是必需的，因为这是一个关键的用户体验问题
- 每个任务引用具体需求以便追溯
- 重点关注不破坏现有的保存逻辑，只修复时间戳更新的问题
- 确保修复后的代码有充分的日志记录，便于后续调试