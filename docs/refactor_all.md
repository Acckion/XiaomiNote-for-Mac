# MiNoteMac 项目代码审查报告：屎山代码清理清单
我已完成全面的代码审查，识别了多个需要清理的问题区域。以下是详细的发现和建议。

## 一、性能监控代码残留（统一为 PerformanceService）
### 1.1 手动计时代码（CFAbsoluteTimeGetCurrent）
问题：项目中仍有多处使用 CFAbsoluteTimeGetCurrent() 进行手动计时，代码分散且风格不统一。

决策：不直接删除性能监控，而是创建统一的 PerformanceService 基础设施（类似 LogService.shared），采用轻量级方案：只做耗时记录 + 超阈值告警，不做统计聚合和报告生成。各模块的散落计时代码统一迁移到 PerformanceService.shared.measure() 调用。

受影响文件：

XMLNormalizer.swift
（第 30-70 行）

在 normalize() 方法中有 5 处计时代码
记录各个步骤的耗时（图片格式、空标签、空格、属性顺序、属性值）
迁移：替换为 PerformanceService.shared.measure()
XMLRoundtripChecker.swift
（第 60-134 行）

在 runCheck() 方法中有计时代码
迁移：替换为 PerformanceService.shared.measure()
FormatStateSynchronizer.swift
（约 340 行，核心防抖逻辑仅 ~60 行）

performStateUpdate() 中有计时代码
有 performanceMonitoringEnabled 标志和 performanceThreshold 阈值
有大量死代码：StateSyncPerformanceRecord、performanceRecords 数组、getPerformanceStats()、generatePerformanceReport()、checkPerformanceCompliance() 等
迁移：删除所有内置性能监控代码（约 280 行），保留核心防抖逻辑，计时改用 PerformanceService
FormatStateManager.swift
（第 203-300 行）

在 updateStateImmediately() 方法中有计时代码
迁移：替换为 PerformanceService.shared.measure()
NativeEditorView.swift
（第 38-44 行）

在 makeNSView() 方法中有计时代码
迁移：替换为 PerformanceService.shared.measure()

1.2 PerformanceCache 中的死统计代码
问题：PerformanceCache.swift 中的 CacheStatistics 结构体及相关方法（cacheStatistics()、resetStatistics()）从未被 UI 或日志消费，是纯死代码。

迁移：删除 CacheStatistics 及相关代码，缓存命中/未命中计数改为通过 PerformanceService 记录（如需要）

## 二、Combine / NotificationCenter 使用现状评估

背景：spec 109 已将跨层业务通知（Cookie 刷新、启动完成、在线状态变化、操作队列完成等约 25 处）迁移到 EventBus。项目中仍有约 50 个文件 import Combine，约 30 处 NotificationCenter 使用。经评估，绝大部分是合理的，不属于架构债务。

2.1 Combine 的三种用法（均为合理使用，不需要迁移）

用法一：@Published + ObservableObject（SwiftUI 必需，不能动）
SwiftUI 的 @ObservedObject / @StateObject 底层依赖 Combine 的 @Published。
所有 State 对象、AudioPlayerService、AudioRecorderService 等的 @Published 属性都属于此类。
这不是"混用"，这是 SwiftUI 的工作方式，没有替代方案。

用法二：NotificationCenter.default.publisher(for:).sink {}（监听系统通知的标准写法）
NativeEditorCoordinator 监听 NSUndoManagerDidUndoChange、NSWindow.didBecomeKeyNotification 等系统通知。
这是 Apple 推荐的现代写法，比 addObserver + @objc 更简洁安全。
迁移到 EventBus 需要自己包一层转发，没有收益。

用法三：PassthroughSubject / Publisher（SwiftUI-AppKit 桥接通信）
NativeEditorContext 的 formatChangePublisher、specialElementPublisher、indentChangePublisher 等。
SwiftUI View 不能直接调用 NSTextView 方法，需要通过 Publisher 传递指令给 Coordinator。
这是 SwiftUI + AppKit 混合架构的标准桥接模式，不能用 EventBus 替代。

结论：项目中 import Combine 的 50 个文件全部属于以上三种合理用法，不需要迁移。

2.2 NotificationCenter 剩余使用评估

已迁移到 EventBus（spec 109 完成）：
跨层业务通知约 25 处已全部迁移完毕。

