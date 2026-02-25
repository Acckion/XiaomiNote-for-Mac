# spec-135：目录骨架建立 + Target 合并 — 任务清单

参考文档：
- 需求：`.kiro/specs/135-directory-skeleton/requirements.md`
- 设计：`.kiro/specs/135-directory-skeleton/design.md`

---

## 任务 1：合并 Target

- [x] 1. 合并 MiNoteLibrary 和 MiNoteMac 为单一 target
  - [x] 1.1 重写 project.yml：删除 MiNoteLibrary target，MiNoteMac sources 覆盖整个 Sources/，测试 target 依赖 MiNoteMac
  - [x] 1.2 删除 Sources 中所有 `import MiNoteLibrary`（7 处）
  - [x] 1.3 修改 Tests 中所有 `@testable import MiNoteLibrary` 为 `@testable import MiNoteMac`（7 处）
  - [x] 1.4 执行 `xcodegen generate` + 编译验证 + 测试验证

## 任务 2：建立 App 三层目录并迁移文件

- [-] 2. App 三层目录迁移
  - [x] 2.1 创建 `Sources/App/Bootstrap/`，迁入 AppDelegate.swift、AppLaunchAssembler.swift
  - [x] 2.2 创建 `Sources/App/Runtime/`，迁入 AppStateManager.swift
  - [x] 2.3 创建 `Sources/App/Composition/`，迁入 AppCoordinatorAssembler.swift 及各域 Assembler（从 Sources/Coordinator/）
  - [-] 2.4 执行 `xcodegen generate` + 编译验证

## 任务 3：建立 Shared 两层目录 + Legacy 目录

- [ ] 3. Shared 和 Legacy 目录建立
  - [ ] 3.1 创建 `Sources/Shared/Kernel/README.md`，标注计划迁入 EventBus、LogService
  - [ ] 3.2 创建 `Sources/Shared/UICommons/README.md`，标注计划迁入共享 UI 组件
  - [ ] 3.3 创建 `Sources/Legacy/README.md`，包含过渡规范说明
  - [ ] 3.4 执行 `xcodegen generate` + 编译验证

## 任务 4：更新文档

- [ ] 4. 文档同步更新
  - [ ] 4.1 更新 AGENTS.md 中的项目结构描述
  - [ ] 4.2 提交所有变更
