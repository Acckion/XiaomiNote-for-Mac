# MiNoteMac 代码质量审计报告

**审计日期**: 2026-02-21  
**审计范围**: 完整代码库（94,589 行 Swift 代码）  
**审计方法**: 静态分析 + 文件结构扫描 + 已完成 spec 对标

---

## 执行摘要

项目经历了 spec 100-108 的大规模重构，但仍存在以下关键问题：

### 关键发现

1. **超大文件问题**（300+ 行）：40+ 个文件超过 600 行，最大文件 1,429 行
2. **通信方式混乱**：NotificationCenter 仍被广泛使用（50+ 处），与新的 EventBus 架构并存
3. **职责混乱的类**：多个类承担过多职责（如 FormatManager、NativeEditorContext、NativeTextView）
4. **待完成的工作**：3 个 TODO 注释，表明功能未完成
5. **架构不一致**：新旧两套通信机制并行，增加维护复杂度

### 优先级排序

| 优先级 | 问题 | 影响范围 | 工作量 |
|--------|------|--------|--------|
| P0 | 超大文件拆分（1000+ 行） | 8 个文件 | 中等 |
| P1 | NotificationCenter 迁移到 EventBus | 50+ 处 | 大 |
| P2 | 职责混乱的类重构 | 15+ 个类 | 大 |
| P3 | 完成 TODO 功能 | 3 处 | 小 |
| P4 | 单例模式清理 | 20+ 处 | 小 |

---

## 一、超大文件问题（P0）

### 1.1 文件规模分布

**超过 1000 行的文件**（8 个）：

| 文件 | 行数 | 职责 | 问题 |
|------|------|------|------|
| OperationProcessor.swift | 1,429 | 操作处理 | 操作类型处理混乱，方法过多 |
| MenuActionHandler.swift | 1,342 | 菜单动作 | 菜单项验证 + 状态管理 + 动作处理混合 |
| FormatMenuDiagnostics.swift | 1,301 | 格式菜单诊断 | 诊断逻辑过于复杂 |
| MainWindowController+Actions.swift | 1,267 | 窗口动作 | 所有 @objc 动作方法集中 |
| DebugSettingsView.swift | 1,247 | 调试设置 UI | 调试功能过多 |
| FormatManager.swift | 1,189 | 格式管理 | 格式应用 + 检测 + 转换混合 |
| MenuManager.swift | 1,153 | 菜单管理 | 菜单构建 + 编辑菜单 + 格式菜单混合 |
| ListBehaviorHandler.swift | 1,142 | 列表行为 | 列表处理逻辑过于复杂 |

**超过 800 行的文件**（15 个）：

| 文件 | 行数 | 职责 |
|------|------|------|
| AudioPanelView.swift | 1,132 | 音频面板 UI |
| UnifiedOperationQueue.swift | 1,116 | 操作队列管理 |
| NotesListView.swift | 1,107 | 笔记列表 UI |
| OperationQueueDebugView.swift | 1,019 | 操作队列调试 UI |
| NativeTextView.swift | 954 | 原生文本视图 |
| MainWindowToolbarDelegate.swift | 954 | 工具栏委托 |
| NativeEditorLogger.swift | 926 | 编辑器日志 |
| SidebarView.swift | 922 | 侧边栏 UI |
| CustomAttachments.swift | 902 | 自定义附件 |
| NotesListViewController.swift | 892 | 笔记列表控制器 |
| NoteEditingCoordinator.swift | 885 | 编辑协调器 |
| NativeFormatProvider.swift | 866 | 格式提供者 |
| AudioAttachment.swift | 837 | 音频附件 |
| AudioRecorderService.swift | 834 | 音频录制服务 |
| NativeEditorContext.swift | 825 | 编辑器上下文 |

### 1.2 问题分析

**OperationProcessor.swift（1,429 行）**
- 职责：操作处理、重试策略、错误分类、事件发布
- 问题：
  - 包含 8 种操作类型的处理逻辑（笔记创建、更新、删除、文件上传等）
  - 混合了业务逻辑、错误处理、重试策略、事件发布
  - 方法数过多（30+ 个方法）
  - 同时使用 NotificationCenter 和 EventBus 发布事件

