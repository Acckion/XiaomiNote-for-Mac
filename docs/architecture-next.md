# MiNoteMac 顶层架构重构蓝图（Architecture Next）

## 1. 文档目的

本文档定义 spec100-spec119 之后的下一阶段顶层架构方向。
目标不是继续做“文件拆分式重构”，而是建立清晰、稳定、可约束的系统边界，降低未来维护成本并提升可扩展性。

适用时间范围：2026-02-25 起的后续重构周期。

---

## 2. 当前问题（顶层视角）

spec100-spec119 已完成大量模块级重构，但项目在顶层仍存在以下结构性问题：

1. 目录组织以技术层为主（Network/Store/State/View），功能改动跨目录跳转频繁。
2. 组合根（AppCoordinator）过胖，装配职责与业务职责局部混杂。
3. 菜单/窗口动作/状态同步分散在 AppDelegate、MenuManager、MenuActionHandler、MainWindowController 多层。
4. 主干网络栈与过渡实现并存（NetworkModule vs NetworkClient/Default*Service 残留）。
5. EventBus、NotificationCenter、直接调用混用，缺少明确边界规则。
6. 缺少架构约束自动化，重构后容易回退到“局部可用、整体失序”。

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

---

## 5. 目录重组方案（Vertical Slice）

建议从当前技术分层目录逐步演进到业务域目录：

