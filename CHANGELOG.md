# 更新日志

本文件记录项目的所有重要变更。格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [Unreleased]

### 新增
- 独立笔记编辑器窗口（spec-107）：支持在新窗口中打开特定笔记进行编辑，包含编辑器区域和 unified 工具栏，支持重复打开检测

### 重构
- MainWindowController 拆分重构（spec-105）：将 MainWindowController.swift（3,239 行）拆分为 7 个文件（1 核心 + 6 extension），提升代码可维护性
- 编辑器桥接层重构（spec-103）：
  - NativeEditorView.swift（2,423 行）按职责拆分为 4 个文件：NativeEditorView（纯 NSViewRepresentable）、NativeEditorCoordinator（Delegate + 内容同步）、CoordinatorFormatApplier（格式应用）、NativeTextView（自定义 NSTextView）
  - NativeEditorContext.swift（1,827 行）按职责拆分为 4 个文件：NativeEditorContext（核心状态 + 格式入口 + XML）、EditorEnums（枚举定义）、EditorContentManager（内容管理 + 录音模板）、EditorFormatDetector（格式检测）
  - 纯代码组织重构，不改变运行时行为，extension 方法编译时静态分派
- 操作队列重构与优化（spec-104）：
  - 清理 NoteServiceProtocol 体系和旧 ViewModel 死代码
  - 新增文件上传基础设施（audioUpload 类型、FileUploadOperationData、pending_uploads 目录管理）
  - 统一写入出口：图片/音频离线插入通过 SyncEngine 队列化
  - 操作队列类型安全化：新增 OperationData 类型安全解析，收敛便捷入队方法
  - 移除 OperationProcessor 的 @MainActor 依赖，消除并发模型传染
  - 添加 IdMappingRegistry 和 UnifiedOperationQueue 的 NSLock 设计决策文档

### 修复
- 修复图片上传时文件扩展名不一致导致本地文件丢失
- 修复图片上传成功后 XML 未更新 fileId 的时序问题
- 修复离线创建笔记后操作队列使用过期临时 ID 及执行顺序问题
- 修复插入图片后不渲染需要点击编辑器才显示的问题
- 修复插入图片/音频后 XML 未即时保存导致上传后 fileId 替换失败
- 修复离线创建笔记插入图片后云端仍使用临时 fileId（noteCreate 和 cloudUpload 等待文件上传完成、processQueue 二次检查新入队操作）
- 修复云端上传冲突重试不检查结果导致后续上传持续冲突，以及 noteCreate 保存覆盖已替换的正式 fileId
- MiNoteService 网络层重构（spec-102）：将 2,029 行的 MiNoteService 按功能领域拆分为 APIClient、NoteAPI、FolderAPI、FileAPI、SyncAPI、UserAPI、ResponseParser 7 个独立类，MiNoteService 保留为 deprecated Facade 转发层，所有调用方已迁移到新 API 类
- Cookie 自动刷新重构：NetworkRequestManager 统一拦截 HTTP 401，自动通过 PassToken 刷新 Cookie 并重试
- MiNoteService 所有 API 方法迁移到 performRequest/NetworkRequestManager，消除直接 URLSession 调用
- 移除 MiNoteService 中无效的 onCookieExpired 回调和 cookieExpiredFlag 机制
- OperationProcessor 认证错误改为可重试，走标准指数退避重试路径

## [3.4.0] - 2026-01-18

### 新增
- 智能内容变化检测：新增 XMLNormalizer 组件，实现基于语义的内容比较
- 时间戳精确控制：只有在实际编辑笔记时才更新时间戳
- 新增 27 个单元测试，覆盖各种 XML 格式场景

### 优化
- XML 规范化耗时 < 10ms，不影响用户体验
- 添加详细的性能监控日志
- 优化内容比较算法

## [3.3.0] - 2026-01-16

### 优化
- 统一操作队列架构重构，提升同步可靠性
- 优化笔记选择和时间戳处理逻辑
- 改进启动数据加载流程
- 完善视图状态同步机制
- 优化原生编辑器格式应用性能
- 改进中文输入法兼容性
- 完善附件选择机制
- 优化列表格式处理
- 优化笔记列表排序和显示
- 改进工具栏可见性管理
- 完善格式菜单状态同步

## [3.0.0] - 2026-01-01

### 新增
- 原生富文本编辑器（NSTextView），替代 Web 编辑器作为默认编辑器
- 完整的格式状态同步机制
- 图片和语音附件支持
- 复选框同步功能
- 语音录制功能
- 语音上传到云端
- 语音播放器
- 画廊视图模式
- 笔记列表排序和日期分组
- 笔记列表移动动画
- 完整的显示菜单（视图模式、缩放、工具栏控制）
- 启动序列管理器

### 修复
- 语音格式兼容性问题

### 优化
- Cookie 自动刷新机制
- 视图状态同步
- 视图状态持久化

## [2.3.0-beta] - 2025-12-15

### 新增
- 原生笔记编辑器（实验性）

## [2.2.0] - 2025-12-01

### 新增
- 轻量化同步功能
- 在线状态管理和 Cookie 自动刷新
- 查找和替换功能

## [2.1.0] - 2025-11-15

### 优化
- 颜色主题系统
- 项目结构和构建配置

## [2.0.0] - 2025-11-01

### 新增
- AppKit+SwiftUI 混合架构
- 完整的 macOS 菜单系统
- 多窗口管理

## [1.2.0] - 2025-10-15

### 新增
- 内存缓存管理器
- 保存队列管理器

### 优化
- 笔记切换性能

## [1.1.0] - 2025-10-01

### 变更
- 从纯 SwiftUI 迁移到 AppKit+SwiftUI 混合架构

### 新增
- 离线操作队列

## [1.0.0] - 2025-09-15

### 新增
- 初始版本
- 基本的笔记编辑和同步功能
