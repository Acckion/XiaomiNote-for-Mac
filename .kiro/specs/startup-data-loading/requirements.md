# 需求文档

## 简介

本文档定义了应用启动时数据加载、同步和离线操作的全面优化需求。核心目标是确保：
1. 登录状态下始终优先加载本地数据库内容（无论网络或 Cookie 状态）
2. 启动时按正确顺序执行：加载本地数据 → 处理离线队列 → 执行完整同步
3. 登录/刷新 Cookie 后自动触发完整同步
4. 提供清晰的状态指示和错误处理

## 术语表

- **System**: 小米笔记 macOS 应用程序
- **Local_Database**: 本地 SQLite 数据库，存储笔记和文件夹数据
- **Offline_Queue**: 离线操作队列，存储网络不可用时的待同步操作
- **Offline_Processor**: 离线操作处理器，负责执行离线队列中的操作
- **Full_Sync**: 完整同步，从服务器获取所有笔记数据并覆盖本地
- **Incremental_Sync**: 增量同步，只同步自上次同步以来的更改
- **Login_State**: 登录状态，表示用户是否已登录小米账号（本地存储有 Cookie）
- **Cookie_Valid**: Cookie 有效性，表示存储的 Cookie 是否仍然有效
- **Sample_Data**: 示例数据，用于未登录状态下展示的测试笔记
- **Sync_Status**: 同步状态，包含上次同步时间和 syncTag
- **Startup_Sequence**: 启动序列，应用启动时的操作执行顺序

## 需求

### 需求 1：启动时数据加载策略

**用户故事：** 作为用户，我希望应用启动时能够立即看到我的笔记内容，即使网络不可用或 Cookie 已过期，这样我可以在任何情况下访问我的笔记。

#### 验收标准

1. WHEN 应用启动且用户处于 Login_State THEN THE System SHALL 首先从 Local_Database 加载笔记和文件夹数据，无论网络状态或 Cookie_Valid 状态如何
2. WHEN 应用启动且用户处于 Login_State 且 Local_Database 为空 THEN THE System SHALL 显示空列表而非 Sample_Data
3. WHEN 应用启动且用户未处于 Login_State THEN THE System SHALL 加载 Sample_Data 作为演示内容
4. WHEN 从 Local_Database 加载数据完成 THEN THE System SHALL 立即更新 UI 显示笔记列表
5. WHEN 加载本地数据时发生错误 THEN THE System SHALL 记录错误日志并显示空列表

### 需求 2：启动序列管理

**用户故事：** 作为用户，我希望应用启动时能够按正确的顺序处理数据，确保我的离线编辑不会丢失，同时能获取最新的云端内容。

#### 验收标准

1. WHEN 应用启动且用户处于 Login_State THEN THE System SHALL 按以下顺序执行：加载本地数据 → 处理离线队列 → 执行完整同步
2. WHEN 执行 Startup_Sequence 时 THEN THE System SHALL 确保每个步骤完成后再执行下一步
3. WHEN Startup_Sequence 中任一步骤失败 THEN THE System SHALL 记录错误并继续执行后续步骤
4. WHEN Startup_Sequence 完成 THEN THE System SHALL 发送启动完成通知

### 需求 3：启动时离线队列处理

**用户故事：** 作为用户，我希望应用启动时能够自动处理之前未完成的操作，这样我不会丢失任何编辑内容。

#### 验收标准

1. WHEN 应用启动且 Offline_Queue 不为空且网络可用且 Cookie_Valid THEN THE System SHALL 在同步前先处理 Offline_Queue 中的待处理操作
2. WHEN 处理 Offline_Queue 时网络不可用 THEN THE System SHALL 保留队列中的操作并跳过此步骤
3. WHEN 处理 Offline_Queue 时 Cookie 已过期 THEN THE System SHALL 保留队列中的操作并跳过此步骤
4. WHEN Offline_Queue 处理完成 THEN THE System SHALL 更新 Local_Database 中受影响的笔记
5. WHEN Offline_Queue 中有操作失败 THEN THE System SHALL 保留失败的操作在队列中以便后续重试

