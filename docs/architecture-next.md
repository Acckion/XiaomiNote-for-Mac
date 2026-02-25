# MiNoteMac 顶层架构重构蓝图（Architecture Next）

## 1. 文档目的

本文档定义 spec100-spec122 之后的下一阶段顶层架构方向。
目标不是继续做"文件拆分式重构"，而是建立清晰、稳定、可约束的系统边界，降低未来维护成本并提升可扩展性。

适用时间范围：2026-02-25 起的后续重构周期。
最近审计时间：2026-02-25（基于代码库实际状态）。

---

## 2. 当前状态与问题

### 2.1 已解决的问题（审计确认）

以下问题在 spec100-spec122 中已解决，无需再列入待办：

1. 网络层过渡实现已全部清理 — NetworkClient、NetworkClientProtocol、DefaultAuthenticationService、DefaultImageService 已不存在于代码库中，NetworkModule 为唯一网络主干。
2. 模块工厂已成熟 — 4 个模块工厂（NetworkModule、SyncModule、EditorModule、AudioModule）稳定运行，启动链清晰。
3. OperationProcessor 已拆分 — spec122 完成拆分为 NoteOperationHandler、FileOperationHandler、FolderOperationHandler。
4. State 对象已替代 ViewModel — 9 个 State 对象已就位（AuthState、FolderState、NoteListState、NoteEditorState、SearchState、SyncState、ViewOptionsState、ViewOptionsManager、ViewState）。
5. 构造器注入已替代 .shared — 除 13 个基础设施类外，所有依赖通过构造器注入。

### 2.2 仍存在的结构性问题

按严重程度排序：

1. 菜单系统三层并行（最大单点复杂度）：
   - AppDelegate：70+ 个 @objc 转发方法，约 500 行纯转发代码，无任何业务逻辑。
   - MenuActionHandler：961 行，混合格式、文件、窗口、导入导出等多域业务逻辑。
   - MenuManager：911 行，菜单定义与状态更新耦合。
   - 同一个菜单动作需要跨 3 个文件追踪，维护成本极高。

2. Command 模式覆盖率不足：
   - 已有基础设施：AppCommand 协议、CommandDispatcher、6 个具体命令（CreateNote、DeleteNote、ToggleStar、ShareNote、CreateFolder、ShowSettings、Sync、IncrementalSync）。
   - 但 MenuActionHandler 中 90% 以上的业务逻辑仍未迁移到 Command，Command 化形同虚设。

3. 目录组织以技术层为主（Network/Store/State/View），功能改动跨目录跳转频繁。

4. EventBus、NotificationCenter、直接调用混用，缺少明确边界规则文档。

5. 缺少架构约束自动化，重构成果容易被新代码破坏。

6. 13 个基础设施类仍保留 `.shared` 单例，缺少分级退出策略：
   - 可退出（中期）：NetworkMonitor、NetworkErrorHandler、NetworkLogger、PerformanceService、PreviewHelper、ViewOptionsManager
   - 需保留（长期）：LogService、DatabaseService、EventBus
   - 待评估：AudioPlayerService、AudioRecorderService、AudioDecryptService、PrivateNotesPasswordManager

7. 导入流程存在逻辑断层：创建空笔记但未真实写入内容。

8. 菜单编辑命令（undo/redo/cut/copy/paste）为空实现。

9. AppCoordinator 本身已较精简（约 200 行），但 AppCoordinatorAssembler 的手工接线代码（100+ 行）缺少按域拆分能力，随着功能增长会持续膨胀。

---

## 3. 架构目标

### 3.1 业务目标

1. 新功能开发时，80% 以上改动限定在单一业务域目录。
2. 关键流程（编辑、同步、导入导出、菜单命令）支持可回归测试。
3. 新人理解主链路（启动、编辑、同步）时间控制在 1 天内。

### 3.2 技术目标

1. 建立稳定依赖方向：UI -> Application -> Domain <- Infrastructure。
2. Domain 层不依赖 AppKit/SwiftUI/SQLite/API 细节。
3. 组合根只负责装配，不承载业务流程逻辑。
4. 全局事件和系统通知职责分离，统一治理。
5. 菜单/工具栏/快捷键统一通过 Command 模式调度，消除多入口分叉实现。

---

## 4. 目标架构（Target Architecture）

### 4.1 分层模型

每个业务域内部统一四层：

1. UI 层
2. Application 层
3. Domain 层
4. Infrastructure 层

职责定义：

- UI：SwiftUI/AppKit 展示与用户交互，不直接操作数据库和 API。
- Application：UseCase/CommandHandler/Facade，编排流程与事务边界。
- Domain：实体、值对象、领域规则、仓储接口。
- Infrastructure：SQLite/APIClient/文件系统/EventBus 适配实现。

