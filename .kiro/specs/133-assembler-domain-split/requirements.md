# spec-133：组合根按域拆分

## 背景

`AppCoordinatorAssembler.buildDependencies()` 当前是单体装配方法（约 150 行），所有域的依赖构建混在一起。随着功能增长会持续膨胀，且难以定位某个域的装配逻辑。

## 需求

### REQ-1：按域拆分 Assembler

将 `AppCoordinatorAssembler` 拆分为 5 个域 Assembler：

- `NotesAssembler`：构建 NoteStore、NoteListState、NoteEditorState、NotePreviewService
- `SyncAssembler`：构建 SyncEngine、SyncState、StartupSequenceManager、ErrorRecoveryService、NetworkRecoveryHandler
- `AuthAssembler`：构建 PassTokenManager、AuthState
- `EditorAssembler`：wireEditorContext 逻辑下沉到此
- `AudioAssembler`：构建 AudioPanelViewModel

### REQ-2：主装配器仅聚合

`AppCoordinatorAssembler.buildDependencies()` 简化为：
1. 创建 4 个模块工厂（NetworkModule、SyncModule、EditorModule、AudioModule）
2. 调用各域 Assembler 获取域产出
3. 处理跨域接线（如 networkModule.setPassTokenManager）
4. 组装 Dependencies 结构体

### REQ-3：保持行为不变

拆分后应用启动行为、依赖图完全不变。所有现有测试通过。

## 验收标准

1. `AppCoordinatorAssembler.buildDependencies()` 方法体不超过 40 行
2. 5 个域 Assembler 文件存在于 `Sources/Coordinator/` 目录
3. 编译通过，应用启动正常
4. 组合根冒烟测试（spec-132）通过