### 需求 4：启动时自动同步

**用户故事：** 作为用户，我希望应用启动时能够自动同步最新的笔记内容，这样我可以看到在其他设备上的更改。

#### 验收标准

1. WHEN 应用启动且用户处于 Login_State 且网络可用且 Cookie_Valid THEN THE System SHALL 在处理离线队列后自动执行一次 Full_Sync
2. WHEN 应用启动且用户处于 Login_State 且网络不可用 THEN THE System SHALL 跳过同步并仅显示本地数据
3. WHEN 应用启动且用户处于 Login_State 且 Cookie 已过期 THEN THE System SHALL 跳过同步并提示用户刷新 Cookie
4. WHEN Full_Sync 完成 THEN THE System SHALL 更新 Local_Database 并刷新 UI 显示
5. WHEN Full_Sync 失败 THEN THE System SHALL 显示错误信息并保留本地数据不变

### 需求 5：登录后自动同步

**用户故事：** 作为用户，我希望登录账号后能够自动同步笔记内容，这样我可以立即看到云端的笔记。

#### 验收标准

1. WHEN 用户成功登录小米账号 THEN THE System SHALL 自动执行一次 Full_Sync
2. WHEN 用户成功刷新 Cookie THEN THE System SHALL 自动执行一次 Full_Sync
3. WHEN 登录后同步失败 THEN THE System SHALL 显示错误信息并保留本地数据
4. WHEN 登录后同步成功 THEN THE System SHALL 清除之前的 Sample_Data 并显示云端数据

### 需求 6：同步状态管理

**用户故事：** 作为用户，我希望应用能够正确管理同步状态，避免重复同步或同步冲突。

#### 验收标准

1. WHEN 同步正在进行中 THEN THE System SHALL 阻止新的同步请求
2. WHEN 同步完成 THEN THE System SHALL 更新 Sync_Status 中的 lastSyncTime 和 syncTag
3. WHEN 应用启动时存在有效的 Sync_Status THEN THE System SHALL 使用 Incremental_Sync 而非 Full_Sync（仅在非首次启动时）
4. WHEN 首次登录或 Sync_Status 不存在 THEN THE System SHALL 执行 Full_Sync

### 需求 7：数据加载状态指示

**用户故事：** 作为用户，我希望能够看到数据加载和同步的状态，这样我知道应用正在做什么。

#### 验收标准

1. WHEN 应用正在加载本地数据 THEN THE System SHALL 显示加载指示器
2. WHEN 应用正在处理离线队列 THEN THE System SHALL 显示处理进度和当前操作
3. WHEN 应用正在执行同步 THEN THE System SHALL 显示同步进度和状态消息
4. WHEN 同步完成 THEN THE System SHALL 显示同步结果（成功同步的笔记数量或错误信息）
5. WHEN 应用处于离线模式 THEN THE System SHALL 在状态栏显示离线状态指示

### 需求 8：错误恢复机制

**用户故事：** 作为用户，我希望应用能够优雅地处理各种错误情况，不会因为网络问题或服务器错误而丢失我的数据。

#### 验收标准

1. WHEN 网络请求失败 THEN THE System SHALL 将操作添加到 Offline_Queue 以便后续重试
2. WHEN Cookie 过期 THEN THE System SHALL 首先尝试静默刷新 Cookie
3. WHEN 静默刷新 Cookie 正在进行 THEN THE System SHALL 显示"正在刷新登录状态"提示
4. WHEN 静默刷新 Cookie 成功 THEN THE System SHALL 自动恢复在线状态并继续之前的操作
5. WHEN 静默刷新 Cookie 失败 THEN THE System SHALL 显示弹窗提示用户手动刷新 Cookie
6. WHEN 网络恢复 THEN THE System SHALL 自动处理 Offline_Queue 中的待处理操作
7. IF 操作重试超过最大次数 THEN THE System SHALL 将操作标记为失败并通知用户
