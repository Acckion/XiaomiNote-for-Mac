# 需求文档

## 简介

本文档定义了原生编辑器内容持久化和同步功能的需求。当前原生编辑器存在无法保存修改内容的问题，需要完善一整套关于加载、保存、上传、离线操作等的逻辑，确保原生编辑器与 Web 编辑器具有同等的数据持久化能力。

## 术语表

- **Native_Editor**: 使用 SwiftUI 和 NSTextView 实现的原生富文本编辑器
- **Web_Editor**: 基于 WebKit 的 Web 编辑器
- **NativeEditorContext**: 原生编辑器的状态管理上下文
- **XiaoMiFormatConverter**: 小米笔记 XML 格式与 NSAttributedString 之间的转换器
- **UnifiedEditorWrapper**: 统一编辑器包装器，负责在原生编辑器和 Web 编辑器之间切换
- **NotesViewModel**: 笔记视图模型，负责笔记的业务逻辑和状态管理
- **LocalStorageService**: 本地存储服务，负责 SQLite 数据库操作
- **SyncService**: 同步服务，负责本地与云端的数据同步
- **OfflineOperationQueue**: 离线操作队列，管理网络断开时的操作

## 需求

### 需求 1：内容加载

**用户故事：** 作为用户，我希望在选择笔记时能够正确加载笔记内容到原生编辑器，以便我可以查看和编辑笔记。

#### 验收标准

1. WHEN 用户选择一个笔记 THEN Native_Editor SHALL 从数据库加载笔记的 XML 内容并转换为 NSAttributedString 显示
2. WHEN 笔记内容包含图片附件 THEN Native_Editor SHALL 正确渲染图片并支持本地缓存加载
3. WHEN 笔记内容包含音频附件 THEN Native_Editor SHALL 正确渲染音频播放器组件
4. WHEN 笔记内容包含复选框 THEN Native_Editor SHALL 正确渲染可交互的复选框并保留勾选状态
5. WHEN 笔记内容包含格式化文本（加粗、斜体、下划线等） THEN Native_Editor SHALL 正确渲染所有格式
6. WHEN 用户快速切换笔记 THEN Native_Editor SHALL 优先从内存缓存加载以实现无延迟切换
7. IF 内存缓存未命中 THEN Native_Editor SHALL 从数据库异步加载完整内容

### 需求 2：内容保存

**用户故事：** 作为用户，我希望在编辑笔记后内容能够自动保存，以便我不会丢失任何修改。

#### 验收标准

1. WHEN 用户在 Native_Editor 中修改内容 THEN System SHALL 将 NSAttributedString 转换为 XML 格式并触发保存流程
2. WHEN 内容发生变化 THEN System SHALL 立即更新内存缓存（Tier 0，<1ms）
3. WHEN 内容发生变化 THEN System SHALL 异步保存到本地数据库（Tier 2，防抖 300ms）
4. WHEN 本地保存完成 THEN System SHALL 更新保存状态指示器为"已保存"
5. WHEN 保存过程中发生错误 THEN System SHALL 显示错误状态并保留用户编辑的内容
6. WHEN 用户切换笔记 THEN System SHALL 先保存当前笔记再切换到新笔记
7. WHEN 用户切换文件夹 THEN System SHALL 先保存当前编辑内容再执行切换

### 需求 3：云端同步

**用户故事：** 作为用户，我希望编辑的内容能够同步到云端，以便我可以在其他设备上访问最新内容。

#### 验收标准

1. WHEN 本地保存完成 THEN System SHALL 调度云端上传任务（延迟 3 秒，防止频繁上传）
2. WHEN 网络可用且 Cookie 有效 THEN System SHALL 将笔记内容上传到小米笔记服务器
3. WHEN 云端同步成功 THEN System SHALL 更新本地笔记的 syncTag 和 updatedAt
4. IF 云端同步失败 THEN System SHALL 将操作加入离线队列等待重试
5. WHEN 网络恢复 THEN System SHALL 自动处理离线队列中的待同步操作

### 需求 4：离线操作

**用户故事：** 作为用户，我希望在离线状态下也能编辑笔记，并在网络恢复后自动同步。

#### 验收标准

