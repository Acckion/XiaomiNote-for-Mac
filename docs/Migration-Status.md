# 重构迁移说明

## 当前状态

已完成以下重构阶段：

### 阶段 1-4：基础架构 ✅
- 依赖注入容器（DIContainer, ServiceLocator）
- 服务协议层（8 个协议）
- 服务实现层（9 个实现）
- ViewModel 基类（BaseViewModel, LoadableViewModel, PageableViewModel）
- 性能优化基础（BackgroundTaskManager, LRUCache, Pageable）
- 应用协调器（AppCoordinator）

### 阶段 5：代码迁移（进行中）
- ✅ ServiceLocator 配置完成
- ✅ AppCoordinator 创建完成
- ✅ AppDelegate 更新完成
- ⚠️ **需要手动操作：将新文件添加到 Xcode 项目**

## 需要手动完成的步骤

由于通过命令行无法直接修改 Xcode 项目文件，需要在 Xcode IDE 中手动完成以下操作：

### 1. 将新创建的文件添加到 MiNoteLibrary 目标

需要添加到 MiNoteLibrary 框架的文件：

**依赖注入**
- `Sources/Core/DependencyInjection/DIContainer.swift`
- `Sources/Core/DependencyInjection/ServiceLocator.swift`

**服务协议**
- `Sources/Service/Protocols/NoteServiceProtocol.swift`
- `Sources/Service/Protocols/NoteStorageProtocol.swift`
- `Sources/Service/Protocols/SyncServiceProtocol.swift`
- `Sources/Service/Protocols/AuthenticationServiceProtocol.swift`
- `Sources/Service/Protocols/NetworkMonitorProtocol.swift`
- `Sources/Service/Protocols/ImageServiceProtocol.swift`
- `Sources/Service/Protocols/AudioServiceProtocol.swift`
- `Sources/Service/Protocols/CacheServiceProtocol.swift`

**服务实现**
- `Sources/Service/Network/Core/NetworkClient.swift`
- `Sources/Service/Network/Implementation/DefaultNoteService.swift`
- `Sources/Service/Network/Implementation/DefaultNetworkMonitor.swift`
- `Sources/Service/Storage/Implementation/DefaultNoteStorage.swift`
- `Sources/Service/Sync/Implementation/DefaultSyncService.swift`
- `Sources/Service/Authentication/Implementation/DefaultAuthenticationService.swift`
- `Sources/Service/Image/Implementation/DefaultImageService.swift`
- `Sources/Service/Audio/Implementation/DefaultAudioService.swift`
- `Sources/Service/Cache/Implementation/DefaultCacheService.swift`

**ViewModel 基类**
- `Sources/Presentation/ViewModels/Base/BaseViewModel.swift`
- `Sources/Presentation/ViewModels/Base/LoadableViewModel.swift`
- `Sources/Presentation/ViewModels/Base/PageableViewModel.swift`

**ViewModel 实现**
- `Sources/Presentation/ViewModels/NoteList/NoteListViewModel.swift`
- `Sources/Presentation/ViewModels/NoteEditor/NoteEditorViewModel.swift`
- `Sources/Presentation/ViewModels/Authentication/AuthenticationViewModel.swift`
- `Sources/Presentation/ViewModels/Folder/FolderViewModel.swift`
- `Sources/Presentation/Coordinators/SyncCoordinator.swift`
- `Sources/Presentation/Coordinators/AppCoordinator.swift`

**性能优化**
- `Sources/Core/Concurrency/BackgroundTaskManager.swift`
- `Sources/Core/Pagination/Pageable.swift`
- `Sources/Core/Cache/LRUCache.swift`

**测试支持**
- `Tests/TestSupport/BaseTestCase.swift`
- `Tests/Mocks/MockNoteService.swift`
- `Tests/Mocks/MockNoteStorage.swift`
- `Tests/Mocks/MockSyncService.swift`
- `Tests/Mocks/MockAuthenticationService.swift`
- `Tests/Mocks/MockNetworkMonitor.swift`

### 2. 在 Xcode 中添加文件的步骤

1. 打开 `MiNoteMac.xcodeproj`
2. 在项目导航器中选择 MiNoteLibrary 目标
3. 右键点击相应的文件夹（如 Core, Service, Presentation 等）
4. 选择 "Add Files to MiNoteMac..."
5. 选择上述列出的文件
6. 确保在 "Add to targets" 中勾选 "MiNoteLibrary"
7. 点击 "Add"

### 3. 验证编译

添加完所有文件后，执行以下命令验证编译：

```bash
xcodebuild -scheme MiNoteMac -configuration Debug build
```

如果编译成功，说明所有文件都已正确添加到项目中。

## 下一步工作

文件添加完成并编译成功后，可以继续进行：

1. 更新现有的 View 以使用新的 ViewModel
2. 逐步移除对旧 NotesViewModel 的依赖
3. 将单例调用迁移到依赖注入
4. 添加单元测试
5. 性能测试和优化

## 技术债务

- ServiceLocator 是过渡期使用，最终应该移除，改为纯依赖注入
- 需要为所有新的 ViewModel 和 Service 添加单元测试
- 需要更新文档以反映新的架构

## 提交历史

- feat(infrastructure): 阶段 1 - 建立基础设施
- feat(viewmodel): 阶段 2 - 拆分 ViewModel
- feat(service): 阶段 3 - 服务层实现
- feat(performance): 阶段 4 - 性能优化基础
- feat(migration): 阶段 5 - 迁移配置（当前）
