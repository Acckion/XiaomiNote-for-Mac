# spec-133：组合根按域拆分 — 任务清单

参考文档：
- 需求：`.kiro/specs/133-assembler-domain-split/requirements.md`
- 设计：`.kiro/specs/133-assembler-domain-split/design.md`

---

## 任务 1：创建 NotesAssembler

- [ ] 1. 提取笔记域装配逻辑
  - [ ] 1.1 创建 `Sources/Coordinator/NotesAssembler.swift`，定义 Output 结构体和 assemble 方法
  - [ ] 1.2 从 AppCoordinatorAssembler 中提取 NoteStore、NoteListState、NoteEditorState、NotePreviewService 的构建逻辑
  - [ ] 1.3 编译验证

## 任务 2：创建 SyncAssembler

- [ ] 2. 提取同步域装配逻辑
  - [ ] 2.1 创建 `Sources/Coordinator/SyncAssembler.swift`，定义 Output 结构体和 assemble 方法
  - [ ] 2.2 从 AppCoordinatorAssembler 中提取 SyncEngine、SyncState、StartupSequenceManager、ErrorRecoveryService、NetworkRecoveryHandler 的构建逻辑
  - [ ] 2.3 编译验证

## 任务 3：创建 AuthAssembler

- [ ] 3. 提取认证域装配逻辑
  - [ ] 3.1 创建 `Sources/Coordinator/AuthAssembler.swift`，定义 Output 结构体和 assemble 方法
  - [ ] 3.2 从 AppCoordinatorAssembler 中提取 PassTokenManager、AuthState、SearchState 的构建逻辑
  - [ ] 3.3 编译验证

## 任务 4：创建 EditorAssembler 和 AudioAssembler

- [ ] 4. 提取编辑器和音频域装配逻辑
  - [ ] 4.1 创建 `Sources/Coordinator/EditorAssembler.swift`，将 wireEditorContext 逻辑下沉到此
  - [ ] 4.2 创建 `Sources/Coordinator/AudioAssembler.swift`，提取 AudioPanelViewModel、MemoryCacheManager 构建逻辑
  - [ ] 4.3 编译验证

## 任务 5：简化主装配器

- [ ] 5. 重构 AppCoordinatorAssembler
  - [ ] 5.1 修改 `buildDependencies()` 方法，调用各域 Assembler 获取产出
  - [ ] 5.2 主方法仅保留：模块工厂创建、各域 Assembler 调用、跨域接线、Dependencies 组装
  - [ ] 5.3 确认 `buildDependencies()` 方法体不超过 40 行
  - [ ] 5.4 编译验证，运行组合根冒烟测试（如 spec-132 已完成）

## 任务 6：项目配置与提交

- [ ] 6. 更新项目配置
  - [ ] 6.1 执行 `xcodegen generate`
  - [ ] 6.2 完整编译验证
  - [ ] 6.3 提交所有变更
