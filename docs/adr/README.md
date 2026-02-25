# 架构决策记录（ADR）

本目录包含 MiNoteMac 项目的架构决策记录。

## 什么是 ADR

ADR（Architecture Decision Record）用于记录和追踪关键架构决策及其理由。每个 ADR 描述一个具体的架构约束或规则，包含决策背景、具体规则、影响和自动化检查方式。

## ADR 索引

| 编号 | 标题 | 状态 | 相关 Spec |
|------|------|------|-----------|
| [ADR-001](ADR-001-dependency-direction.md) | 依赖方向规则 | 已采纳 | spec-125 |
| [ADR-002](ADR-002-event-governance.md) | 事件治理规则 | 已采纳 | spec-125 |
| [ADR-003](ADR-003-network-backbone.md) | 网络主干规则 | 已采纳 | spec-114, spec-125 |
| [ADR-004](ADR-004-shared-singleton-policy.md) | .shared 使用规则 | 已采纳 | spec-118, spec-125 |

## ADR 模板

新增 ADR 时请遵循以下格式：

```markdown
# ADR-{编号}: {标题}

## 状态
已采纳 | 已废弃 | 已取代

## 上下文
描述决策背景和驱动因素。

## 决策
具体的架构规则和约束。

## 后果
正面影响和需要注意的代价。

## 自动化检查
对应的检查脚本规则名称（如有）。

## 相关 Spec
- spec-{编号}: {名称}
```

## 使用说明

- 新增架构规则时，创建新的 ADR 文件并更新本索引
- ADR 编号递增，已发布的 ADR 不可修改内容，只能通过新 ADR 取代
- 如需废弃某条 ADR，将状态改为"已废弃"或"已取代"，并注明取代它的 ADR 编号
