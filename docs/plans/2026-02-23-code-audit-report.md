# 代码审计报告 2026-02-23（更新版）

## 审计背景

在完成以下大规模重构后，对项目代码质量进行全面审计：
- spec 98：状态管理重构（NotesViewModel -> State 对象）
- spec 100：架构重构（EventBus 驱动 + State 对象）
- spec 101：Cookie 自动刷新重构
- spec 102：MiNoteService 拆分（APIClient/NoteAPI/FolderAPI/FileAPI/SyncAPI/UserAPI）
- spec 103：编辑器桥接层重构（NativeEditorView + NativeEditorContext 拆分）
- spec 104：文件上传操作队列
- spec 105：MainWindowController 拆分重构（已完成）

## 整体评价

项目架构良好，评分 8.5/10。经过多轮重构，核心模块（网络层、状态管理、同步引擎、编辑器、窗口控制器）已经具备清晰的职责划分。

## 已完成的重构（spec 100-105）

| Spec | 模块 | 重构内容 |
|------|------|----------|
| 100 | 架构 | EventBus 驱动 + State 对象架构 |
| 101 | 网络 | NetworkRequestManager 统一 401 自动刷新 Cookie |
| 102 | 网络 | MiNoteService 拆分为 APIClient/NoteAPI/FolderAPI/FileAPI/SyncAPI/UserAPI |
| 103 | 编辑器 | NativeEditorView + NativeEditorContext 按职责拆分 |
| 104 | 同步 | 文件上传操作队列基础设施 |
| 105 | 窗口 | MainWindowController 拆分为 1 核心 + 6 extension |

## 待清理：废弃代码和 print() 残留

### 可直接删除的废弃文件

| 文件 | 说明 |
|------|------|
| `Sources/Network/MiNoteService.swift` | 全部方法已 deprecated，Facade 转发层，无直接实例化引用 |
| `Sources/Network/MiNoteService+Encryption.swift` | MiNoteService 的 extension，随主文件一起删除 |
| `Sources/View/SwiftUIViews/Common/ContentView.swift` | 已 deprecated，使用 ContentAreaView 替代 |

### 废弃方法待清理

| 文件 | deprecated 方法数 | 说明 |
|------|-------------------|------|
| `CoordinatorFormatApplier.swift` | 7 | 已被 BlockFormatHandler.apply 替代，均为 private |
| `NewLineHandler.swift` | 2 | 已被新方法替代，均为 private |

### print() 残留

| 文件 | print() 数量 | 说明 |
|------|-------------|------|
| `MemoryCacheManager.swift` | 8 处 | 使用 `Swift.print()`，需替换为 `LogService.shared` |
| `WindowManager.swift` | 7 处 | 使用 `print()`，需替换为 `LogService.shared` |

### error domain 字符串清理

多个 API 文件中使用 `"MiNoteService"` 作为 NSError domain 字符串，删除 MiNoteService 后应统一替换为 `"MiNote"` 或各自的类名。

涉及文件：NoteAPI.swift、FolderAPI.swift、FileAPI.swift、UserAPI.swift、OperationProcessor.swift

## 待重构模块（按优先级排列）

### P1 紧急（核心模块，职责严重混杂）

| 模块 | 行数 | 核心问题 |
|------|------|----------|
| XiaoMiFormatConverter.swift | ~2,052 | XML 转换 + 格式检测 + 附件处理 + deprecated 方法未清理 |
| SyncEngine.swift | ~1,595 | 增量同步 + 全量同步 + 冲突解决 + 错误处理混在一起 |
| OperationProcessor.swift | ~1,428 | 8 种操作执行 + 重试策略 + 错误分类全部混杂 |
| FormatManager.swift | ~1,189 | inline 格式和 block 格式交织，50+ 公开方法 |

### P2 重要（大文件，可维护性差）

| 模块 | 行数 | 核心问题 |
|------|------|----------|
| MenuActionHandler.swift | ~1,345 | 107 个菜单方法集中一个文件 |
| FormatMenuDiagnostics.swift | ~1,301 | 调试工具过于复杂 |
| MainWindowController+Actions.swift | ~1,267 | 拆分后仍有 80+ @objc 方法 |
| MenuManager.swift | ~1,153 | 菜单构建逻辑过于复杂 |
| ListBehaviorHandler.swift | ~1,142 | 光标限制 + 回车处理 + 删除处理 + 编号更新 |
| UnifiedOperationQueue.swift | ~1,116 | 操作存储 + 去重合并 + 状态管理 |

### P3 优化

| 模块 | 行数 | 核心问题 |
|------|------|----------|
| AudioPanelView.swift | ~1,132 | 录制 + 播放 + 列表 UI 混杂 |
| NotesListView.swift | ~1,107 | 列表 + 搜索 + 筛选 + 排序混杂 |
| NativeTextView.swift | ~954 | 光标 + 键盘 + 粘贴 + 拖放 + 附件交互 |
| NativeEditorContext.swift | ~825 | 30+ @Published 属性，状态过多 |
| NoteEditingCoordinator.swift | ~885 | 加载 + 保存 + 缓存 + 云端同步 4 个阶段交织 |

## 建议重构顺序

1. spec 106：快速清理（删除废弃代码 + 替换 print + 清理 error domain）
2. spec 107+：按 P1 逐个拆分大模块