# spec-136：Editor / Search / Audio 纵向切片 — 任务清单

参考文档：
- 需求：`.kiro/specs/136-editor-search-audio-slice/requirements.md`
- 设计：`.kiro/specs/136-editor-search-audio-slice/design.md`

---

## 任务 1：Search 域迁移

- [ ] 1. 迁移 Search 域
  - [ ] 1.1 创建 `Features/Search/` 四层目录结构（Domain/Infrastructure/Application/UI）
  - [ ] 1.2 `git mv Sources/State/SearchState.swift Sources/Features/Search/Application/`
  - [ ] 1.3 执行 `xcodegen generate` + 编译验证
  - [ ] 1.4 提交：`refactor(search): 迁移 SearchState 到 Features/Search`

## 任务 2：Editor 域迁移

- [ ] 2. 迁移 Editor 域
  - [ ] 2.1 创建 `Features/Editor/` 四层目录结构（Domain/Infrastructure/Application/UI）
  - [ ] 2.2 迁移 Domain 层：EditorConfiguration.swift、TitleIntegrationError.swift → `Features/Editor/Domain/`
  - [ ] 2.3 迁移 Infrastructure 层：FormatConverter/ 整个目录 → `Features/Editor/Infrastructure/FormatConverter/`
  - [ ] 2.4 迁移 Application 层：NoteEditingCoordinator.swift → `Features/Editor/Application/`
  - [ ] 2.5 执行 `xcodegen generate` + 编译验证
  - [ ] 2.6 提交：`refactor(editor): 迁移编辑器域代码到 Features/Editor`

## 任务 3：Audio 域迁移

- [ ] 3. 迁移 Audio 域
  - [ ] 3.1 创建 `Features/Audio/` 四层目录结构（Domain/Infrastructure/Application/UI）
  - [ ] 3.2 迁移 Infrastructure 层：AudioCacheService、AudioConverterService、AudioUploadService、AudioPlayerService、AudioRecorderService、AudioDecryptService、DefaultAudioService → `Features/Audio/Infrastructure/`
  - [ ] 3.3 迁移 Application 层：AudioPanelStateManager → `Features/Audio/Application/`
  - [ ] 3.4 迁移 Application 层：AudioPanelViewModel → `Features/Audio/Application/`
  - [ ] 3.5 执行 `xcodegen generate` + 编译验证
  - [ ] 3.6 提交：`refactor(audio): 迁移音频域代码到 Features/Audio`

## 任务 4：清理与文档更新

- [ ] 4. 迁移后清理
  - [ ] 4.1 删除迁空的目录（`Service/Audio/Implementation/`、`Presentation/ViewModels/AudioPanel/`）
  - [ ] 4.2 更新 AGENTS.md 中的项目结构描述，反映 7 个域的 Features 布局
  - [ ] 4.3 执行 `xcodegen generate` + 编译验证
  - [ ] 4.4 提交：`docs: 更新项目结构文档，反映 Editor/Search/Audio 切片`