**MenuActionHandler.swift（1,342 行）**
- 职责：菜单项验证、菜单状态管理、菜单动作处理
- 问题：
  - 包含 50+ 个菜单项的验证逻辑
  - 混合了菜单项启用/禁用状态、勾选状态、动作处理
  - 与 MenuManager 职责重叠

**FormatManager.swift（1,189 行）**
- 职责：格式应用、格式检测、格式转换
- 问题：
  - 包含 20+ 种格式的应用方法
  - 混合了格式应用、列表处理、标题处理、引用处理
  - 与 ListBehaviorHandler、BlockFormatHandler 职责重叠

**NativeEditorContext.swift（825 行）**
- 职责：编辑器状态、格式管理、内容管理、自动保存
- 问题：
  - 包含 30+ 个 @Published 属性
  - 混合了编辑器状态、格式状态、保存状态、内容保护
  - 与 NativeEditorCoordinator、EditorFormatDetector 职责重叠

### 1.3 建议

**立即行动**：
1. 拆分 OperationProcessor（按操作类型）
2. 拆分 MenuActionHandler（按菜单类别）
3. 拆分 FormatManager（按格式类型）
4. 拆分 NativeEditorContext（按职责）

---

## 二、通信方式混乱（P1）

### 2.1 NotificationCenter 使用统计

**发现 50+ 处 NotificationCenter 使用**：

| 模块 | 使用次数 | 通知类型 |
|------|---------|---------|
| 编辑器相关 | 15 | 格式变化、保存状态、调试模式 |
| 音频相关 | 12 | 录制状态、播放状态、上传状态 |
| 网络相关 | 8 | 网络恢复、Cookie 刷新 |
| 同步相关 | 6 | 在线状态、操作完成 |
| 窗口相关 | 5 | 返回画廊、视图切换 |
| 其他 | 4 | 内存警告、权限变化 |

### 2.2 问题分析

**架构不一致**：
- 新架构设计使用 EventBus（Actor 隔离、类型安全）
- 旧代码仍使用 NotificationCenter（字符串标识、运行时错误风险）
- 两套机制并行存在，增加维护复杂度

**具体问题**：

1. **EditorFormatDetector.swift**
   ```swift
   NotificationCenter.default.post(name: .paragraphStyleDidChange, ...)
   ```
   应改为：`eventBus.publish(EditorEvent.formatChanged(...))`

2. **IdMappingRegistry.swift**
   ```swift
   NotificationCenter.default.post(name: Self.idMappingCompletedNotification, ...)
   ```
   应改为：`eventBus.publish(SyncEvent.idMappingCompleted(...))`

3. **AudioRecorderService.swift**
   ```swift
   NotificationCenter.default.post(name: Self.recordingStateDidChangeNotification, ...)
   ```
   应改为：`eventBus.publish(AudioEvent.recordingStateChanged(...))`

### 2.3 迁移计划

**Phase 1**：编辑器相关通知迁移（15 处）
- EditorFormatDetector → EditorEvent
- NativeEditorContext → EditorEvent
- MainWindowController+Actions → EditorEvent

**Phase 2**：音频相关通知迁移（12 处）
- AudioRecorderService → AudioEvent
- AudioPlayerService → AudioEvent
- AudioUploadService → AudioEvent
- AudioPanelStateManager → AudioEvent

**Phase 3**：网络和同步相关通知迁移（14 处）
- NetworkMonitor → NetworkEvent
- OnlineStateManager → SyncEvent
- IdMappingRegistry → SyncEvent

**Phase 4**：清理 NotificationCenter 定义
- 删除所有 NSNotification.Name 扩展
- 删除所有 NotificationCenter 监听代码

---

## 三、职责混乱的类（P2）

### 3.1 编辑器相关类的职责混乱

**NativeEditorContext.swift（825 行）**

当前职责：
- 编辑器状态管理（30+ @Published 属性）
- 格式状态管理（currentFormats、toolbarButtonStates）
- 内容管理（attributedText、nsAttributedText、titleText）
- 自动保存管理（autoSaveManager、changeTracker）
- 内容保护（backupContent、lastSaveError）

问题：
- 职责过多，难以维护
- 与 NativeEditorCoordinator 职责重叠
- 与 EditorFormatDetector 职责重叠
- 与 EditorContentManager 职责重叠

