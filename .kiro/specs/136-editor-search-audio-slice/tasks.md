# spec-136：目录结构全面对齐 — 任务清单

参考文档：
- 需求：`.kiro/specs/136-editor-search-audio-slice/requirements.md`
- 设计：`.kiro/specs/136-editor-search-audio-slice/design.md`

---

## 任务 1：Search 域迁移（REQ-1）

- [x] 1. 迁移 Search 域
  - [x] 1.1 创建 `Features/Search/` 四层目录结构（Domain/Infrastructure/Application/UI）
  - [x] 1.2 `git mv Sources/State/SearchState.swift Sources/Features/Search/Application/`
  - [x] 1.3 `git mv Sources/View/SwiftUIViews/Search/SearchFilterMenuContent.swift Sources/Features/Search/UI/`
  - [x] 1.4 执行 `xcodegen generate` + 编译验证
  - [x] 1.5 提交：`refactor(search): 迁移 Search 域到 Features/Search`

## 任务 2：Auth 域 UI 补全（REQ-4）

- [x] 2. 补全 Auth 域 UI 层
  - [x] 2.1 `git mv Sources/View/SwiftUIViews/Auth/*.swift Sources/Features/Auth/UI/`
  - [x] 2.2 `git mv Sources/Window/Controllers/LoginWindowController.swift Sources/Features/Auth/UI/`
  - [x] 2.3 执行 `xcodegen generate` + 编译验证
  - [x] 2.4 提交：`refactor(auth): 迁移认证域 UI 到 Features/Auth/UI`

## 任务 3：Shared/Contracts 迁入（REQ-7）

- [ ] 3. 迁移服务协议到 Shared/Contracts
  - [ ] 3.1 `git mv Sources/Service/Protocols/*.swift Sources/Shared/Contracts/`
  - [ ] 3.2 删除 `Sources/Shared/Contracts/.gitkeep`
  - [ ] 3.3 执行 `xcodegen generate` + 编译验证
  - [ ] 3.4 提交：`refactor: 迁移服务协议到 Shared/Contracts`

## 任务 4：Shared/Kernel — 核心基础设施（REQ-5 部分）

- [ ] 4. 迁移核心基础设施到 Shared/Kernel
  - [ ] 4.1 `git mv Sources/Core/EventBus Sources/Shared/Kernel/EventBus`
  - [ ] 4.2 `git mv Sources/Service/Core/LogService.swift Sources/Shared/Kernel/`
  - [ ] 4.3 `git mv Sources/Service/Core/PerformanceService.swift Sources/Shared/Kernel/`
  - [ ] 4.4 `git mv Sources/Core/Pagination/Pageable.swift Sources/Shared/Kernel/`
  - [ ] 4.5 创建 `Sources/Shared/Kernel/Extensions/` 目录，迁移 `Sources/Extensions/*.swift`
  - [ ] 4.6 `git mv Sources/View/SwiftUIViews/Common/PreviewHelper.swift Sources/Shared/Kernel/`
  - [ ] 4.7 删除 `Sources/Shared/Kernel/README.md`
  - [ ] 4.8 执行 `xcodegen generate` + 编译验证
  - [ ] 4.9 提交：`refactor(core): 迁移 EventBus/LogService/Extensions 到 Shared/Kernel`

## 任务 5：Shared/Kernel — 数据存储层（REQ-10）

- [ ] 5. 迁移数据存储层到 Shared/Kernel/Store
  - [ ] 5.1 创建 `Sources/Shared/Kernel/Store/Implementation/` 目录
  - [ ] 5.2 `git mv Sources/Store/DatabaseService.swift Sources/Shared/Kernel/Store/`
  - [ ] 5.3 `git mv Sources/Store/DatabaseService+*.swift Sources/Shared/Kernel/Store/`
  - [ ] 5.4 `git mv Sources/Store/DatabaseMigrationManager.swift Sources/Shared/Kernel/Store/`
  - [ ] 5.5 `git mv Sources/Store/LocalStorageService.swift Sources/Shared/Kernel/Store/`
  - [ ] 5.6 `git mv Sources/Store/MemoryCacheManager.swift Sources/Shared/Kernel/Store/`
  - [ ] 5.7 `git mv Sources/Store/Implementation/DefaultNoteStorage.swift Sources/Shared/Kernel/Store/Implementation/`
  - [ ] 5.8 创建 `Sources/Shared/Kernel/Cache/` 目录
  - [ ] 5.9 `git mv Sources/Service/Cache/Implementation/DefaultCacheService.swift Sources/Shared/Kernel/Cache/`
  - [ ] 5.10 执行 `xcodegen generate` + 编译验证
  - [ ] 5.11 提交：`refactor(storage): 迁移 DatabaseService/Store 到 Shared/Kernel/Store`