保留 NotificationCenter 的合理场景：

Apple 系统通知（不能动）：
- NSWindow.didBecomeKeyNotification
- NSUndoManagerDidUndoChange / NSUndoManagerDidRedoChange
- 其他 AppKit/Foundation 系统通知
这些是 Apple 框架发出的通知，只能用 NotificationCenter 接收。

编辑器内部通信（不建议动）：
- .nativeEditorRequestContentSync（编辑器内容同步请求）
- .nativeEditorFormatCommand（键盘快捷键格式命令）
这些是 NSTextView 体系内的通信，发送方和接收方都在 AppKit 层，用 NotificationCenter 是自然的选择。

可以考虑迁移但收益有限的（音频服务自定义通知）：
- AudioPlayerService：4 个通知（playbackStateDidChange, playbackProgressDidChange, playbackDidFinish, playbackError）
- AudioRecorderService：5 个通知
- AudioUploadService：4 个通知
- AudioPanelStateManager：3 个通知
- AudioAttachment：监听以上通知
这些是项目自定义的 NotificationCenter 通知，理论上可以迁移到 EventBus。
但接收方 AudioAttachment 是 NSTextAttachment 子类（不是 SwiftUI View），生命周期管理比较特殊，迁移风险大于收益。

决策：Combine 和 NotificationCenter 的剩余使用均为合理场景，暂不列入重构范围。
音频服务的 16 个自定义通知作为低优先级备选项，仅在未来音频模块大重构时一并处理。

## 三、@objc 标记过度使用
3.1 @objc 标记分析
问题：AppDelegate 中有 50+ 个 @objc 标记的方法，这些是为了兼容 AppKit 菜单系统。

受影响文件：

AppDelegate.swift
 - 50+ 个 @objc 方法
NotesListViewController.swift
 - 8 个 @objc 方法
SidebarViewController.swift
 - 4 个 @objc 方法
Sources/Window/Controllers/MainWindowController+Search.swift - 2 个 @objc 方法
BaseSheetToolbarDelegate.swift
 - 2 个 @objc 方法
评估：这些 @objc 标记是必要的，用于 AppKit 菜单系统的 selector 调用。不建议删除。

## 四、@unchecked Sendable 和 nonisolated(unsafe) 使用
4.1 @unchecked Sendable 标记
问题：仍有 2 个类使用 @unchecked Sendable，这是 Swift 6 并发的债务。

受影响文件：

DatabaseService.swift
 - 标记为 @unchecked Sendable

原因：使用 dbQueue（并发 DispatchQueue）手动保证线程安全
评估：这是合理的，因为改为 actor 需要所有调用方变为 async，影响面过大
UnifiedOperationQueue.swift
 - 标记为 @unchecked Sendable

原因：使用锁手动保证线程安全
评估：这是合理的
4.2 nonisolated(unsafe) 使用
问题：有多处 nonisolated(unsafe) 使用，这些是 Swift 6 并发的妥协。

受影响文件：

LocalStorageService.swift
 - FileManager.default
AudioRecorderService.swift
 - 5 个通知名称
AudioPlayerService.swift
 - 4 个通知名称
AudioUploadService.swift
 - 4 个通知名称
DefaultAuthenticationService.swift
 - 2 个 Subject
FontSizeManager.swift
 - 4 个常量
ImageAttachment.swift
 - 12 个属性
CustomAttachments.swift
 - 7 个属性
QuoteBlockRenderer.swift
 - 3 个属性
评估：这些使用大多是合理的（全局常量、线程安全的全局对象）。但 ImageAttachment 和 CustomAttachments 中的 nonisolated(unsafe) 属性可能需要重新评估。

## 五、强制解包和强制类型转换
5.1 强制解包（!）
问题：有多处强制解包，这是代码质量问题。

受影响文件：

LocalStorageService.swift
 - 第 15 行

let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
AudioCacheService.swift
 - 第 53 行

let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
XMLRoundtripDebugView.swift
 - 第 121 行

let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
DebugSettingsView.swift
 - 第 792 行

let domain = Bundle.main.bundleIdentifier!
ImageStorageManager.swift
 - 第 34, 52 行

let url = localStorage.getImageURL(fileId: fileId, fileType: "jpg")!
LogService.swift
 - 第 35 行

