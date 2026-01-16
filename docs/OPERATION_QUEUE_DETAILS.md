
操作队列架构概述
你的项目有三个核心队列组件协同工作：

1. NoteOperationCoordinator（核心协调器）
这是一个 Swift Actor，负责协调所有笔记操作：

保存流程：

用户编辑 → saveNote() → 本地保存到 SQLite → 注册到 PendingUploadRegistry → 触发 1 秒防抖上传
防抖机制：

连续保存会取消之前的上传任务，只保留最后一次
1 秒内无新保存才真正触发上传
活跃编辑保护：

activeEditingNoteId 追踪当前正在编辑的笔记
正在编辑的笔记会被同步跳过
2. PendingUploadRegistry（待上传注册表）
追踪哪些笔记有本地修改等待上传：

数据结构：

noteId → { localSaveTimestamp, registeredAt }
生命周期：

本地保存成功 → 注册
云端上传成功 → 注销
上传失败 → 保留（等待重试）
持久化：

存储在 SQLite 的 pending_uploads 表
应用重启后自动恢复
3. OfflineOperationQueue（离线操作队列）
管理所有待执行的云端操作：

操作类型：

createNote、updateNote、deleteNote
createFolder、renameFolder、deleteFolder
uploadImage
优先级：

删除操作：优先级 3（最高）
更新/重命名：优先级 2
创建/上传：优先级 1
操作合并规则
OfflineOperationQueue.deduplicateAndMerge() 实现了智能合并：

新操作	已有操作	合并结果
createNote	updateNote	合并为 createNote（使用最新内容）
updateNote	createNote	合并为 createNote（使用最新内容）
updateNote	updateNote	只保留时间戳较新的那个
deleteNote	任何操作	清除所有旧操作，只保留 deleteNote
createNote	deleteNote	两个都删除（创建+删除 = 无操作）
updateNote	deleteNote	忽略 updateNote，保留 deleteNote
同步保护机制
SyncProtectionFilter.shouldSkipSync() 决定是否跳过同步：

跳过条件（按优先级）：

笔记正在编辑（isNoteActivelyEditing）→ 跳过
笔记在待上传列表中 → 跳过（用户优先策略）
本地时间戳 ≥ 云端时间戳 → 跳过
冲突解决策略：

正在编辑 → keepLocal
在待上传列表 → keepLocal（无论云端是否更新）
不在待上传列表 → useCloud
典型场景流程
场景 1：用户编辑并保存

编辑 → saveNote() → 本地保存 → 注册 PendingUpload → 1秒后 → 添加到 OfflineQueue → 上传 → 成功 → 注销 PendingUpload
场景 2：保存后立即触发同步

保存完成 → 定时同步触发 → SyncProtectionFilter 检查 → 发现在 PendingUpload 中 → 跳过该笔记
场景 3：切换笔记

切换 → saveNoteImmediately() → 取消防抖 → 立即保存 → 立即上传 → 设置新的 activeEditingNoteId
场景 4：离线编辑后网络恢复

离线编辑 → 保存到本地 → 注册 PendingUpload → 添加到 OfflineQueue
网络恢复 → OfflineOperationProcessor 处理队列 → 上传成功 → 注销 PendingUpload
关键设计决策
Local-First：本地保存立即生效，网络操作异步
用户优先：即使云端更新，待上传的笔记也保留本地版本
Actor 隔离：NoteOperationCoordinator 使用 Actor 确保线程安全
持久化恢复：PendingUploadRegistry 和 OfflineOperationQueue 都持久化到数据库
这套机制有效防止了"保存后被同步覆盖"的竞态条件问题。