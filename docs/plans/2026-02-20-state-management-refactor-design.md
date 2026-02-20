# 状态管理大规模重构设计

## 问题诊断

### 根因

`selectedNote` 存在于 5 个地方，`notes` 数组存在于 3 个地方，通过 Combine 互相同步。当 `NoteEditingCoordinator` 更新 `NotesViewModel.notes` 时，变化不会传播到 `NoteListViewModel.notes`（`WindowState` 的数据源），导致列表预览"还原"。同时多个 `onChange` 触发器互相干扰，造成编辑器内容丢失。

### 当前状态副本分布

```
selectedNote 存在于:
1. NotesViewModel.selectedNote (@Published)
2. ViewStateCoordinator.selectedNote (@Published)
3. NoteListViewModel.selectedNote (@Published)
4. NotesViewModelAdapter.selectedNote (继承自 NotesViewModel)
5. WindowState.selectedNote (@Published)

notes 数组存在于:
1. NotesViewModel.notes (@Published)
2. NoteListViewModel.notes (@Published)
3. WindowState.notes (@Published)

同步方式: Combine sink/assign，形成复杂的双向同步网络
```

### 直接导致的 Bug

1. 修改正文后切换笔记，列表预览还原（notes 数组更新未传播到 NoteListViewModel）
2. 修改标题后切换笔记，编辑器和列表都还原（handleSaveSuccess 在笔记切换后仍执行）
3. 云端不同步（scheduleCloudUpload 被取消或未触发）
4. handleNoteAppear 和 handleSelectedNoteChange 双重触发 switchToNote

## 重构目标

1. `NotesViewModel` 成为唯一数据源（Single Source of Truth）
2. 消除所有冗余状态副本和 Combine 同步链
3. 数据更新路径唯一：写入 `NotesViewModel.notes` 一次，全局可见
4. 修复所有保存/切换相关 Bug

## 架构设计

### 重构后的数据流

```
NotesViewModel（唯一数据源）
  ├── @Published notes: [Note]
  ├── @Published selectedNote: Note?
  ├── @Published selectedFolder: Folder?
  ├── @Published hasUnsavedContent: Bool
  └── saveContentCallback: (() async -> Bool)?

视图层直接读取:
  ├── NoteDetailView → viewModel.selectedNote
  ├── NotesListView → viewModel.filteredNotes
  ├── SidebarView → viewModel.selectedFolder
  └── GalleryView → viewModel.selectedNote

WindowState（仅保留窗口独立状态）:
  ├── expandedNote: Note?
  ├── scrollPosition: CGFloat
  ├── expandedFolders: Set<String>
  └── showSidebar: Bool
  （不再持有 notes、selectedNote、selectedFolder 等数据副本）

NoteEditingCoordinator（编辑器状态管理）:
  └── updateNotesArrayOnly → 直接写 viewModel.notes
      （一次写入，SwiftUI 自动刷新所有依赖视图）
```

### 被删除/简化的组件

| 组件 | 处理方式 |
|------|---------|
| ViewStateCoordinator | 删除。有用功能（状态持久化、文件夹切换前保存）合并到 NotesViewModel |
| NoteListViewModel | 保留但不再持有 notes/selectedNote 副本。降级为纯业务操作层（deleteNote、toggleStar 等） |
| NotesViewModelAdapter | 简化。去掉 Combine 同步链，直接委托到 AppCoordinator 的各个 ViewModel |
| WindowState | 简化。去掉 notes、selectedNote、selectedFolder 等数据副本，只保留窗口独立状态 |

### NoteDetailView 事件处理简化

重构前：
```
handleSelectedNoteChange (onChange of viewModel.selectedNote)
  ├── 不同笔记: saveBeforeSwitching + switchToNote
  └── 同一笔记内容变化: switchToNote（外部同步）

handleNoteAppear (onAppear)
  └── saveBeforeSwitching + switchToNote  ← 和上面重复！
```

重构后：
```
handleSelectedNoteChange (onChange of viewModel.selectedNote)
  ├── 不同笔记: saveBeforeSwitching + switchToNote
  └── 同一笔记内容变化: 忽略（编辑器自己管理内容）

handleNoteAppear: 删除
```

### NoteEditingCoordinator 保存流程简化

重构前：
```
performXMLSave → Task → NoteOperationCoordinator.saveNote → handleSaveSuccess
  handleSaveSuccess: 无取消检查，可能在笔记切换后污染新笔记状态
  updateViewModel: 更新 notes 数组 + stateCoordinator.updateNoteContent
  updateNotesArrayOnly: 只更新 notes 数组（不传播到 NoteListViewModel）
```

重构后：
```
performXMLSave → Task → NoteOperationCoordinator.saveNote → handleSaveSuccess
  handleSaveSuccess: 增加 Task.isCancelled + noteId 一致性检查
  updateViewModel: 只更新 viewModel.notes 数组（唯一数据源，自动传播）
  去掉 stateCoordinator 相关调用
```

## 影响范围

### 核心改动（6 个文件）

1. `ViewStateCoordinator.swift` — 删除
2. `WindowState.swift` — 去掉数据副本，只保留窗口独立状态
3. `NotesViewModelAdapter.swift` — 去掉 Combine 同步链
4. `NoteEditingCoordinator.swift` — 简化数据更新路径，修复 handleSaveSuccess
5. `NoteDetailView.swift` — 去掉 handleNoteAppear，简化 handleSelectedNoteChange
6. `NotesViewModel.swift` — 去掉 setupStateCoordinatorSync，吸收 ViewStateCoordinator 的有用功能

### 关联改动（6-8 个文件）

7. `AppCoordinator.swift` — 调整 noteListViewModel 使用
8. `NotesListView.swift` — 去掉 stateCoordinator.selectNote
9. `SidebarView.swift` — 去掉 stateCoordinator.selectFolder
10. `ContentAreaView.swift` — 调整 WindowState 使用
11. `GalleryView.swift` — 调整 WindowState 使用
12. `NoteDetailViewController.swift` — 调整 WindowState 参数
13. `NoteListViewModel.swift` — 去掉 notes/selectedNote 的 @Published（可选）

### 不受影响

- 编辑器核心（NativeEditorView、FormatManager 等）
- 服务层（DatabaseService、SyncService、MiNoteService）
- 模型层（Note、Folder）
- 工具栏、菜单系统

## 风险控制

1. 分阶段提交，每个阶段确保可编译
2. 先修复 handleSaveSuccess 的取消检查（最小修复，立即止血）
3. 再逐步消除冗余状态副本
4. 最后清理和验证
