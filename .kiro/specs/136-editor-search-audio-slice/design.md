# spec-136：Editor / Search / Audio 纵向切片 — 设计

## 技术方案

### 1. Search 域迁移

Search 域当前最轻量，仅有 SearchState 一个文件。

```
Features/Search/
├── Domain/             # 建壳（当前无领域模型）
├── Infrastructure/     # 建壳（当前无基础设施）
├── Application/
│   └── SearchState.swift   (从 Sources/State/ 迁入)
└── UI/                 # 建壳（搜索 UI 当前嵌入 Notes 域）
```

迁移步骤：
1. 创建 `Features/Search/` 四层目录
2. `git mv Sources/State/SearchState.swift Sources/Features/Search/Application/`
3. `xcodegen generate` + 编译验证

### 2. Editor 域迁移

Editor 域较复杂，需要区分模块工厂（保留原位）和域内代码（迁入 Features）。

```
Features/Editor/
├── Domain/
│   ├── EditorConfiguration.swift    (从 Service/Editor/ 迁入)
│   └── TitleIntegrationError.swift  (从 Service/Editor/ 迁入)
├── Infrastructure/
│   └── FormatConverter/             (从 Service/Editor/FormatConverter/ 整体迁入)
│       ├── AST/
│       ├── Converter/
│       ├── Generator/
│       ├── Parser/
│       ├── Utils/
│       ├── ConversionError.swift
│       ├── XiaoMiFormatConverter.swift
│       ├── XMLNormalizer.swift
│       └── XMLRoundtripChecker.swift
├── Application/
│   └── NoteEditingCoordinator.swift (从 Service/Editor/ 迁入)
└── UI/                              # 建壳（编辑器 UI 当前在 View/NativeEditor/）
```

保留在原位的文件：
- `Sources/Service/Editor/EditorModule.swift`：模块工厂，负责构建编辑器层依赖图

迁移步骤：
1. 创建 `Features/Editor/` 四层目录
2. `git mv Sources/Service/Editor/EditorConfiguration.swift Sources/Features/Editor/Domain/`
3. `git mv Sources/Service/Editor/TitleIntegrationError.swift Sources/Features/Editor/Domain/`
4. `git mv Sources/Service/Editor/FormatConverter Sources/Features/Editor/Infrastructure/FormatConverter`
5. `git mv Sources/Service/Editor/NoteEditingCoordinator.swift Sources/Features/Editor/Application/`
6. `xcodegen generate` + 编译验证

### 3. Audio 域迁移

Audio 域文件较多，按四层分类迁入。

```
Features/Audio/
├── Domain/              # 建壳（当前无独立领域模型）
├── Infrastructure/
│   ├── AudioCacheService.swift       (从 Service/Audio/ 迁入)
│   ├── AudioConverterService.swift   (从 Service/Audio/ 迁入)
│   ├── AudioUploadService.swift      (从 Service/Audio/ 迁入)
│   ├── AudioPlayerService.swift      (从 Service/Audio/ 迁入)
│   ├── AudioRecorderService.swift    (从 Service/Audio/ 迁入)
│   ├── AudioDecryptService.swift     (从 Service/Audio/ 迁入)
│   └── DefaultAudioService.swift     (从 Service/Audio/Implementation/ 迁入)
├── Application/
│   ├── AudioPanelStateManager.swift  (从 Service/Audio/ 迁入)
│   └── AudioPanelViewModel.swift     (从 Presentation/ViewModels/AudioPanel/ 迁入)
└── UI/                               # 建壳（当前无独立 UI）
```

保留在原位的文件：
- `Sources/Service/Audio/AudioModule.swift`：模块工厂，负责构建音频层依赖图

迁移步骤：
1. 创建 `Features/Audio/` 四层目录
2. 逐个 `git mv` 迁移 Infrastructure 层文件
3. `git mv Sources/Service/Audio/AudioPanelStateManager.swift Sources/Features/Audio/Application/`
4. `git mv Sources/Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift Sources/Features/Audio/Application/`
5. `xcodegen generate` + 编译验证

### 4. 迁移后清理

- `Sources/State/` 目录：SearchState 迁出后，剩余 ViewOptionsManager、ViewOptionsState、ViewState 暂留
- `Sources/Service/Editor/` 目录：仅保留 EditorModule.swift
- `Sources/Service/Audio/` 目录：仅保留 AudioModule.swift
- `Sources/Presentation/ViewModels/AudioPanel/` 目录：迁空后删除
- `Sources/Service/Audio/Implementation/` 目录：迁空后删除

## 影响范围

- 迁移：SearchState（1 个文件）
- 迁移：Editor 域（3 个文件 + FormatConverter 整个目录）
- 迁移：Audio 域（8 个文件 + 1 个 ViewModel）
- 清理：空目录删除
- 更新：AGENTS.md 项目结构描述