建议拆分：
1. **EditorStateManager**：编辑器基本状态（焦点、光标、选择范围）
2. **EditorFormatStateManager**：格式状态（currentFormats、toolbarButtonStates）
3. **EditorContentStateManager**：内容状态（attributedText、titleText、版本号）
4. **EditorSaveStateManager**：保存状态（saveStatus、backupContent、autoSave）

**NativeTextView.swift（954 行）**

当前职责：
- 文本视图基础功能
- 键盘事件处理（回车、删除、缩进）
- 列表行为处理
- 粘贴板处理
- 拖放处理
- 格式应用
- 光标管理

问题：
- 职责过多，方法数 40+
- 与 ListBehaviorHandler 职责重叠
- 与 PasteboardManager 职责重叠
- 与 FormatManager 职责重叠

建议拆分：
1. **NativeTextViewCore**：基础文本视图功能
2. **NativeTextViewKeyboardHandler**：键盘事件处理
3. **NativeTextViewPasteboardHandler**：粘贴板处理
4. **NativeTextViewDragDropHandler**：拖放处理

**FormatManager.swift（1,189 行）**

当前职责：
- 加粗、斜体、下划线等基础格式应用
- 标题格式应用
- 列表格式应用
- 引用格式应用
- 对齐方式应用
- 颜色应用
- 格式检测

问题：
- 职责过多，方法数 50+
- 与 ListBehaviorHandler 职责重叠
- 与 BlockFormatHandler 职责重叠
- 与 NativeFormatProvider 职责重叠

建议拆分：
1. **BasicFormatManager**：基础格式（加粗、斜体、下划线、颜色）
2. **BlockFormatManager**：块级格式（标题、列表、引用、对齐）
3. **FormatDetector**：格式检测（独立类）

### 3.2 菜单相关类的职责混乱

**MenuActionHandler.swift（1,342 行）**

当前职责：
- 菜单项验证（NSMenuItemValidation）
- 菜单状态管理（MenuState）
- 菜单动作处理（50+ 个 @objc 方法）

问题：
- 职责过多
- 与 MenuManager 职责重叠
- 与 MainWindowController+Actions 职责重叠

建议拆分：
1. **MenuValidator**：菜单项验证逻辑
2. **MenuStateManager**：菜单状态管理
3. **MenuActionDispatcher**：菜单动作分发

**MenuManager.swift（1,153 行）**

当前职责：
- 菜单构建
- 编辑菜单项构建
- 格式菜单项构建
- 菜单项标签定义

问题：
- 职责过多
- 与 MenuActionHandler 职责重叠
- 编辑菜单和格式菜单逻辑混合

建议拆分：
1. **MenuBuilder**：基础菜单构建
2. **EditMenuBuilder**：编辑菜单构建
3. **FormatMenuBuilder**：格式菜单构建

### 3.3 操作队列相关类的职责混乱

**OperationProcessor.swift（1,429 行）**

当前职责：
- 笔记创建操作处理
- 笔记更新操作处理
- 笔记删除操作处理
- 文件上传操作处理
- 重试策略管理
- 错误分类和处理
- 事件发布

问题：
- 职责过多，方法数 30+
- 操作类型处理逻辑混合
- 与 UnifiedOperationQueue 职责重叠

建议拆分：
1. **NoteOperationHandler**：笔记操作处理
2. **FileOperationHandler**：文件操作处理
3. **OperationRetryStrategy**：重试策略
4. **OperationErrorHandler**：错误处理

### 3.4 音频相关类的职责混乱

**AudioRecorderService.swift（834 行）**

当前职责：
- 音频录制管理
- 权限检查
- 状态管理
- 通知发布

问题：
- 职责过多
- 与 AudioPanelStateManager 职责重叠

建议拆分：
1. **AudioRecorder**：核心录制功能
2. **AudioPermissionManager**：权限管理
3. **AudioRecorderStateManager**：状态管理

---

## 四、待完成的工作（P3）

### 4.1 TODO 注释

| 文件 | 行号 | 内容 | 优先级 |
|------|------|------|--------|
| MainWindowController+Actions.swift | 1184 | 链接插入功能待实现 | 低 |
| SettingsView.swift | 367 | 导入功能需要通过 NoteStore 或 EventBus 处理 | 中 |
| AppStateManager.swift | 150 | 实现应用重置逻辑 | 低 |