### 4.2 依赖方向

仅允许以下依赖：

1. UI -> Application
2. Application -> Domain
3. Infrastructure -> Domain
4. CompositionRoot -> 所有层（仅装配）

禁止：

1. UI 直接依赖 Infrastructure。
2. Domain 依赖 SwiftUI/AppKit/Foundation 以外技术实现细节（SQLite、URLSession 具体实现）。
3. Domain 依赖 EventBus/NotificationCenter。

### 4.3 菜单命令目标架构

当前三层转发架构（AppDelegate @objc → MenuActionHandler → 业务逻辑）替换为：

菜单项/工具栏/快捷键 ↓ (selector) AppDelegate @objc 方法（薄转发层，仅构造 Command） ↓ CommandDispatcher.dispatch(command) ↓ 具体 Command.execute(context) ↓ State 对象 / Service（实际业务逻辑）


目标：AppDelegate 的 @objc 方法体缩减为 1-2 行（构造 Command + dispatch），MenuActionHandler 最终消亡。

---

## 5. 目录重组方案（Vertical Slice）

### 5.1 目标目录结构

建议从当前技术分层目录逐步演进到业务域目录：

```text
Sources/
├── App/
│   ├── Bootstrap/           # AppDelegate, AppLaunchAssembler
│   ├── Composition/         # RootComposition, FeatureAssembler
│   └── Runtime/             # AppStateManager, RuntimeOrchestrator
├── Shared/
│   ├── Kernel/              # LogService, EventBus, 基础工具
│   ├── Contracts/           # 跨域协议与通用 DTO
│   └── UICommons/           # 共享 UI 组件
├── Features/
│   ├── Notes/
│   │   ├── UI/
│   │   ├── Application/
│   │   ├── Domain/
│   │   └── Infrastructure/
│   ├── Editor/
│   ├── Sync/
│   ├── Auth/
│   ├── Folders/
│   ├── Search/
│   └── Audio/
└── Legacy/                  # 过渡期兼容代码，带退出时间
```

### 5.2 迁移约束

1. `Legacy/` 是临时缓冲区，所有迁入文件必须带"删除截止版本"。
2. 新增功能禁止落入旧技术层目录。
3. 目录迁移必须同步更新 `project.yml`（XcodeGen），每次迁移后执行 `xcodegen generate` 验证。
4. 迁移以业务域为单位，每个域一个 spec，避免一次性大规模移动。

---

## 6. 关键治理决策

### 6.1 EventBus 不弃用，收敛职责

EventBus 作为跨域业务事件总线保留。

使用范围：

1. 跨域业务状态变化（同步完成、认证失效、ID 迁移）。
2. 需要解耦发布者与多个订阅者的业务事件。

禁止范围：

1. UI 控件内部即时交互（优先回调/绑定）。
2. 系统通知替代（系统通知继续使用 NotificationCenter）。

### 6.2 NotificationCenter 仅保留两类场景

1. Apple 系统通知（如 NSApplication.willTerminateNotification）。
2. AppKit 内部桥接且无业务语义的局部通知（如编辑器内部格式状态同步）。

任何新增业务通知默认走 EventBus。

### 6.3 Command 模型统一入口（渐进式迁移）

菜单、工具栏、快捷键、窗口动作统一转换为 Command。

流程：

1. UI 发出 Command。
2. CommandDispatcher 调度到具体 Command。
3. Command 调用 State 对象或 Service 执行业务逻辑。
4. 按需发布 EventBus 事件。

迁移策略（渐进式，非一次性替换）：

1. 第一批：格式命令（toggleBold、toggleItalic 等，约 20 个，纯转发无复杂逻辑）。
2. 第二批：文件命令（导入、导出、创建笔记/文件夹，约 15 个）。
3. 第三批：窗口命令（平铺、最大化、居中等，约 12 个）。
4. 第四批：视图命令（列表/画廊切换、缩放、折叠等，约 10 个）。
5. 最终：MenuActionHandler 清空并删除。

收益：同一业务动作的多入口不再分叉实现。

### 6.4 组合根瘦身（修正方案）

原计划将 AppCoordinator 拆分为 3 个类。审计发现 AppCoordinator 本身已较精简（约 200 行），真正需要拆分的是装配层。

修正方案：

1. AppCoordinatorAssembler 拆分为按域的 FeatureAssembler（每个域独立装配方法）。
2. AppCoordinator 保留当前职责（State 管理 + 协调方法 + 窗口代理）。
3. 启动时序逻辑从 AppCoordinator.start() 提取到 RuntimeOrchestrator（当 start() 复杂度增长时再执行）。
4. 长期目标：随着 Vertical Slice 迁移，协调方法逐步下沉到各域的 Application 层。