loggers[module]!
建议：使用 guard let 或 if let 替代强制解包。

5.2 强制类型转换（as!）
问题：有多处强制类型转换。

受影响文件：

ASTToAttributedStringConverter.swift
 - 8 处

return convertTextBlock(block as! TextBlockNode)
PerformanceCache.swift
 - 第 262 行

return style.copy() as! NSParagraphStyle
NewLineHandler.swift
 - 第 406 行

existingStyle.mutableCopy() as! NSMutableParagraphStyle
EditorContentManager.swift
 - 第 46, 78 行

let currentText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
NativeEditorContext.swift
 - 第 387 行

let mutableText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
建议：使用 guard let 或 if let 替代强制类型转换。

6.3 强制 try（try!）
问题：有 2 处强制 try。

受影响文件：

FileUploadOperationData.swift
 - 第 21 行

try! JSONEncoder().encode(self)
OperationData.swift
 - 第 17 行

try! JSONEncoder().encode(self)
建议：这些应该改为 do-catch 或返回 Result 类型。

## 七、ViewModel 与 State 对象的重复
### 7.1 旧 ViewModel 仍在使用
问题：项目已迁移到 State 对象架构，但仍有 2 个 ViewModel 在使用。

受影响文件：

AuthenticationViewModel.swift

使用 Combine 的 @Published 属性
在 AppCoordinator 中被创建但可能未被使用
建议：检查是否已被 AuthState 替代
AudioPanelViewModel.swift

使用 Combine 的 @Published 属性
在 AppCoordinator 中被创建并使用
注释说"暂不重构"
建议：这个应该被迁移到 State 对象或 AudioModule 中
## 八、调试视图和调试代码
### 8.1 调试视图（仍在使用）
问题：项目中有多个调试视图，这些应该被条件编译或移除。

受影响文件：

XMLRoundtripDebugView.swift

在 SettingsView 中作为 NavigationLink 显示
建议：应该被 #if DEBUG 包裹
OperationQueueDebugView.swift

在 SettingsView 中作为 NavigationLink 显示
建议：应该被 #if DEBUG 包裹
XMLDebugEditorView.swift

在 NoteDetailView 中使用（当 isDebugMode 时）
建议：应该被 #if DEBUG 包裹
DebugModeView.swift

包装 XMLDebugEditorView
建议：应该被 #if DEBUG 包裹
DebugWindowController.swift

在 MenuActionHandler 中被创建
建议：应该被 #if DEBUG 包裹
8.2 #if DEBUG 条件编译
问题：项目中有多处 #if DEBUG 代码，这些应该被清理或统一。

受影响文件：

LogService.swift
 - debugSensitive/infoSensitive 方法
PasteboardManager.swift
 - 多处 #if DEBUG
NativeEditorView.swift
 - Preview
PreviewHelper.swift
 - #if DEBUG
XMLDebugEditorView.swift
 - #if DEBUG
MenuManager.swift
 - 调试工具子菜单
 
## 九、TODO/FIXME 标记
### 9.1 待实现的功能
问题：有 3 处 TODO 标记，表示功能未完成。

受影响文件：

SettingsView.swift
 - 第 385 行

// TODO: 导入功能需要通过 NoteStore 或 EventBus 处理，后续任务实现
Sources/Window/Controllers/MainWindowController+Actions.swift - 第 1185 行

// TODO: 根据编辑器类型插入链接
AppStateManager.swift
 - 第 161 行

// TODO: 实现应用重置逻辑
建议：这些应该被转换为 spec 任务或移除。

## 十、References 目录
问题：文件树中显示有 References 目录，但搜索未找到内容。

建议：检查 References 目录是否还有存在价值，如果没有应该删除。

## 十一、优先级清理建议
高优先级（立即清理）
菜单编辑命令链路空实现：`MenuActionHandler -> MainWindowController+Actions` 的 `undo/redo/cut/copy/paste/selectAll` 目前仅占位，需先恢复可用行为。
导入流程逻辑断层：导入时构造了 `Note(title/content)` 但未实际写入该内容，需下沉为独立 ImportUseCase 并补齐落库链路。
`OperationProcessor` 过度集中（God Actor）：拆分为按操作类型的 handler（note/folder/file）+ 独立错误分类/响应解析组件。
菜单系统三层并行（`AppDelegate`、`MenuManager`、`MenuActionHandler`）且兼容代码残留，需统一命令路由与状态同步入口。
过渡网络链路清理：`NetworkClient`/`NetworkClientProtocol` 及依赖它的未接入主干实现（`DefaultAuthenticationService`、`DefaultImageService`）应清理或归档。