```text
Sources/
├── App/
│   ├── Bootstrap/
│   ├── Composition/
│   └── Runtime/
├── Shared/
│   ├── Kernel/              # LogService、EventBus、基础工具
│   ├── Contracts/           # 跨域协议与通用DTO
│   └── UICommons/
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

说明：

1. `Legacy/` 是临时缓冲区，所有迁入文件必须带“删除截止版本”。
2. 新增功能禁止落入旧技术层目录。

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

1. Apple 系统通知。
2. AppKit 内部桥接且无业务语义的局部通知。

任何新增业务通知默认走 EventBus。

### 6.3 引入 Command 模型统一入口

菜单、工具栏、快捷键、窗口动作统一转换为 Command。

流程：

1. UI 发出 Command。
2. Application 层 CommandHandler 执行。
3. 按需发布 EventBus 事件。

收益：同一业务动作的多入口不再分叉实现。

### 6.4 组合根瘦身

将 `AppCoordinator` 拆分为：

1. `RootComposition`（顶层装配）
2. `FeatureAssembler`（按域装配）
3. `RuntimeOrchestrator`（启动时序）

`AppCoordinator` 仅保留窗口协同和导航职责。

### 6.5 单一网络主干

确定唯一主干：`NetworkModule -> APIClient -> Domain APIs`。

策略：

1. 清理 `NetworkClient` 与 `NetworkClientProtocol`。
2. 清理或归档未接入主干的 `DefaultAuthenticationService`、`DefaultImageService`。
3. 杜绝第二套网络抽象再次出现。

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

### 7.3 复杂度约束（建议）

1. 单文件建议不超过 600 行。
2. 单类型公开方法建议不超过 30 个。
3. 超限必须在 PR 中给出拆分计划。

---

## 8. 测试架构升级

### 8.1 测试分层

1. Domain 单元测试：纯规则与状态变换。
2. Application 用例测试：命令执行与事件发布。
3. Integration 测试：Sync/Store/Network 关键链路。
4. UI 冒烟测试：关键入口（菜单命令、导入导出、同步触发）。

### 8.2 近期优先补测

1. OperationProcessor 拆分后的行为一致性测试。
2. 菜单命令链路（undo/redo/cut/copy/paste）可用性测试。
3. 导入流程“内容真实写入”回归测试。

---

## 9. 顶层重构前置任务（必须先完成）

在进入顶层架构迁移前，先完成以下“清障任务”，避免在重构中被历史耦合反复阻塞。

### 9.1 前置任务清单（按优先级）

1. 菜单命令链路收敛
   - 目标：将菜单、工具栏、快捷键入口先统一到可替换命令调用，消除当前多入口分叉行为。
   - 涉及模块：`MenuActionHandler`、`MainWindowController+Actions`、`MenuManager`。
   - 完成标准：`undo/redo/cut/copy/paste/selectAll` 全部具备真实行为，禁止空实现占位。

2. OperationProcessor 第一层拆分
   - 目标：先把超大执行器拆出按操作类型的 handler 接口（note/folder/file），降低单点复杂度。
   - 涉及模块：`OperationProcessor`、`UnifiedOperationQueue`。
   - 完成标准：主流程行为保持一致，重试策略与错误分类回归通过。

3. 过渡网络链路清理
   - 目标：消除并行网络主干，统一到 `NetworkModule -> APIClient -> 各 API`。
   - 涉及模块：`NetworkClient`、`NetworkClientProtocol`、`DefaultAuthenticationService`、`DefaultImageService`（未接入主干部分）。
   - 完成标准：主干调用路径无过渡链路依赖，相关死代码已移除或归档。

4. 组合根轻量瘦身
   - 目标：将 `AppCoordinator` 的装配逻辑先抽到 assembler，减少后续目录迁移阻力。
   - 涉及模块：`AppCoordinator` 与启动装配链路。
   - 完成标准：`AppCoordinator` 仅保留协调职责，不承载大块实例构建逻辑。

### 9.2 前置任务验收门槛

1. 前置任务全部通过回归测试后，才进入“目录级 Vertical Slice 迁移”。
2. 任一前置任务未完成，不启动对应域的目录搬迁。
3. 前置任务完成后更新 Legacy 清单，避免“已清障模块”再次回流。

---

## 10. 迁移路线图（建议 4 阶段）

### 阶段 A：架构立规（1-2 周）

产出：

1. 架构 ADR（边界、依赖、事件治理、网络主干单一化）。
2. 架构检查脚本初版（import 规则、shared 规则、目录规则）。
3. Legacy 清单与退出时间表。

验收：

1. CI 可在 PR 中报告架构违规。
2. 新代码已按新规则落位。

### 阶段 B：高风险主链迁移（2-4 周）

范围：

1. 菜单命令链（Command 化）。
2. 导入导出流程下沉到 Application UseCase。
3. OperationProcessor 拆分为多 handler。

验收：

1. 三条链路的回归测试通过。
2. 用户可见占位行为显著减少。

### 阶段 C：目录纵向切片（3-6 周）

范围：

1. 先迁移 `Notes`、`Sync` 两个核心域到 `Features/*`。
2. 迁移 `Auth`、`Folders`。
3. 其余域按收益推进。

验收：

1. 80% 的需求改动可在单域内完成。
2. 跨域依赖数量持续下降。

### 阶段 D：遗留清算与稳态治理（持续）

范围：

1. 清理 `NetworkClient` 过渡链路。
2. 清理 Legacy 目录到空。
3. 规则脚本转强制 gate。

验收：

1. `Legacy/` 为空或仅保留明确到期项。
2. 架构违规 PR 无法合并。

---

## 11. 对现有 spec 体系的衔接建议

为了兼容当前 spec 驱动开发流程，建议新增“架构级 spec 模板”：

1. `spec-120` 架构约束与目录治理
2. `spec-121` Command 统一入口重构（菜单/窗口/快捷键）
3. `spec-122` OperationProcessor 拆分重构
4. `spec-123` Vertical Slice 第一阶段（Notes + Sync）
5. `spec-124` 过渡网络链路清理（NetworkClient 退场）

每个架构级 spec 必须包含：

1. 边界规则
2. 回归测试清单
3. 回滚策略
4. 迁移完成定义（DoD）

---

## 12. 风险与缓解

### 风险 1：迁移期间功能回归

缓解：

1. 先命令链与用例层，后目录搬迁。
2. 每阶段必须有可回归测试再进入下一阶段。

### 风险 2：团队执行不一致

缓解：

1. 将规则写进 CI，不依赖人工自觉。
2. ADR 和 PR 模板绑定必填项。

### 风险 3：重构周期过长造成疲劳

缓解：

1. 每个阶段拆为可交付的小里程碑。
2. 先做“高痛点高收益”链路，不做全量搬家。

---

## 13. 完成定义（Definition of Done）

满足以下条件，视为顶层架构重构进入稳态：

1. 业务核心域已完成 Vertical Slice 迁移。
2. 组合根完成瘦身，业务流程不再驻留 AppCoordinator。
3. EventBus/NotificationCenter 使用边界可被脚本校验。
4. 无并行网络主干（`NetworkClient` 过渡链路已退出）。
5. 关键业务链路具备稳定回归测试。

---

## 14. 立即行动清单（建议）

1. 本周落地架构 ADR 和检查脚本草案。
2. 下周启动 Command 统一入口重构（菜单/窗口动作）。
3. 同步启动 OperationProcessor 拆分设计稿。
4. 在下一轮 spec 中正式纳入 `architecture-next` 作为基线文档。
