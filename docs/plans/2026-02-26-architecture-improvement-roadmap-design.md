# 架构改进路线图设计文档（归档）

> 状态：已完成归档
> 初版日期：2026-02-26
> 归档日期：2026-02-26
> 对应主文档：`docs/architecture-next.md`

## 1. 文档说明

本文档原用于承载 spec-131 ~ spec-136 的执行路线图。  
相关任务已完成，本文档转为归档记录，不再作为待办入口。

## 2. 已完成项

- spec-131：架构门禁修复（RULE-001 覆盖 `Sources/Features/*/Domain`）。
- spec-132：关键链路回归测试补齐（Command/导入/同步队列）。
- spec-133：组合根按域拆分（Notes/Sync/Auth/Editor/Audio Assembler）。
- spec-134：同步队列深度治理（失败策略与可观测性优化）。
- spec-135：目录骨架落地（App 三层 + Shared 两层）。
- spec-136：Editor/Search/Audio 纵向切片完成。

## 3. 当前维护入口

- 当前收尾任务统一维护在：`docs/plans/TODO`。
- 架构目标与 DoD 统一维护在：`docs/architecture-next.md`。