中优先级（下一个 sprint）
`AppCoordinator` 组合根瘦身：减少对 `.shared` 的直接依赖与手工接线，拆分为子装配器。
清理重复逻辑：如 `NotesListView` 中 XML 预览提取逻辑重复实现，提炼为单一工具。
将公开入口中的 TODO/“功能开发中”占位收敛为明确 spec 任务（保留入口但避免假完成状态）。
补齐关键模块测试：当前测试集中在 NativeEditor，需补充 OperationQueue/Menu/Import 的回归测试。

低优先级（长期改进）
统一性能监控入口为 `PerformanceService`，逐步替换散落计时代码。
持续清理强制解包、强制类型转换、强制 try。
评估 `@unchecked Sendable` 与 `nonisolated(unsafe)` 的剩余使用点，逐步收敛。

# 文件清单汇总
Sources/ 目录完整文件清单（按目录）
Sources/App/（9 个文件）

App.swift ✓
AppDelegate.swift ⚠️ (50+ @objc 方法，但必要)
AppStateManager.swift ⚠️ (TODO 标记)
MenuActionHandler.swift ⚠️ (调试菜单)
MenuItemTag.swift ✓
MenuManager.swift ⚠️ (调试菜单)
MenuManager+EditMenu.swift ✓
MenuManager+FormatMenu.swift ✓
MenuState.swift ✓
Sources/Coordinator/（2 个文件）

AppCoordinator.swift ⚠️ (AudioPanelViewModel)
SyncCoordinator.swift ✓
Sources/Core/（子目录）

EventBus/ ✓
Pagination/ ✓
Sources/Extensions/（4 个文件）

所有文件 ✓
Sources/Model/（11 个文件）

所有文件 ✓
Sources/Network/（12 个文件）

所有文件 ✓
Sources/Presentation/ViewModels/（2 个文件）

AuthenticationViewModel.swift ⚠️ (可能已被 AuthState 替代)
AudioPanelViewModel.swift ⚠️ (应该迁移到 State 对象)
Sources/Service/（多个子目录）

