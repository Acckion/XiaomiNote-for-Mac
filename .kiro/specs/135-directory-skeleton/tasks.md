# spec-135：目录骨架建立 — 任务清单

参考文档：
- 需求：`.kiro/specs/135-directory-skeleton/requirements.md`
- 设计：`.kiro/specs/135-directory-skeleton/design.md`

---

## 任务 1：建立 App 三层目录并迁移文件

- [ ] 1. App 三层目录迁移
  - [ ] 1.1 创建 `Sources/App/Bootstrap/` 目录，将 AppDelegate.swift、AppLaunchAssembler.swift 迁入
  - [ ] 1.2 创建 `Sources/App/Runtime/` 目录，将 AppStateManager.swift 迁入
  - [ ] 1.3 创建 `Sources/App/Composition/` 目录，将 AppCoordinatorAssembler.swift 及各域 Assembler（spec-133 产出）从 `Sources/Coordinator/` 迁入
  - [ ] 1.4 执行 `xcodegen generate` + 编译验证

## 任务 2：建立 Shared 两层目录（建壳）

- [ ] 2. Shared 目录建壳
  - [ ] 2.1 创建 `Sources/Shared/Kernel/README.md`，标注计划迁入 EventBus、LogService
  - [ ] 2.2 创建 `Sources/Shared/UICommons/README.md`，标注计划迁入共享 UI 组件
  - [ ] 2.3 执行 `xcodegen generate` + 编译验证

## 任务 3：建立 Legacy 过渡目录

- [ ] 3. Legacy 目录建立
  - [ ] 3.1 创建 `Sources/Legacy/README.md`，包含过渡规范说明（文件标注格式、审计频率）
  - [ ] 3.2 执行 `xcodegen generate` + 编译验证

## 任务 4：更新文档

- [ ] 4. 文档同步更新
  - [ ] 4.1 更新 AGENTS.md 中的项目结构描述，反映新的目录布局
  - [ ] 4.2 提交所有变更
