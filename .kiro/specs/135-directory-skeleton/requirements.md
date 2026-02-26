# spec-135：目录骨架建立

## 背景

`docs/architecture-next.md` 第 5 节定义了目标目录结构，但当前代码库与目标存在 4 个差距：App 三层目录未成型、Shared 两层未建立、Legacy 过渡目录未启用。本 spec 建立骨架并完成首批迁移。

## 需求

### REQ-1：App 三层目录

建立以下目录并迁入对应文件：

- `Sources/App/Bootstrap/`：迁入 AppDelegate.swift、AppLaunchAssembler.swift
- `Sources/App/Composition/`：迁入 AppCoordinatorAssembler.swift 及各域 Assembler（spec-133 产出）
- `Sources/App/Runtime/`：迁入 AppStateManager.swift

迁移后 `Sources/App/` 根目录仅保留 Assets.xcassets 和 App.swift（SwiftUI 入口）。

### REQ-2：Shared 两层目录

建立以下目录（先建壳，标注迁移计划）：

- `Sources/Shared/Kernel/`：放置 README.md 标注计划迁入 EventBus、LogService
- `Sources/Shared/UICommons/`：放置 README.md 标注计划迁入共享 UI 组件

实际迁移在后续 spec 中执行，本 spec 只建壳。

### REQ-3：Legacy 过渡目录

建立 `Sources/Legacy/` 目录，放置 README.md 说明过渡规范：
- 仅接收临时兼容代码
- 新增文件必须标注 spec 编号与移除日期
- 定期审计清理

### REQ-4：迁移约束

- 每次文件迁移后执行 `xcodegen generate` + 编译验证
- 使用 `git mv` 保留文件历史
- 更新 AGENTS.md 中的项目结构描述

## 验收标准

1. `Sources/App/Bootstrap/`、`Sources/App/Composition/`、`Sources/App/Runtime/` 目录存在且包含对应文件
2. `Sources/Shared/Kernel/`、`Sources/Shared/UICommons/` 目录存在
3. `Sources/Legacy/` 目录存在且包含规范说明
4. 编译通过
5. AGENTS.md 项目结构已更新
