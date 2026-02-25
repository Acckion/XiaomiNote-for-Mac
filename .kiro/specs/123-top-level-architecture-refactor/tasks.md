# 顶层架构重构 — 主 Spec 任务清单

本 spec 为主控 spec，任务项为子 spec 的推进检查点，不包含具体实现代码。

参考文档：
- 架构蓝图：`docs/architecture-next.md`
- 设计文档：`.kiro/specs/123-top-level-architecture-refactor/design.md`

---

## 阶段 A：菜单命令链 Command 化

- [ ] 1. 创建并完成 spec 124-menu-command-migration
  - [x] 1.1 创建 spec 124 的 requirements.md、design.md、tasks.md
  - [ ] 1.2 实施 spec 124（格式命令迁移）
  - [ ] 1.3 实施 spec 124（文件命令迁移）
  - [ ] 1.4 实施 spec 124（窗口命令迁移）
  - [ ] 1.5 实施 spec 124（视图命令迁移）
  - [ ] 1.6 清理 MenuActionHandler，简化 AppDelegate
  - [ ] 1.7 手动测试验收，合并分支
  - [ ] 1.8 回到主 spec，更新状态，评估后续计划

## 阶段 B：架构立规与约束自动化

- [x] 2. 创建并完成 spec 125-architecture-governance
  - [x] 2.1 创建 spec 125 的 requirements.md、design.md、tasks.md
  - [x] 2.2 编写架构 ADR 文档
  - [x] 2.3 实现架构检查脚本
  - [x] 2.4 集成到 CI
  - [x] 2.5 第一级 .shared 单例退出
  - [x] 2.6 手动测试验收，合并分支
  - [x] 2.7 回到主 spec，更新状态，评估后续计划

## 阶段 C：目录纵向切片

- [x] 3. 创建并完成 spec 126-notes-vertical-slice
  - [x] 3.1 创建 spec 126 的 requirements.md、design.md、tasks.md
  - [x] 3.2 实施 Notes 域迁移
  - [x] 3.3 更新 project.yml，编译验证
  - [x] 3.4 手动测试验收，合并分支
  - [x] 3.5 回到主 spec，更新状态

- [ ] 4. 创建并完成 spec 127-sync-vertical-slice
  - [ ] 4.1 创建 spec 127 的 requirements.md、design.md、tasks.md
  - [ ] 4.2 实施 Sync 域迁移
  - [ ] 4.3 更新 project.yml，编译验证
  - [ ] 4.4 手动测试验收，合并分支
  - [ ] 4.5 回到主 spec，更新状态

- [ ] 5. 创建并完成 spec 128-auth-folders-vertical-slice
  - [ ] 5.1 创建 spec 128 的 requirements.md、design.md、tasks.md
  - [ ] 5.2 实施 Auth + Folders 域迁移
  - [ ] 5.3 更新 project.yml，编译验证
  - [ ] 5.4 手动测试验收，合并分支
  - [ ] 5.5 回到主 spec，更新状态

## 阶段 D：遗留清算与稳态治理

- [ ] 6. 遗留清算
  - [ ] 6.1 清理 Legacy 目录
  - [ ] 6.2 规则脚本转强制 gate
  - [ ] 6.3 第二、三级 .shared 单例评估与退出
  - [ ] 6.4 导入流程逻辑断层修复
  - [ ] 6.5 菜单编辑命令补齐实现

## 收尾

- [ ] 7. 整体验收
  - [ ] 7.1 确认所有完成定义条目已满足
  - [ ] 7.2 更新 AGENTS.md 反映新架构
  - [ ] 7.3 更新 docs/architecture-next.md 标记为已完成
  - [ ] 7.4 更新 docs/spec-catalog.md
