# 实现计划：启动数据加载优化

## 概述

本实现计划将设计文档中的架构转化为具体的编码任务。实现将按照以下顺序进行：创建核心组件 → 修改现有组件 → 集成测试 → 验证。

## 任务

- [x] 1. 创建 StartupSequenceManager 核心组件
  - [x] 1.1 创建 StartupSequenceManager 类和基础结构
    - 创建 `Sources/Service/StartupSequenceManager.swift` 文件
    - 定义 `StartupPhase` 枚举（idle、loadingLocalData、processingOfflineQueue、syncing、completed、failed）
    - 定义 `StartupState` 和 `StartupError` 数据结构
    - 实现 `@Published` 属性：currentPhase、isCompleted、errorMessage
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 1.2 实现 StartupSequenceManager 的启动序列逻辑
    - 实现 `executeStartupSequence()` 方法
    - 实现 `loadLocalData()` 私有方法
    - 实现 `processOfflineQueue()` 私有方法
    - 实现 `performSync()` 私有方法
    - 确保每个步骤完成后再执行下一步
    - 确保步骤失败时继续执行后续步骤
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ]* 1.3 编写 StartupSequenceManager 属性测试
    - **Property 2: 启动序列顺序正确性**
    - **Property 3: 启动序列错误容忍性**
    - **Validates: Requirements 2.1, 2.2, 2.3**

- [x] 2. 修改 NotesViewModel 数据加载逻辑
  - [x] 2.1 修改 NotesViewModel 初始化和数据加载
    - 添加 `startupManager: StartupSequenceManager` 依赖
    - 添加 `isFirstLaunch: Bool` 属性
    - 修改 `init()` 方法，使用 StartupSequenceManager 执行启动序列
    - 修改 `loadLocalData()` 方法，登录状态下不加载示例数据
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [ ]* 2.2 编写数据加载属性测试
    - **Property 1: 登录状态下始终加载本地数据**
    - **Validates: Requirements 1.1, 1.2, 4.2, 4.3**

  - [x] 2.3 实现登录和Cookie刷新成功处理
    - 实现 `handleLoginSuccess()` 方法
    - 实现 `handleCookieRefreshSuccess()` 方法
    - 在登录成功后清除示例数据并执行完整同步
    - 在Cookie刷新成功后恢复在线状态并执行完整同步
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [ ]* 2.4 编写自动同步触发属性测试
    - **Property 6: 自动同步触发条件**
    - **Validates: Requirements 4.1, 5.1, 5.2**

- [x] 3. 检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

- [ ] 4. 修改 AuthenticationStateManager 支持静默刷新状态
  - [ ] 4.1 添加静默刷新状态属性
    - 添加 `@Published var isRefreshingCookie: Bool` 属性
    - 添加 `@Published var refreshStatusMessage: String` 属性
    - 实现 `attemptSilentRefreshWithStatus()` 方法
    - 在静默刷新时显示"正在刷新登录状态"提示
    - _Requirements: 8.2, 8.3, 8.4, 8.5_

  - [ ]* 4.2 编写静默刷新Cookie属性测试
    - **Property 10: 静默刷新Cookie流程**
    - **Validates: Requirements 8.2, 8.4**

- [ ] 5. 修改离线队列处理逻辑
  - [ ] 5.1 优化 OfflineOperationProcessor 启动时处理
    - 确保只在网络可用且Cookie有效时处理队列
    - 确保处理失败的操作保留在队列中
    - 确保处理完成后更新本地数据库
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ]* 5.2 编写离线队列处理属性测试
    - **Property 4: 离线队列处理条件**
    - **Property 5: 离线队列处理后数据一致性**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

- [ ] 6. 修改 SyncService 同步锁和状态管理
  - [ ] 6.1 实现同步锁机制
    - 添加同步进行中标志
    - 在同步进行中阻止新的同步请求
    - 同步完成后更新 lastSyncTime 和 syncTag
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [ ]* 6.2 编写同步锁属性测试
    - **Property 7: 同步锁机制**
    - **Property 8: 同步状态更新**
    - **Validates: Requirements 6.1, 6.2**

- [ ] 7. 检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

- [ ] 8. 实现错误恢复机制
  - [ ] 8.1 实现网络错误时离线队列添加
    - 在网络请求失败时将操作添加到离线队列
    - 实现重试限制逻辑
    - 超过最大重试次数时标记为失败
    - _Requirements: 8.1, 8.7_

  - [ ]* 8.2 编写错误恢复属性测试
    - **Property 9: 网络错误时离线队列添加**
    - **Property 12: 重试限制**
    - **Validates: Requirements 8.1, 8.7**

  - [ ] 8.3 实现网络恢复后自动处理
    - 监听网络状态变化
    - 网络恢复时自动处理离线队列
    - _Requirements: 8.6_

  - [ ]* 8.4 编写网络恢复属性测试
    - **Property 11: 网络恢复后自动处理**
    - **Validates: Requirements 8.6**

- [ ] 9. 实现数据加载状态指示
  - [ ] 9.1 添加状态指示UI支持
    - 在 NotesViewModel 中添加状态指示属性
    - 添加加载指示器状态
    - 添加离线队列处理进度状态
    - 添加同步进度和状态消息
    - 添加离线模式指示
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 10. 集成和连接
  - [ ] 10.1 连接所有组件
    - 在 AppDelegate 或 AppStateManager 中初始化 StartupSequenceManager
    - 连接 NotesViewModel 与 StartupSequenceManager
    - 连接 AuthenticationStateManager 的登录/刷新成功回调
    - 连接 OnlineStateManager 的网络状态变化回调
    - _Requirements: 2.1, 5.1, 5.2, 8.6_

  - [ ]* 10.2 编写集成测试
    - 测试完整启动流程
    - 测试登录后同步流程
    - 测试网络恢复后处理流程
    - _Requirements: 2.1, 5.1, 8.6_

- [ ] 11. 最终检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

## 备注

- 标记为 `*` 的任务为可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- 检查点确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
