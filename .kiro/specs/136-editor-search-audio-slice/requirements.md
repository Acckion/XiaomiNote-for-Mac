# spec-136：Editor / Search / Audio 纵向切片 — 需求

## 背景

spec-126 至 spec-128 完成了 Notes、Sync、Auth、Folders 四个核心域的 Vertical Slice 迁移。剩余三个域（Search、Editor、Audio）仍散落在旧技术层目录中，需要迁入 `Features/` 结构以达成 architecture-next.md 的目标。

## 需求

### REQ-1：Search 域迁移

将搜索相关代码迁入 `Features/Search/`：

- `Sources/State/SearchState.swift` → `Features/Search/Application/SearchState.swift`
- 建立 `Features/Search/` 四层目录结构（Domain/Infrastructure/Application/UI）
- 当前 Search 域仅有 Application 层（SearchState），其余层先建壳

### REQ-2：Editor 域迁移

将编辑器相关代码迁入 `Features/Editor/`：

- `Sources/Service/Editor/NoteEditingCoordinator.swift` → `Features/Editor/Application/`
- `Sources/Service/Editor/EditorConfiguration.swift` → `Features/Editor/Domain/`
- `Sources/Service/Editor/TitleIntegrationError.swift` → `Features/Editor/Domain/`
- `Sources/Service/Editor/FormatConverter/` 整个目录 → `Features/Editor/Infrastructure/FormatConverter/`
- `Sources/Service/Editor/EditorModule.swift` 保留原位（模块工厂不属于域内部）
- 建立 `Features/Editor/` 四层目录结构

### REQ-3：Audio 域迁移

将音频相关代码迁入 `Features/Audio/`：

- `Sources/Service/Audio/AudioCacheService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Service/Audio/AudioConverterService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Service/Audio/AudioUploadService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Service/Audio/AudioPanelStateManager.swift` → `Features/Audio/Application/`
- `Sources/Service/Audio/AudioPlayerService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Service/Audio/AudioRecorderService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Service/Audio/AudioDecryptService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Service/Audio/Implementation/DefaultAudioService.swift` → `Features/Audio/Infrastructure/`
- `Sources/Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift` → `Features/Audio/Application/`
- `Sources/Service/Audio/AudioModule.swift` 保留原位（模块工厂不属于域内部）
- 建立 `Features/Audio/` 四层目录结构

### REQ-4：迁移约束

- 每个域独立迁移，一个域一个 commit
- 每次迁移后执行 `xcodegen generate` + 编译验证
- 使用 `git mv` 保留文件历史
- 更新 AGENTS.md 中的项目结构描述
- EditorModule、AudioModule 作为模块工厂保留在 `Sources/Service/` 中，不迁入 Features

## 验收标准

1. `Features/Search/`、`Features/Editor/`、`Features/Audio/` 目录存在且包含对应文件
2. 每个域具备四层目录结构（Domain/Infrastructure/Application/UI）
3. EditorModule、AudioModule 仍在 `Sources/Service/` 中
4. 编译通过
5. AGENTS.md 项目结构已更新