### 4.2 建议

1. **链接插入功能**：在 FormatManager 中添加 `insertLink()` 方法
2. **导入功能**：通过 EventBus 发布 `NoteEvent.importRequested(notes:)`
3. **应用重置**：实现清除本地数据、重置同步状态的逻辑

---

## 五、单例模式使用（P4）

### 5.1 单例统计

**发现 20+ 个单例**：

| 类 | 单例名 | 模块 | 问题 |
|------|--------|------|------|
| FormatManager | shared | 编辑器 | 应改为依赖注入 |
| FontSizeManager | shared | 编辑器 | 应改为依赖注入 |
| AudioRecorderService | shared | 音频 | 应改为依赖注入 |
| AudioPlayerService | shared | 音频 | 应改为依赖注入 |
| AudioUploadService | shared | 音频 | 应改为依赖注入 |
| AudioCacheService | shared | 音频 | 应改为依赖注入 |
| APIClient | shared | 网络 | 应改为依赖注入 |
| NoteAPI | shared | 网络 | 应改为依赖注入 |
| FolderAPI | shared | 网络 | 应改为依赖注入 |
| FileAPI | shared | 网络 | 应改为依赖注入 |
| SyncAPI | shared | 网络 | 应改为依赖注入 |
| UserAPI | shared | 网络 | 应改为依赖注入 |
| DatabaseService | shared | 存储 | 应改为依赖注入 |
| LocalStorageService | shared | 存储 | 应改为依赖注入 |
| EventBus | shared | 核心 | 应改为依赖注入 |
| OperationProcessor | shared | 同步 | 应改为依赖注入 |
| UnifiedOperationQueue | shared | 同步 | 应改为依赖注入 |
| SyncStateManager | shared | 同步 | 应改为依赖注入 |
| LogService | shared | 核心 | 保留（全局日志） |
| NetworkMonitor | shared | 网络 | 保留（全局网络状态） |

### 5.2 问题

- 单例模式限制了测试能力
- 难以进行依赖注入
- 增加了模块间耦合

### 5.3 建议

- 逐步迁移到依赖注入（通过 ServiceLocator 或构造函数注入）
- 保留 LogService 和 NetworkMonitor 作为全局单例
- 其他服务通过 AppCoordinator 创建和注入

---

## 六、已完成的重构 spec 对标

### 6.1 spec 100-108 完成情况

| Spec | 标题 | 状态 | 问题 |
|------|------|------|------|
| 100 | 架构重构 | ⚠️ 部分完成 | 新旧架构并存，EventBus 未被充分使用 |
| 101 | Cookie 自动刷新 | ✅ 完成 | NetworkRequestManager 正确实现 |
| 102 | MiNoteService 重构 | ✅ 完成 | API 类正确拆分 |
| 103 | 编辑器桥接重构 | ⚠️ 部分完成 | NativeEditorContext 职责仍混乱 |
| 104 | 文件上传操作队列 | ✅ 完成 | UnifiedOperationQueue 实现正确 |
| 105 | 主窗口控制器重构 | ✅ 完成 | MainWindowController 正确拆分为 7 个文件 |
| 106 | 废弃代码清理 | ✅ 完成 | MiNoteService 已删除 |
| 107 | 格式转换器清理 | ✅ 完成 | XiaoMiFormatConverter 已精简 |
| 108 | 同步引擎重构 | ✅ 完成 | SyncEngine 正确拆分为 5 个文件 |

### 6.2 遗留问题

从 spec 100 审计报告中识别的问题仍未完全解决：

1. **新旧架构并存**：EventBus 创建但未被充分使用
2. **NotificationCenter 仍被广泛使用**：应迁移到 EventBus
3. **职责混乱的类未拆分**：NativeEditorContext、FormatManager 等
4. **单例模式未改进**：仍有 20+ 个单例

---

## 七、代码质量指标

### 7.1 复杂度分析

| 指标 | 值 | 评级 | 说明 |
|------|------|------|------|
| 平均文件大小 | 280 行 | 中等 | 超过 300 行的文件占 15% |
| 最大文件大小 | 1,429 行 | 高 | OperationProcessor 需拆分 |
| 类平均方法数 | 15 | 中等 | 部分类超过 30 个方法 |
| 圈复杂度 | 未测量 | - | 建议使用 SwiftLint 测量 |
| 代码重复率 | 未测量 | - | 建议使用 Simian 测量 |

