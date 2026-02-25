# 架构改进路线图设计文档

> 审计基线：2026-02-26
> 关联文档：`docs/architecture-next.md`（目标架构）、`docs/plans/TODO`（缺陷清单）

---

## 1. 背景

spec100-spec130 完成了菜单 Command 化、4 个核心域 Vertical Slice、模块工厂、架构治理脚本等基础工作。但审计发现 5 个残留缺陷：

1. 架构门禁 RULE-001 只扫描 `Sources/Model`，漏检 `Features/*/Domain`（已确认 `Note.swift` 有 `import AppKit` 违规，CI 绿灯通过）
2. 关键链路（Command 调度、导入写入、同步队列）缺少回归测试
3. `AppCoordinatorAssembler` 仍是单体装配（约 150 行），未按域拆分
4. 目标目录结构 4 个差距未落地（App 三层、Shared 两层、Editor/Search/Audio 切片、Legacy 目录）
5. 文档残留已过时的 MenuActionHandler 描述

## 2. 设计原则

安全网优先：先让门禁能真正拦住违规，再补关键链路测试，然后才推进结构性迁移。每个阶段的产出都是后续阶段的前置保障。

## 3. 路线图

### 3.1 依赖关系

```
spec-131 (门禁修复)
    │
    ▼
spec-132 (回归测试)
    │
    ├──────────────┐
    ▼              ▼
spec-133        spec-134
(组合根拆分)    (同步队列优化)
    │
    ▼
spec-135 (目录骨架)
    │
    ▼
spec-136 (Editor/Search/Audio 切片)
```

### 3.2 阶段一：门禁修复

spec-131：架构门禁补全

目标：让 RULE-001 真正覆盖所有 Domain 层代码，消除"CI 绿灯但规则失效"的盲区。

范围：
- 扩展 `check_domain_imports` 扫描范围：`Sources/Model` + `Sources/Features/*/Domain`
- 修复现存违规：`Note.swift` 移除 `import AppKit`（未使用 AppKit 类型，直接移除）
- 为架构脚本增加自检用例（至少 RULE-001 正/反样本各 1 个）
- 清理文档中已过时的 MenuActionHandler 描述（architecture-next.md、refactor_all.md）

风险：低
预估：1-2 天
阻塞：后续所有 spec

### 3.3 阶段二：关键链路回归测试

spec-132：回归测试补齐

目标：为后续大规模目录迁移建立自动化安全网。

范围：
- Command 链路测试：验证 CommandDispatcher 能正确调度到具体 Command 的 execute 方法
- 导入流程测试：ImportMarkdownCommand / ImportNotesCommand 的"内容真实写入"断言（验证 ImportContentConverter 产出非空 XML）
- 同步队列测试：文件丢失失败路径、nextRetryAt 门控、二次入队场景
- 组合根冒烟测试：AppCoordinatorAssembler.buildDependencies() 产出的关键服务非空

风险：中（需要为 Command 和 Assembler 设计可测试的注入点）
预估：3-5 天
依赖：spec-131

### 3.4 阶段三：组合根拆分 + 目录骨架

spec-133：组合根按域拆分

目标：将 AppCoordinatorAssembler 的单体装配拆分为按域的 FeatureAssembler，降低膨胀风险。

范围：
- 拆分为 5 个 FeatureAssembler：NotesAssembler、SyncAssembler、AuthAssembler、EditorAssembler、AudioAssembler
- 每个 Assembler 负责构建本域的依赖子图，返回结构化产出
- 主装配器（AppCoordinatorAssembler）仅聚合各域 Assembler 的产出 + 跨域接线
- wireEditorContext 下沉到 EditorAssembler

风险：中（跨域依赖接线需要仔细处理）
预估：2-3 天
依赖：spec-132（冒烟测试框架已就位，拆分后可立即验证）

spec-135：目录骨架建立

目标：建立 architecture-next 第 5 节定义的目标目录结构骨架。只建壳 + 首批迁移，不做大规模搬迁。

范围：
- 建立 `Sources/App/Bootstrap/`，迁入 AppDelegate、AppLaunchAssembler
- 建立 `Sources/App/Composition/`，迁入 AppCoordinatorAssembler（及拆分后的各域 Assembler）
- 建立 `Sources/App/Runtime/`，迁入 AppStateManager
- 建立 `Sources/Shared/Kernel/`（先建壳，标注 EventBus、LogService 迁移计划）
- 建立 `Sources/Shared/UICommons/`（先建壳，标注共享 UI 组件迁移边界）
- 建立 `Sources/Legacy/` 过渡规范：仅接收临时兼容代码，新增文件必须标注 spec 编号与移除日期
- 每次迁移后执行 xcodegen generate + 编译验证

风险：中（大量文件移动影响 project.yml 和 import 路径）
预估：2-3 天
依赖：spec-133

### 3.5 阶段四：剩余域切片 + 持续治理

spec-136：Editor / Search / Audio 纵向切片

目标：将散落在旧目录的三个域迁入 Features/ 结构。

范围：
- Search 域：`State/SearchState` -> `Features/Search/Application/`，相关 UI/服务调用同步更新
- Editor 域：`Service/Editor/` 核心代码 -> `Features/Editor/`（EditorModule 保留为工厂，内部类按四层组织）
- Audio 域：`Service/Audio/` 核心代码 -> `Features/Audio/`（AudioModule 保留为工厂）
- 每个域独立可编译验证，一个域一个 commit

风险：中-高（Editor 域依赖最复杂，约 20 个类）
预估：1-2 周
依赖：spec-135 + spec-132

spec-134：同步队列深度优化

目标：提升 OperationProcessor 的可观测性和可维护性。

范围：
- processQueue 批处理路径增加可观测日志（首轮/次轮执行数量、跳过原因）
- 统一 maxRetryCount 配置源（消除 OperationProcessor 与 UnifiedOperationQueue 的参数分散）
- 提取 OperationFailurePolicy（错误分类 + 重试决策），减少 Processor 体积

风险：中
预估：2-3 天
依赖：spec-132（同步队列回归测试已就位）

## 4. spec-130 状态

spec-130（导入流程修复）已全部完成，从 TODO 中移除。

## 5. 原 TODO 中 spec-137 的处理

原 spec-137（Legacy 过渡规范 + 目录差距看板）合并进 spec-135，不再单独开 spec。

## 6. 验收标准

路线图整体完成时，应满足 architecture-next.md 第 13 节"完成定义"中的以下条目：

1. 架构违规 PR 无法合并（spec-131）
2. 关键业务链路具备稳定回归测试（spec-132）
3. 组合根装配器已按域拆分（spec-133）
4. 业务核心域已完成 Vertical Slice 迁移（spec-136 完成后，7 个域全部就位）
