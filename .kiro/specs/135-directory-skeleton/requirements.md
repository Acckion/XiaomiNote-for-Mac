# spec-135：目录骨架建立 + Target 合并

## 背景

`docs/architecture-next.md` 第 5 节定义了目标目录结构，但当前代码库与目标存在 4 个差距：App 三层目录未成型、Shared 两层未建立、Legacy 过渡目录未启用。此外，MiNoteLibrary / MiNoteMac 双 target 结构是历史遗留，导致 Assembler 等文件无法自由迁移到 App 目录下。本 spec 合并 target 并建立目录骨架。

## 需求

### REQ-0：合并 Target

将 MiNoteLibrary framework target 和 MiNoteMac application target 合并为单一 MiNoteMac target：

- 删除 MiNoteLibrary target
- MiNoteMac target 的 sources 覆盖整个 `Sources/` 目录
- 测试 target 改为依赖 MiNoteMac（`@testable import MiNoteMac`）
- 删除 Sources 中所有 `import MiNoteLibrary`
- 保留现有 `public` 访问控制（不影响编译，后续按需清理）

### REQ-1：App 三层目录

建立以下目录并迁入对应文件：

- `Sources/App/Bootstrap/`：迁入 AppDelegate.swift、AppLaunchAssembler.swift
- `Sources/App/Composition/`：迁入 AppCoordinatorAssembler.swift 及各域 Assembler（spec-133 产出）
- `Sources/App/Runtime/`：迁入 AppStateManager.swift

迁移后 `Sources/App/` 根目录保留 Assets.xcassets、App.swift 和菜单相关文件。

### REQ-2：Coordinator 目录精简

Assembler 迁出后，`Sources/Coordinator/` 仅保留 AppCoordinator.swift。

### REQ-3：Shared 两层目录

建立以下目录（先建壳，标注迁移计划）：

- `Sources/Shared/Kernel/`：放置 README.md 标注计划迁入 EventBus、LogService
- `Sources/Shared/UICommons/`：放置 README.md 标注计划迁入共享 UI 组件

### REQ-4：Legacy 过渡目录

建立 `Sources/Legacy/` 目录，放置 README.md 说明过渡规范。

### REQ-5：迁移约束

- 每次文件迁移后执行 `xcodegen generate` + 编译验证
- 使用 `git mv` 保留文件历史
- 更新 AGENTS.md 中的项目结构描述

## 验收标准

1. project.yml 中只有 MiNoteMac 和 MiNoteLibraryTests 两个 target
2. 编译通过，测试通过
3. `Sources/App/Bootstrap/`、`Composition/`、`Runtime/` 目录存在且包含对应文件
4. `Sources/Shared/Kernel/`、`UICommons/` 目录存在
5. `Sources/Legacy/` 目录存在且包含规范说明
6. AGENTS.md 项目结构已更新