## 任务 6：Shared/Kernel — State 文件归位（REQ-8）

- [ ] 6. 迁移散落 State 文件到 Shared/Kernel
  - [ ] 6.1 `git mv Sources/State/ViewOptionsManager.swift Sources/Shared/Kernel/`
  - [ ] 6.2 `git mv Sources/State/ViewOptionsState.swift Sources/Shared/Kernel/`
  - [ ] 6.3 `git mv Sources/State/ViewState.swift Sources/Shared/Kernel/`
  - [ ] 6.4 执行 `xcodegen generate` + 编译验证
  - [ ] 6.5 提交：`refactor: 迁移视图状态文件到 Shared/Kernel`

## 任务 7：Shared/UICommons — 共享 UI 组件（REQ-6、REQ-9 部分）

- [ ] 7. 迁移共享 UI 组件到 Shared/UICommons
  - [ ] 7.1 `git mv Sources/View/Shared/OnlineStatusIndicator.swift Sources/Shared/UICommons/`
  - [ ] 7.2 `git mv Sources/View/AppKitComponents/SidebarViewController.swift Sources/Shared/UICommons/`
  - [ ] 7.3 `git mv Sources/View/SwiftUIViews/Common/NetworkLogView.swift Sources/Shared/UICommons/`
  - [ ] 7.4 创建 `Sources/Shared/UICommons/Toolbar/` 目录，迁移 `Sources/ToolbarItem/*.swift`
  - [ ] 7.5 创建 `Sources/Shared/UICommons/Settings/` 目录，迁移 `Sources/View/SwiftUIViews/Settings/*.swift`
  - [ ] 7.6 删除 `Sources/Shared/UICommons/README.md`
  - [ ] 7.7 执行 `xcodegen generate` + 编译验证
  - [ ] 7.8 提交：`refactor(ui): 迁移共享 UI 组件到 Shared/UICommons`

## 任务 8：Editor 域迁移 — 服务层（REQ-2 部分）

- [ ] 8. 迁移 Editor 域服务层
  - [ ] 8.1 创建 `Features/Editor/` 四层目录结构（Domain/Infrastructure/Application/UI）
  - [ ] 8.2 `git mv Sources/Service/Editor/EditorConfiguration.swift Sources/Features/Editor/Domain/`
  - [ ] 8.3 `git mv Sources/Service/Editor/TitleIntegrationError.swift Sources/Features/Editor/Domain/`
  - [ ] 8.4 `git mv Sources/Service/Editor/FormatConverter Sources/Features/Editor/Infrastructure/FormatConverter`
  - [ ] 8.5 `git mv Sources/Service/Editor/NoteEditingCoordinator.swift Sources/Features/Editor/Application/`
  - [ ] 8.6 执行 `xcodegen generate` + 编译验证
  - [ ] 8.7 提交：`refactor(editor): 迁移编辑器服务层到 Features/Editor`

## 任务 9：Editor 域迁移 — UI 层（REQ-2 部分）

- [ ] 9. 迁移 Editor 域 UI 层
  - [ ] 9.1 创建 `Sources/Features/Editor/UI/Bridge/` 目录
  - [ ] 9.2 `git mv Sources/View/Bridge/*.swift Sources/Features/Editor/UI/Bridge/`
  - [ ] 9.3 `git mv Sources/View/NativeEditor Sources/Features/Editor/UI/NativeEditor`
  - [ ] 9.4 `git mv Sources/View/SwiftUIViews/Common/NativeFormatMenuView.swift Sources/Features/Editor/UI/`
  - [ ] 9.5 `git mv Sources/View/SwiftUIViews/Common/XMLDebugEditorView.swift Sources/Features/Editor/UI/`
  - [ ] 9.6 执行 `xcodegen generate` + 编译验证
  - [ ] 9.7 提交：`refactor(editor): 迁移编辑器 UI 层到 Features/Editor/UI`