### 7.2 架构健康度

| 维度 | 评分 | 说明 |
|------|------|------|
| 分层清晰度 | 7/10 | 分层明确，但新旧架构混存 |
| 模块独立性 | 6/10 | 单例模式导致耦合过高 |
| 职责单一性 | 5/10 | 多个类职责混乱 |
| 通信一致性 | 4/10 | NotificationCenter 和 EventBus 并存 |
| 可测试性 | 5/10 | 单例模式限制测试 |
| 文档完整性 | 8/10 | 代码注释充分 |

---

## 八、优先级重构计划

### Phase 1：紧急修复（1-2 周）

**目标**：解决最严重的职责混乱问题

1. **拆分 OperationProcessor**（1,429 行）
   - 按操作类型拆分为 5 个 handler
   - 预计减少到 300-400 行

2. **拆分 MenuActionHandler**（1,342 行）
   - 按菜单类别拆分为 3 个类
   - 预计减少到 400-500 行

3. **迁移编辑器通知到 EventBus**（15 处）
   - EditorFormatDetector → EditorEvent
   - NativeEditorContext → EditorEvent

### Phase 2：架构改进（2-3 周）

**目标**：统一通信方式，完成 EventBus 迁移

1. **迁移所有 NotificationCenter 到 EventBus**（50+ 处）
   - 音频相关（12 处）
   - 网络相关（8 处）
   - 同步相关（6 处）
   - 其他（4 处）

2. **拆分 NativeEditorContext**（825 行）
   - 按职责拆分为 4 个 state 类
   - 预计减少到 200-250 行

3. **拆分 FormatManager**（1,189 行）
   - 按格式类型拆分为 3 个类
   - 预计减少到 400-500 行

### Phase 3：代码质量提升（2-3 周）

**目标**：完成单例迁移，提升可测试性

1. **迁移单例到依赖注入**（20+ 个）
   - 通过 AppCoordinator 创建和注入
   - 保留 LogService 和 NetworkMonitor

2. **拆分超大 UI 组件**（800+ 行）
   - AudioPanelView（1,132 行）
   - NotesListView（1,107 行）
   - SidebarView（922 行）

3. **完成 TODO 功能**（3 处）
   - 链接插入功能
   - 导入功能
   - 应用重置功能

---

## 九、建议和行动项

### 9.1 立即行动（本周）

- [ ] 创建 spec 109：OperationProcessor 拆分
- [ ] 创建 spec 110：MenuActionHandler 拆分
- [ ] 创建 spec 111：编辑器通知迁移到 EventBus

### 9.2 短期行动（1-2 周）

- [ ] 创建 spec 112：NativeEditorContext 拆分
- [ ] 创建 spec 113：FormatManager 拆分
- [ ] 创建 spec 114：所有 NotificationCenter 迁移到 EventBus

### 9.3 中期行动（2-4 周）

- [ ] 创建 spec 115：单例迁移到依赖注入
- [ ] 创建 spec 116：超大 UI 组件拆分
- [ ] 创建 spec 117：完成 TODO 功能

### 9.4 长期行动（1-2 月）

- [ ] 建立代码质量检查流程（SwiftLint、Simian）
- [ ] 建立单元测试覆盖率目标（70%+）
- [ ] 建立代码审查规范（最大文件 500 行、最大方法数 20）

---

## 十、总结

MiNoteMac 项目经历了大规模重构，新架构框架已建立（EventBus、State 对象、SyncEngine 拆分等），但仍存在以下关键问题：

1. **超大文件问题**：40+ 个文件超过 600 行，需要进一步拆分
2. **通信方式混乱**：NotificationCenter 和 EventBus 并存，应统一迁移
3. **职责混乱**：多个类承担过多职责，需要按职责拆分
4. **单例模式**：20+ 个单例限制了可测试性，应迁移到依赖注入

**建议优先级**：
1. 拆分超大文件（P0）
2. 迁移 NotificationCenter 到 EventBus（P1）
3. 拆分职责混乱的类（P2）
4. 完成 TODO 功能（P3）
5. 迁移单例到依赖注入（P4）

通过按优先级执行这些重构，可以显著提升代码质量、可维护性和可测试性。