Audio/ ⚠️ (NotificationCenter + Combine 混用)
Authentication/ ⚠️ (Combine 使用)
Cache/ ✓
Core/ ⚠️ (LogService 中有 #if DEBUG)
Editor/ ⚠️ (性能监控代码残留)
Image/ ✓
Protocols/ ✓
Sources/State/（9 个文件）

所有文件 ✓
Sources/Store/（13 个文件）

大多数 ✓
LocalStorageService.swift ⚠️ (强制解包)
DatabaseService.swift ⚠️ (@unchecked Sendable，但合理)
Sources/Sync/（多个文件）

大多数 ✓
OperationData.swift ⚠️ (强制 try)
FileUploadOperationData.swift ⚠️ (强制 try)
OnlineStateManager.swift ⚠️ (Combine 使用)
Sources/ToolbarItem/（4 个文件）

所有文件 ✓
Sources/View/（多个子目录）

AppKitComponents/ ⚠️ (@objc 方法，但必要)
Bridge/ ⚠️ (Combine 使用、强制类型转换)
NativeEditor/ ⚠️ (性能监控代码、强制类型转换)
Shared/ ✓
SwiftUIViews/ ⚠️ (调试视图、NotificationCenter、强制解包)
Sources/Window/（多个文件）

Controllers/ ⚠️ (调试窗口、@objc 方法)
State/ ✓

# 总结
项目中存在以下主要问题：

性能监控代码散乱：5 个文件中有手动计时代码，需统一为 PerformanceService 基础设施
FormatStateSynchronizer 膨胀：340 行中仅 60 行是核心防抖逻辑，其余为死性能监控代码
PerformanceCache 死统计代码：CacheStatistics 从未被消费
架构混乱：Combine 和 EventBus 混用、NotificationCenter 和 EventBus 混用
代码质量：多处强制解包、强制类型转换、强制 try
旧架构残留：2 个 ViewModel 应该被迁移到 State 对象
调试代码：多个调试视图和调试菜单应该被条件编译
待实现功能：3 处 TODO 标记

## 十二、NetworkClient 溯源与处置建议（新增）

### 12.1 创建时间与来源

- `NetworkClient.swift` 首次创建于提交 `733ae56`（`refactor(migration): 创建 AuthUser 模型和 NetworkClient 抽象`）。
- 提交时间：2026-01-22 18:57:24 +0800。
- 初始路径为 `Sources/Service/Network/NetworkClient.swift`，后在目录重构中移动到 `Sources/Network/NetworkClient.swift`。

### 12.2 与 spec 的关系

该文件没有在 `.kiro/specs` 中找到“首次创建”的明确 spec 任务绑定，但在后续重构中多次被提及：

- spec 104（file-upload-operation-queue）明确将其列为“后续处理项”：
  - `NetworkClient / NetworkClientProtocol 的清理（可后续处理）`
- spec 106（deprecated-code-cleanup）仅更新注释，不涉及行为改造：
  - 移除与 `MiNoteService` 过渡期描述相关注释
- spec 112（unchecked-sendable-cleanup）仅做并发语义调整：
  - 将 `NetworkClient` 改为 `struct`，处理 Sendable 相关问题

结论：当前已落地的 spec 都未将其纳入主干网络架构建设，只做了“保留态”维护。

### 12.3 当前代码现状

- `NetworkClient` 当前仅被以下过渡实现引用：
  - `DefaultAuthenticationService`
  - `DefaultImageService`
- 这两套实现未接入当前主干依赖图（主干网络已走 `NetworkModule -> APIClient/NoteAPI/FolderAPI/FileAPI/SyncAPI/UserAPI`）。
- `NetworkClient` 自身仍有明显占位特征：
  - `baseURL` 属性与请求内硬编码 URL 并存
  - HTTP 错误统一映射为 `NetworkError.notAuthenticated`

### 12.4 处置建议（最终决策）

建议：**清理，不发扬光大**。

原因：

1. 它不在当前主干调用路径上，属于并行过渡链路残留。
2. 继续强化会形成第二套网络栈，与已完成的 `NetworkModule` 架构冲突。
3. spec 104 已明确其可作为后续清理项，当前时机成熟。

建议清理范围：

- `Sources/Network/NetworkClient.swift`
- `Sources/Network/NetworkClientProtocol.swift`
- 未接入主干且依赖该客户端的过渡实现（如 `DefaultAuthenticationService`、`DefaultImageService`），在确认无运行时入口后一并移除或归档。

## 十三、第二轮审计补充（模块级）

### 13.1 需要优先重构的屎山模块

1. 同步执行层：`Sources/Sync/OperationQueue/OperationProcessor.swift`
   - 体量过大（1400+ 行），同时承载调度、重试、API 调用、数据修复、事件发布，职责耦合过高。
2. 窗口动作层：`Sources/Window/Controllers/MainWindowController+Actions.swift`
   - 大量动作仍为占位实现或“开发中”提示，且混合菜单、编辑器、同步、窗口职责。
3. 菜单动作层：`Sources/App/MenuActionHandler.swift`
   - 导入导出、窗口行为、格式动作与状态同步混在同一类，且存在导入内容未真正写入的逻辑断层。
4. 菜单构建层：`Sources/App/MenuManager.swift` + `Sources/App/AppDelegate.swift`
   - 菜单定义、转发、兼容入口并存，维护成本高，改动容易出现行为不一致。
5. 组合根：`Sources/Coordinator/AppCoordinator.swift`
   - 依赖装配过重、`.shared` 直接引用较多，影响可测试性和后续演进。

### 13.2 已识别的具体风险点

- 编辑命令路由存在“上层转发正常、底层空实现”的断层，用户可见行为会不一致。
- 导入流程当前更接近“创建空新笔记”，而非“按文件内容导入”。
- 部分功能入口已对外暴露，但内部仍是占位实现，容易造成“看起来可用、实际不可用”的假象。

### 13.3 与既有结论的关系

- 本节为对前文“性能监控、并发标注、TODO 清理”的补充，不冲突。
- 优先级以“先修功能正确性和架构主链，再做代码洁癖型清理”为原则。
