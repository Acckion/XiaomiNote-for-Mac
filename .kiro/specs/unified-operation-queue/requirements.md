# 需求文档

## 简介

本文档描述了统一操作队列功能的需求。该功能通过创建 `NoteOperationCoordinator` 来协调所有笔记操作（本地保存、云端上传、定时同步），防止竞态条件导致的格式丢失和内容被还原问题。

## 问题分析

当前系统存在以下竞态条件：

1. **保存-同步竞态**：用户编辑并保存（XML 长度 367）→ 定时同步从云端获取旧数据（XML 长度 346）→ 同步覆盖本地数据库 → `loadLocalDataAfterSync()` 触发编辑器重新加载旧内容 → 格式丢失

2. **现有保护机制的缺陷**：
   - `loadLocalDataAfterSync()` 检查 `hasUnsavedChanges`，但保存完成后该标志已清除
   - `SyncService` 比较时间戳，但本地保存后云端尚未更新，云端时间戳仍是旧的
   - 3秒上传延迟期间，定时同步可能已经覆盖了本地内容

## 术语表

- **Note_Operation_Coordinator**: 笔记操作协调器，协调保存、上传、同步操作的中央控制器
- **Pending_Upload_Registry**: 待上传注册表，记录有本地修改等待上传的笔记 ID 和时间戳
- **Active_Editing_Note**: 活跃编辑笔记，当前正在原生编辑器中打开的笔记
- **Sync_Service**: 同步服务，负责定时从云端拉取笔记更新
- **Local_Save_Timestamp**: 本地保存时间戳，记录笔记最后一次本地保存的时间
- **Native_Editor**: 原生编辑器，基于 NSTextView 的富文本编辑器

## 需求

### 需求 1：待上传注册表

**用户故事：** 作为用户，我希望系统能追踪哪些笔记有本地修改等待上传，以防止同步覆盖我的编辑。

#### 验收标准

1. WHEN 用户编辑笔记并触发本地保存，THE Note_Operation_Coordinator SHALL 将笔记 ID 和保存时间戳注册到 Pending_Upload_Registry
2. WHEN 云端上传成功，THE Note_Operation_Coordinator SHALL 从 Pending_Upload_Registry 移除该笔记
3. WHEN 云端上传失败，THE Note_Operation_Coordinator SHALL 保留 Pending_Upload_Registry 中的记录并将操作加入离线队列
4. WHEN 应用启动，THE Note_Operation_Coordinator SHALL 从持久化存储恢复 Pending_Upload_Registry

### 需求 2：同步保护机制

**用户故事：** 作为用户，我希望定时同步不会覆盖我刚刚保存但尚未上传的内容。

#### 验收标准

1. WHEN Sync_Service 获取到笔记更新，THE Sync_Service SHALL 检查该笔记是否在 Pending_Upload_Registry 中
2. WHEN 笔记在 Pending_Upload_Registry 中，THE Sync_Service SHALL 跳过该笔记的内容更新
3. WHEN 笔记在 Pending_Upload_Registry 中且云端时间戳早于 Local_Save_Timestamp，THE Sync_Service SHALL 完全跳过该笔记
4. WHEN 笔记不在 Pending_Upload_Registry 中，THE Sync_Service SHALL 正常执行同步逻辑

### 需求 3：活跃编辑保护

**用户故事：** 作为用户，我希望正在编辑的笔记不会被任何外部操作覆盖。

#### 验收标准

1. WHEN 用户在 Native_Editor 中打开笔记进行编辑，THE Note_Operation_Coordinator SHALL 将该笔记标记为 Active_Editing_Note
2. WHILE 笔记是 Active_Editing_Note，THE Sync_Service SHALL 跳过该笔记的内容更新
3. WHEN 用户切换到其他笔记，THE Note_Operation_Coordinator SHALL 清除原笔记的 Active_Editing_Note 标记
4. WHEN Native_Editor 有未保存更改，THE Note_Operation_Coordinator SHALL 阻止同步更新 selectedNote

### 需求 4：上传调度优化

**用户故事：** 作为用户，我希望我的编辑能尽快上传到云端，减少被同步覆盖的风险。

#### 验收标准

1. WHEN 本地保存完成，THE Note_Operation_Coordinator SHALL 立即检查网络状态并尝试上传
2. WHEN 网络可用且无其他上传任务，THE Note_Operation_Coordinator SHALL 在 1 秒内开始上传
3. WHEN 用户连续编辑，THE Note_Operation_Coordinator SHALL 使用防抖机制合并上传请求
4. WHEN 上传成功，THE Note_Operation_Coordinator SHALL 更新本地笔记的云端同步时间戳

### 需求 5：冲突检测与解决

**用户故事：** 作为用户，我希望系统能智能处理本地和云端的冲突，始终保留我最新的修改。

#### 验收标准

1. WHEN 同步获取到笔记更新，THE Note_Operation_Coordinator SHALL 比较云端时间戳与 Local_Save_Timestamp
2. WHEN Local_Save_Timestamp 较新，THE Note_Operation_Coordinator SHALL 保留本地内容并触发上传
3. WHEN 云端时间戳较新且笔记不在 Pending_Upload_Registry 中，THE Note_Operation_Coordinator SHALL 使用云端内容更新本地
4. WHEN 云端时间戳较新但笔记在 Pending_Upload_Registry 中，THE Note_Operation_Coordinator SHALL 保留本地内容

### 需求 6：状态持久化

**用户故事：** 作为用户，我希望应用重启后，待上传的笔记仍能正确同步。

#### 验收标准

1. WHEN 笔记加入 Pending_Upload_Registry，THE Note_Operation_Coordinator SHALL 将状态持久化到数据库
2. WHEN 应用启动，THE Note_Operation_Coordinator SHALL 从数据库恢复 Pending_Upload_Registry
3. WHEN 网络恢复，THE Note_Operation_Coordinator SHALL 处理 Pending_Upload_Registry 中的所有笔记
4. IF 持久化状态与实际状态不一致，THEN THE Note_Operation_Coordinator SHALL 以本地数据库内容为准