1. WHEN 网络不可用 THEN System SHALL 将编辑操作保存到离线队列
2. WHEN 离线队列中有待处理操作 THEN System SHALL 在 UI 中显示待同步状态
3. WHEN 网络恢复 THEN System SHALL 按顺序处理离线队列中的操作
4. IF 离线操作与云端冲突 THEN System SHALL 使用时间戳比较策略解决冲突
5. WHEN 离线操作处理完成 THEN System SHALL 更新 UI 状态并清除队列

### 需求 5：格式转换

**用户故事：** 作为用户，我希望在原生编辑器中编辑的格式能够正确保存和恢复。

#### 验收标准

1. THE XiaoMiFormatConverter SHALL 支持 NSAttributedString 到 XML 的双向转换
2. WHEN 转换包含粗体文本 THEN Converter SHALL 生成 `<b>` 标签并正确解析
3. WHEN 转换包含斜体文本 THEN Converter SHALL 生成 `<i>` 标签并正确解析
4. WHEN 转换包含下划线文本 THEN Converter SHALL 生成 `<u>` 标签并正确解析
5. WHEN 转换包含删除线文本 THEN Converter SHALL 生成 `<delete>` 标签并正确解析
6. WHEN 转换包含高亮文本 THEN Converter SHALL 生成 `<background>` 标签并正确解析
7. WHEN 转换包含标题 THEN Converter SHALL 生成对应的 `<size>`、`<mid-size>` 或 `<h3-size>` 标签
8. WHEN 转换包含复选框 THEN Converter SHALL 生成 `<input type="checkbox">` 标签并保留 checked 属性
9. WHEN 转换包含图片 THEN Converter SHALL 生成 `<img>` 标签并保留 fileId 属性
10. WHEN 转换包含音频 THEN Converter SHALL 生成 `<sound>` 标签并保留 fileId 属性
11. FOR ALL 有效的 XML 内容，解析后再导出 SHALL 产生等效的 XML（往返一致性）

### 需求 6：状态同步

**用户故事：** 作为用户，我希望编辑器的状态（如保存状态、格式状态）能够正确显示。

#### 验收标准

1. WHEN 内容未保存 THEN System SHALL 显示"未保存"状态指示器（红色）
2. WHEN 正在保存 THEN System SHALL 显示"保存中..."状态指示器（黄色）
3. WHEN 保存完成 THEN System SHALL 显示"已保存"状态指示器（绿色）
4. WHEN 保存失败 THEN System SHALL 显示"保存失败"状态指示器（红色）并允许查看错误详情
5. WHEN 用户选择文本 THEN Native_Editor SHALL 更新工具栏按钮状态以反映当前格式
6. WHEN 用户移动光标 THEN Native_Editor SHALL 检测当前位置的格式并更新状态

### 需求 7：编辑器切换

**用户故事：** 作为用户，我希望在原生编辑器和 Web 编辑器之间切换时内容不会丢失。

#### 验收标准

1. WHEN 用户从 Web_Editor 切换到 Native_Editor THEN System SHALL 保存当前内容并在新编辑器中加载
2. WHEN 用户从 Native_Editor 切换到 Web_Editor THEN System SHALL 导出 XML 并在 Web 编辑器中加载
3. WHEN 切换编辑器 THEN System SHALL 保持笔记的选中状态不变
4. WHEN 切换编辑器 THEN System SHALL 注册对应编辑器的格式提供者到 FormatStateManager

### 需求 8：录音模板

**用户故事：** 作为用户，我希望在原生编辑器中录音后能够正确保存录音附件。

#### 验收标准

1. WHEN 用户开始录音 THEN Native_Editor SHALL 插入录音模板占位符
2. WHEN 录音完成 THEN System SHALL 将占位符更新为实际的音频附件
3. WHEN 更新录音模板 THEN System SHALL 立即触发保存以确保内容持久化
4. WHEN 导出包含录音的内容 THEN Converter SHALL 生成正确的 `<sound>` 标签

### 需求 9：错误处理

**用户故事：** 作为用户，我希望在保存失败时能够得到明确的提示并保留我的编辑内容。

#### 验收标准

1. IF 本地保存失败 THEN System SHALL 显示错误提示并保留编辑内容
2. IF 云端同步失败 THEN System SHALL 将操作加入离线队列并显示待同步状态
3. IF 格式转换失败 THEN System SHALL 记录错误日志并尝试使用原始内容
4. WHEN 发生错误 THEN System SHALL 提供重试选项或手动保存按钮