### 6.5 单一网络主干（已完成）

审计确认：NetworkClient、NetworkClientProtocol、DefaultAuthenticationService、DefaultImageService 已全部清理。

当前唯一主干：`NetworkModule -> APIClient -> Domain APIs`。

治理规则：禁止引入第二套网络抽象。任何新增网络请求必须通过 NetworkModule 提供的 API 类。

### 6.6 .shared 单例分级退出策略

将 13 个残留 .shared 单例分为三级：

第一级（可退出，中期目标）：
- NetworkMonitor → 迁入 NetworkModule 构造
- NetworkErrorHandler → 迁入 NetworkModule 构造
- NetworkLogger → 迁入 NetworkModule 构造
- PerformanceService → 迁入 AppCoordinatorAssembler 构造
- PreviewHelper → 迁入需要的 State 对象构造
- ViewOptionsManager → 迁入 AppCoordinatorAssembler 构造

第二级（需保留，架构基础设施）：
- LogService → 全局日志，保留 .shared
- DatabaseService → 全局数据库，保留 .shared
- EventBus → 全局事件总线，保留 .shared

第三级（待评估，依赖硬件资源）：
- AudioPlayerService → 评估是否可迁入 AudioModule
- AudioRecorderService → 评估是否可迁入 AudioModule
- AudioDecryptService → 评估是否可迁入 AudioModule
- PrivateNotesPasswordManager → 评估是否可迁入 AuthState

---

## 7. 代码边界与约束规则

### 7.1 分层约束（必须）

1. `Features/*/Domain` 目录禁止 import `AppKit`、`SwiftUI`。
2. `Features/*/UI` 禁止直接 import `Store`、`Network` 具体实现。
3. `Features/*/Application` 禁止直接访问数据库 SQL。

### 7.2 全局访问约束（必须）

1. 非 Composition 目录禁止新增 `.shared` 依赖。
2. EventBus 订阅必须有生命周期管理（Task/Cancellable 可追踪）。
3. 新增 TODO 必须绑定 spec 编号与计划移除日期。
4. 新增网络请求必须通过 NetworkModule 提供的 API 类，禁止直接使用 URLSession。

### 7.3 复杂度约束（建议）

1. 单文件建议不超过 600 行。
2. 单类型公开方法建议不超过 30 个。
3. 超限必须在 PR 中给出拆分计划。

### 7.4 菜单系统约束（必须，Command 化完成后生效）

1. AppDelegate 的 @objc 菜单方法体不超过 3 行。
2. 禁止在 AppDelegate 或 MenuActionHandler 中新增业务逻辑，所有新菜单动作必须实现为 Command。
3. MenuActionHandler 中的方法只减不增，直到清空删除。

---

## 8. 测试架构升级

### 8.1 测试分层

1. Domain 单元测试：纯规则与状态变换。
2. Application 用例测试：命令执行与事件发布。
3. Integration 测试：Sync/Store/Network 关键链路。
4. UI 冒烟测试：关键入口（菜单命令、导入导出、同步触发）。

### 8.2 近期优先补测

1. 菜单命令链路（undo/redo/cut/copy/paste）可用性测试。
2. 导入流程"内容真实写入"回归测试。
3. Command 模式的单元测试（每个 Command 的 execute 方法）。

---

## 9. 现有 Command 系统审计

### 9.1 已实现的命令

| 命令 | 文件 | 状态 |
|------|------|------|
| CreateNoteCommand | NoteCommands.swift | 已实现，含 UI 弹窗 |
| DeleteNoteCommand | NoteCommands.swift | 已实现，含确认弹窗 |
| ToggleStarCommand | NoteCommands.swift | 已实现 |
| ShareNoteCommand | NoteCommands.swift | 已实现 |
| CreateFolderCommand | NoteCommands.swift | 已实现，含 UI 弹窗 |
| SyncCommand | SyncCommands.swift | 已实现 |
| IncrementalSyncCommand | SyncCommands.swift | 已实现 |
| ShowSettingsCommand | WindowCommands.swift | 已实现 |

### 9.2 CommandDispatcher 设计问题

当前 CommandDispatcher 依赖 AppCoordinator 作为 CommandContext，这意味着所有 Command 都通过 coordinator 访问 State 对象。这个设计在短期内可行，但长期应考虑：

1. CommandContext 是否应该更细粒度（只传入 Command 需要的 State，而非整个 coordinator）。
2. Command 中是否应该包含 UI 逻辑（如 NSAlert 弹窗）— 建议将 UI 交互提取到调用方，Command 只处理业务逻辑。

这些改进可在 Command 化完成后的优化阶段处理，不阻塞当前迁移。

---

## 10. 迁移路线图（修订版，4 阶段）

