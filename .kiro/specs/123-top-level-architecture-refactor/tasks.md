# 顶层架构重构 — 主 Spec 任务清单

本 spec 为主控 spec，任务项为子 spec 的推进检查点，不包含具体实现代码。

参考文档：
- 架构蓝图：`docs/architecture-next.md`
- 设计文档：`.kiro/specs/123-top-level-architecture-refactor/design.md`

---

## 阶段 A：菜单命令链 Command 化

- [x] 1. 创建并完成 spec 124-menu-command-migration
  - [x] 1.1 创建 spec 124 的 requirements.md、design.md、tasks.md
  - [x] 1.2 实施 spec 124（格式命令迁移）
  - [x] 1.3 实施 spec 124（文件命令迁移）
  - [x] 1.4 实施 spec 124（窗口命令迁移）
  - [x] 1.5 实施 spec 124（视图命令迁移）
  - [x] 1.6 清理 MenuActionHandler，简化 AppDelegate
  - [x] 1.7 手动测试验收，合并分支
  - [x] 1.8 回到主 spec，更新状态，评估后续计划

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

- [x] 4. 创建并完成 spec 127-sync-vertical-slice
  - [x] 4.1 创建 spec 127 的 requirements.md、design.md、tasks.md
  - [x] 4.2 实施 Sync 域迁移
  - [x] 4.3 更新 project.yml，编译验证
  - [x] 4.4 手动测试验收，合并分支
  - [x] 4.5 回到主 spec，更新状态

- [x] 5. 创建并完成 spec 128-auth-folders-vertical-slice
  - [x] 5.1 创建 spec 128 的 requirements.md、design.md、tasks.md
  - [x] 5.2 实施 Auth + Folders 域迁移
  - [x] 5.3 更新 project.yml，编译验证
  - [x] 5.4 手动测试验收，合并分支
  - [x] 5.5 回到主 spec，更新状态

## 阶段 D：遗留清算与稳态治理

- [ ] 6. 创建并完成 spec 129-architecture-governance-hardening（6.1 + 6.2 + 6.3 + 6.5）
  - [ ] 6.1 确认 Legacy 目录不存在（零工作量）
  - [ ] 6.2 修复架构检查脚本（ALLOWED_SHARED 路径、RULE-004 豁免、CI 强制门禁）
  - [ ] 6.3 删除已废弃 .shared 单例（NetworkMonitor/NetworkErrorHandler/NetworkLogger/PreviewHelper）
  - [ ] 6.4 评估并迁移 PerformanceService / PrivateNotesPasswordManager
  - [ ] 6.5 验证编辑命令已工作，修正 architecture-next.md 过时描述
  - [ ] 6.6 手动测试验收，合并分支

- [ ] 7. 创建并完成 spec 130-import-flow-fix（原 6.4）
  - [ ] 7.1 实现 ImportContentConverter（纯文本/Markdown/RTF → 小米笔记 XML）
  - [ ] 7.2 修复 ImportNotesCommand 和 ImportMarkdownCommand 的导入逻辑
  - [ ] 7.3 编译验证
  - [ ] 7.4 手动测试验收，合并分支

## 收尾

- [ ] 8. 整体验收
  - [ ] 8.1 确认所有完成定义条目已满足
  - [ ] 8.2 更新 AGENTS.md 反映新架构
  - [ ] 8.3 更新 docs/architecture-next.md 标记为已完成
  - [ ] 8.4 更新 docs/spec-catalog.md
