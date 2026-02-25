# 更新日志

本文件记录项目的所有重要变更。格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [Unreleased]

### 新增
- 独立笔记编辑器窗口（spec-107）：支持在新窗口中打开特定笔记进行编辑，包含编辑器区域和 unified 工具栏，支持重复打开检测

### 移除
- 过渡网络链路清理：删除 NetworkClient/NetworkClientProtocol 过渡抽象及其唯一消费者 DefaultAuthenticationService/DefaultImageService，清理 AuthenticationServiceProtocol/ImageServiceProtocol 无消费者协议，移除 Authentication/Image 空目录

### 重构
- 菜单 Command 化迁移（spec-124）：将 MenuActionHandler（1,317 行）拆分为 7 个领域 Command 文件（FormatCommands、FileCommands、WindowCommands、ViewCommands、UtilityCommands、NoteCommands、SyncCommands），共约 73 个 Command struct 通过 CommandDispatcher 统一调度，提取 MenuStateManager 分离菜单状态管理职责，AppDelegate @objc 方法简化为单行 dispatch 调用，删除 MenuActionHandler
- OperationProcessor 拆分（spec-122）：将 OperationProcessor（1,441 行）拆分为调度层 + handler 分发模式，定义 OperationHandler 协议和 OperationResponseParser 工具结构体，按操作域拆出 NoteOperationHandler、FileOperationHandler、FolderOperationHandler 三个 actor，OperationProcessor 瘦身至 478 行纯调度层，公共接口不变，外部调用方零改动
- 菜单命令链路收敛（spec-120）：删除编辑操作空壳方法（undo/redo/cut/copy/paste/selectAll）改走 NSResponder 链，填实格式操作方法统一调用 FormatStateManager，引入 AppCommand 协议和 CommandDispatcher 统一调度业务操作（新建/删除笔记、新建文件夹、同步、分享、设置窗口），精简 MenuActionHandler 转发层注入 CommandDispatcher
- 调试基础设施清理（spec-119）：移除 NativeEditorLogger（800+ 行）、NativeEditorMetrics（400+ 行）、NativeEditorErrorHandler（490+ 行）、PerformanceMonitor（130 行）、ParagraphManagerDebugView、ParagraphDebugWindowController，统一使用 LogService.shared 记录日志，提取 NativeEditorError 枚举到独立文件，单例数量从 15 个减少到 12 个
- 剩余单例清理（spec-118）：创建 AudioModule 工厂管理 4 个音频类，重构 12 个纠缠单例为构造器注入，消除约 271 处外部 `.shared` 引用，改造 AppDelegate 启动链为 NetworkModule → SyncModule → EditorModule → AudioModule → AppCoordinator，ViewOptionsManager 改用 EnvironmentObject 注入，最终仅保留 15 个基础设施类的 `static let shared`
- 构造器注入 + EditorModule 工厂（spec-117）：创建 EditorModule 工厂集中构建编辑器层依赖图，重构 17 个编辑器层类（PerformanceCache、FontSizeManager、EditorConfigurationManager、XMLNormalizer、PerformanceMonitor、TypingOptimizer、PasteboardManager、XiaoMiFormatConverter、CustomRenderer、SpecialElementFormatHandler、UnifiedFormatManager、SafeRenderer、NativeEditorInitializer、EditorRecoveryManager、ImageStorageManager、AttachmentSelectionManager、AttachmentKeyboardHandler、FormatStateManager、CursorFormatManager）支持构造器注入，消除类内部硬编码的 .shared 交叉引用，修改 AppCoordinator/AppDelegate 接入 EditorModule，保留 3 个调试工具类（NativeEditorLogger、NativeEditorMetrics、NativeEditorErrorHandler）单例不变，保留 .shared 供未重构模块过渡期使用
- 构造器注入 + SyncModule 工厂（spec-116）：创建 SyncModule 工厂集中构建同步层依赖图，重构 8 个同步层类（LocalStorageService、UnifiedOperationQueue、IdMappingRegistry、OperationProcessor、OnlineStateManager、SyncEngine、SyncGuard、SyncStateManager）支持构造器注入，消除 OperationProcessor 内部 13 处 IdMappingRegistry.shared 和 SyncEngine 内部 2 处 OperationProcessor.shared 硬编码引用，修改 AppCoordinator/AppDelegate 接入 SyncModule，保留 .shared 供未重构模块过渡期使用
- 构造器注入 + 模块工厂（spec-114）：删除未使用的 DIContainer/ServiceLocator 死代码，创建 NetworkModule 工厂集中构建网络层依赖图，重构 7 个网络层类（NetworkRequestManager、APIClient、NoteAPI、FolderAPI、FileAPI、SyncAPI、UserAPI）支持构造器注入，修改 AppCoordinator/AppDelegate/AuthState 使用注入实例，保留 .shared 供未重构模块过渡期使用
- @unchecked Sendable 清理（spec-112）：将项目中 30+ 处 @unchecked Sendable 减少到 5 处，12 个类改为 struct、7 个改为 actor、3 个添加 @MainActor、Folder.rawData 改为 Sendable 类型，保留的 5 处（DatabaseService、UnifiedOperationQueue、IdMappingRegistry、DIContainer、ServiceLocator）补充线程安全文档
- Web 编辑器残留清理（spec-110）：删除 EditorProtocol/EditorFactory/EditorType/EditorPreferencesService 抽象层，移除所有 isUsingNativeEditor 条件判断，清理 HTML 数据通道残留，简化 EditorSettingsView 和 NativeEditorInitializer
- SyncEngine 拆分重构（spec-108）：将 SyncEngine.swift（1,596 行）按职责拆分为 5 个文件（1 核心 + 4 extension），核心文件瘦身至 ~380 行，提升代码可维护性
- XiaoMiFormatConverter 清理重构（spec-107）：删除旧管道代码（2,052 行缩减至 112 行），收拢转换模块到 `Sources/Service/Editor/FormatConverter/` 子目录
- 废弃代码清理（spec-106）：删除 MiNoteService 废弃文件、清理 deprecated 方法、统一 print() 为 LogService、修正 error domain 字符串、更新过时注释引用和项目文档
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