## 任务 10：Audio 域迁移（REQ-3）

- [ ] 10. 迁移 Audio 域
  - [ ] 10.1 创建 `Features/Audio/` 四层目录结构（Domain/Infrastructure/Application/UI）
  - [ ] 10.2 迁移 Infrastructure 层：AudioCacheService、AudioConverterService、AudioUploadService、AudioPlayerService、AudioRecorderService、AudioDecryptService → `Features/Audio/Infrastructure/`
  - [ ] 10.3 `git mv Sources/Service/Audio/Implementation/DefaultAudioService.swift Sources/Features/Audio/Infrastructure/`
  - [ ] 10.4 `git mv Sources/Service/Audio/AudioPanelStateManager.swift Sources/Features/Audio/Application/`
  - [ ] 10.5 `git mv Sources/Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift Sources/Features/Audio/Application/`
  - [ ] 10.6 `git mv Sources/View/SwiftUIViews/Audio/*.swift Sources/Features/Audio/UI/`
  - [ ] 10.7 执行 `xcodegen generate` + 编译验证
  - [ ] 10.8 提交：`refactor(audio): 迁移音频域到 Features/Audio`

## 任务 11：Common 视图分流（REQ-9 部分）

- [ ] 11. 分流 Common 目录剩余视图到对应域
  - [ ] 11.1 迁移到 Notes 域 UI：ContentAreaView、SidebarView、GalleryView、FloatingInfoBar、TrashView
  - [ ] 11.2 迁移到 Sync 域 UI：OperationProcessorProgressView、OfflineOperationsProgressView
  - [ ] 11.3 执行 `xcodegen generate` + 编译验证
  - [ ] 11.4 提交：`refactor(ui): 分流 Common 视图到对应域`

## 任务 12：模块工厂迁移 + 启动链迁移（REQ-13、REQ-12 部分）

- [ ] 12. 迁移模块工厂和启动链文件
  - [ ] 12.1 `git mv Sources/Service/Editor/EditorModule.swift Sources/App/Composition/`
  - [ ] 12.2 `git mv Sources/Service/Audio/AudioModule.swift Sources/App/Composition/`
  - [ ] 12.3 `git mv Sources/Service/Core/StartupSequenceManager.swift Sources/App/Runtime/`
  - [ ] 12.4 `git mv Sources/Service/Core/ErrorRecoveryService.swift Sources/App/Runtime/`
  - [ ] 12.5 执行 `xcodegen generate` + 编译验证
  - [ ] 12.6 提交：`refactor: 迁移模块工厂到 App/Composition，启动链到 App/Runtime`

## 任务 13：遗留代码归档 + 旧目录清理（REQ-11、REQ-12）

- [ ] 13. 归档遗留代码并清理旧目录
  - [ ] 13.1 `git mv Sources/Network/Implementation/DefaultNetworkMonitor.swift Sources/Legacy/`
  - [ ] 13.2 删除已清空的旧目录（State、Presentation、Service、View、Core/EventBus、Core/Pagination、Extensions、ToolbarItem、Store、Network/Implementation）
  - [ ] 13.3 删除 Legacy/README.md（已有实际文件）
  - [ ] 13.4 执行 `xcodegen generate` + 编译验证
  - [ ] 13.5 提交：`refactor: 归档遗留代码，清理旧目录结构`

## 任务 14：文档更新（REQ-14）

- [ ] 14. 更新项目文档
  - [ ] 14.1 更新 `AGENTS.md` 中的项目结构描述，反映最终 7 域 Features 布局和 Shared 三层结构
  - [ ] 14.2 更新 `architecture-next.md` 第 5 节，标记目录重组方案已完成
  - [ ] 14.3 更新 `docs/plans/TODO`，标记 spec-136 完成
  - [ ] 14.4 更新架构检查脚本 `scripts/check-architecture.sh` 中的路径规则（如有需要）
  - [ ] 14.5 执行 `xcodegen generate` + 编译验证
  - [ ] 14.6 提交：`docs: 更新项目结构文档，反映目录全面对齐`
