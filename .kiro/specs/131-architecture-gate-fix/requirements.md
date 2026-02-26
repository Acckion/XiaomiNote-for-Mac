# spec-131：架构门禁补全

## 背景

RULE-001（Domain 层 import 检查）当前只扫描 `Sources/Model`，而 4 个核心域的 Domain 层已迁移到 `Features/*/Domain`。导致 Domain 层违规可以"CI 绿灯通过"。已确认 `Sources/Features/Notes/Domain/Note.swift` 存在 `import AppKit` 违规。

## 需求

### REQ-1：扩展 RULE-001 扫描范围

`check_domain_imports` 函数必须同时扫描：
- `Sources/Model`（旧目录兼容）
- `Sources/Features/*/Domain`（新 Vertical Slice 目录）

两个目录中任何 `.swift` 文件包含 `import AppKit` 或 `import SwiftUI` 均报告为 error 级别违规（除非标注 `// arch-ignore`）。

### REQ-2：修复现存 Domain 违规

`Sources/Features/Notes/Domain/Note.swift` 移除 `import AppKit`。该文件未使用任何 AppKit 类型，`import AppKit` 为冗余引入。

### REQ-3：架构脚本自检用例

为 `check-architecture.sh` 增加自检模式（`--self-test`），至少覆盖：
- RULE-001 正样本：Domain 目录中无 AppKit/SwiftUI import 的文件，脚本不报告违规
- RULE-001 反样本：Domain 目录中有 `import AppKit` 的文件，脚本报告 error

自检通过时输出"自检通过"，失败时输出具体失败项并返回非零退出码。

### REQ-4：清理文档残留

以下文档中关于 MenuActionHandler 的描述已过时（MenuActionHandler 已删除），需要更新：
- `docs/architecture-next.md`：第 2.2 节问题 1、第 6.3 节迁移策略、第 7.4 节约束
- `docs/refactor_all.md`：如有 MenuActionHandler 相关描述

## 验收标准

1. `./scripts/check-architecture.sh --strict` 在当前代码库上通过（0 error）
2. `Note.swift` 不再包含 `import AppKit`
3. `./scripts/check-architecture.sh --self-test` 通过
4. 文档中不再有"MenuActionHandler 待删除"类描述
