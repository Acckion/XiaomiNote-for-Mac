# Implementation Plan: Cookie 静默刷新无限循环修复

## Overview

本实现计划将修复 Cookie 静默刷新的无限循环问题，通过添加冷却期机制、修复验证同步逻辑、添加失败计数限制等方式解决问题。

## Tasks

- [x] 1. 增强 SilentCookieRefreshManager 冷却期机制
  - [x] 1.1 添加冷却期相关属性和方法
    - 添加 `lastRefreshTime`、`lastRefreshResult`、`cooldownPeriod` 属性
    - 实现 `isInCooldownPeriod()` 方法
    - 实现 `resetCooldown()` 方法
    - 添加 `isRefreshing` 公开属性供其他组件查询
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 1.2 修改 refresh() 方法添加冷却期检查
    - 在刷新开始前检查冷却期
    - 冷却期内返回上次结果
    - 刷新完成后记录时间戳和结果
    - _Requirements: 1.1, 1.2, 1.4_

  - [x] 1.3 添加 Cookie 同步验证逻辑
    - 实现 `synchronizeCookiesAndVerify()` 方法
    - 验证 serviceToken 在 WKWebView 和 HTTPCookieStorage 中一致
    - 同步失败时返回刷新失败
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ]* 1.4 编写 SilentCookieRefreshManager 单元测试
    - 测试冷却期内请求被拒绝
    - 测试冷却期过期后请求被允许
    - 测试 Cookie 同步验证逻辑
    - _Requirements: 1.1, 1.2, 1.4, 3.1, 3.3_

- [x] 2. 增强 AuthenticationStateManager 刷新逻辑
  - [x] 2.1 添加失败计数和防重入机制
    - 添加 `consecutiveFailures` 计数器
    - 添加 `maxConsecutiveFailures` 常量（值为 3）
    - 添加 `isInRefreshCycle` 防重入标志
    - _Requirements: 4.1, 4.2, 2.4_

  - [x] 2.2 修改 attemptSilentRefresh() 方法
    - 添加防重入检查
    - 刷新前暂停定时检查任务
    - 使用 await 同步等待 checkCookieValidity() 完成
    - 根据验证结果决定是否恢复在线状态
    - 刷新后恢复定时检查任务（带 30 秒宽限期）
    - _Requirements: 2.1, 2.2, 2.3, 5.1_

  - [x] 2.3 添加失败处理方法
    - 实现 `handleRefreshSuccessButValidationFailed()` 方法
    - 实现 `handleRefreshFailure()` 方法
    - 达到最大失败次数时显示弹窗
    - _Requirements: 4.2, 4.3_

  - [x] 2.4 修复状态恢复逻辑
    - 实现 `restoreOnlineStatusAfterValidation()` 方法
    - 只有 Cookie 有效时才恢复在线状态
    - 只有 Cookie 有效时才清除 cookieExpiredShown 标志
    - 移除错误的"成功恢复在线状态"日志
    - _Requirements: 5.2, 5.3, 5.4_

  - [x] 2.5 添加手动刷新支持
    - 实现 `handleManualRefresh()` 方法
    - 重置失败计数器
    - 重置 SilentCookieRefreshManager 的冷却期
    - _Requirements: 4.4_

  - [ ]* 2.6 编写 AuthenticationStateManager 单元测试
    - 测试失败计数递增和重置
    - 测试达到最大次数后停止
    - 测试状态恢复逻辑
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.2, 5.4_

- [x] 3. 增强 ScheduledTaskManager 任务控制
  - [x] 3.1 添加任务暂停/恢复功能
    - 添加 `pausedTasks` 集合
    - 添加 `taskResumeTime` 字典
    - 实现 `pauseTask()` 方法
    - 实现 `resumeTask()` 方法（支持宽限期）
    - 实现 `isTaskPaused()` 方法
    - _Requirements: 6.3_

  - [ ]* 3.2 编写 ScheduledTaskManager 单元测试
    - 测试任务暂停功能
    - 测试任务恢复功能（带宽限期）
    - _Requirements: 6.3_

- [x] 4. 增强 CookieValidityCheckTask 协调逻辑
  - [x] 4.1 添加刷新期间跳过检查的逻辑
    - 实现 `shouldSkipCheck()` 方法
    - 在 execute() 中检查是否应该跳过
    - 跳过时返回成功结果（带 skipped 标记）
    - _Requirements: 6.1, 6.2_

  - [ ]* 4.2 编写 CookieValidityCheckTask 单元测试
    - 测试刷新期间跳过检查
    - _Requirements: 6.1_

- [ ] 5. Checkpoint - 确保所有测试通过
  - 运行所有单元测试
  - 确保没有编译错误
  - 如有问题，询问用户

- [ ]* 6. 编写属性测试
  - [ ]* 6.1 编写冷却期机制属性测试
    - **Property 1: 冷却期机制**
    - **Validates: Requirements 1.1, 1.2, 1.4**

  - [ ]* 6.2 编写刷新后验证同步属性测试
    - **Property 2: 刷新后验证同步**
    - **Validates: Requirements 2.1, 2.3, 2.4, 5.1**

  - [ ]* 6.3 编写失败计数与限制属性测试
    - **Property 4: 失败计数与限制**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4**

  - [ ]* 6.4 编写状态恢复正确性属性测试
    - **Property 5: 状态恢复正确性**
    - **Validates: Requirements 5.2, 5.4**

- [ ] 7. 集成测试和验证
  - [ ] 7.1 手动测试完整刷新流程
    - 测试正常刷新流程
    - 测试冷却期内重复请求
    - 测试连续失败后停止
    - _Requirements: 1.1, 1.2, 4.2, 4.3_

  - [ ] 7.2 验证日志输出正确性
    - 确保不再输出错误的"成功恢复在线状态"
    - 确保失败计数正确记录
    - _Requirements: 5.3_

- [ ] 8. Final Checkpoint - 确保所有测试通过
  - 运行所有测试
  - 确保功能正常
  - 如有问题，询问用户

## Notes

- 任务标记 `*` 的为可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- Checkpoint 任务用于确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