### 阶段 A：菜单命令链 Command 化（2-3 周）

这是当前代码库最大的单点复杂度，优先解决。

范围：

1. 将 MenuActionHandler 中的格式命令迁移为 FormatCommands（约 20 个）。
2. 将文件命令迁移为 FileCommands（导入、导出、创建，约 15 个）。
3. 将窗口命令迁移为 WindowCommands（平铺、最大化等，约 12 个）。
4. 将视图命令迁移为 ViewCommands（列表/画廊切换、缩放等，约 10 个）。
5. 简化 AppDelegate 的 @objc 方法为 1-2 行 Command 构造 + dispatch。
6. MenuActionHandler 清空后删除。

验收：

1. 所有菜单动作通过 Command 调度。
2. AppDelegate 的菜单方法体均不超过 3 行。
3. MenuActionHandler 文件已删除。
4. 应用功能行为无变化。

对应 spec：123-menu-command-migration

### 阶段 B：架构立规与约束自动化（1-2 周）

范围：

1. 编写架构 ADR 文档（边界、依赖、事件治理规则）。
2. 实现架构检查脚本初版（import 规则、.shared 规则、目录规则）。
3. 集成到 CI，PR 中报告架构违规。
4. 第一级 .shared 单例退出（NetworkMonitor、NetworkErrorHandler、NetworkLogger 迁入 NetworkModule）。

验收：

1. CI 可在 PR 中报告架构违规。
2. 新代码已按新规则落位。
3. NetworkModule 内部 3 个单例已消除。

对应 spec：124-architecture-governance

### 阶段 C：目录纵向切片（3-6 周）

范围：

1. 先迁移 `Notes`、`Sync` 两个核心域到 `Features/*`。
2. 迁移 `Auth`、`Folders`。
3. 其余域按收益推进。
4. 每个域迁移为独立 spec，确保每步可编译可运行。

验收：

1. 80% 的需求改动可在单域内完成。
2. 跨域依赖数量持续下降。
3. project.yml 反映新目录结构。

对应 spec：125-notes-vertical-slice、126-sync-vertical-slice、127+

### 阶段 D：遗留清算与稳态治理（持续）

范围：

1. 清理 Legacy 目录到空。
2. 规则脚本转强制 gate（违规 PR 无法合并）。
3. 第二、三级 .shared 单例评估与退出。
4. 导入流程逻辑断层修复。
5. 菜单编辑命令（undo/redo/cut/copy/paste）补齐实现。

验收：

1. `Legacy/` 为空或仅保留明确到期项。
2. 架构违规 PR 无法合并。
3. 导入流程可真实写入内容。

---

## 11. Spec 拆分建议

| Spec 编号 | 名称 | 阶段 | 风险 | 预估工作量 |
|-----------|------|------|------|-----------|
| 123 | menu-command-migration | A | 中 | 2-3 周 |
| 124 | architecture-governance | B | 低 | 1-2 周 |
| 125 | notes-vertical-slice | C | 高 | 1-2 周 |
| 126 | sync-vertical-slice | C | 高 | 1-2 周 |
| 127 | auth-folders-vertical-slice | C | 中 | 1 周 |
| 128+ | 按需追加 | C/D | - | - |

建议执行顺序：123 → 124 → 125 → 126 → 127+

理由：
- 123（菜单 Command 化）是当前最大痛点，且不依赖目录重组，可独立执行。
- 124（架构立规）为后续 Vertical Slice 迁移建立约束基础。
- 125-127（目录迁移）依赖前两步的基础，按域逐步推进。

---

## 12. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Command 化过程中菜单功能回退 | 用户可见 | 每批 Command 迁移后手动测试全部菜单项 |
| Vertical Slice 迁移破坏 XcodeGen 配置 | 编译失败 | 每次迁移后执行 xcodegen generate + 编译验证 |
| 架构检查脚本误报 | 开发效率下降 | 初期仅报告不阻塞，稳定后转强制 gate |
| .shared 单例退出引入运行时崩溃 | 应用崩溃 | 逐个退出，每个单例退出后完整测试启动链 |
| 大规模目录移动导致 git 历史断裂 | 代码追溯困难 | 使用 git mv 保留历史，每个域一个 commit |

---

## 13. 完成定义（Definition of Done）

满足以下条件，视为顶层架构重构进入稳态：

1. 所有菜单动作通过 Command 模式调度，MenuActionHandler 已删除。
2. 业务核心域已完成 Vertical Slice 迁移。
3. 组合根装配器已按域拆分。
4. EventBus/NotificationCenter 使用边界可被脚本校验。
5. 第一级 .shared 单例已退出。
6. 关键业务链路具备稳定回归测试。
7. 架构违规 PR 无法合并。

