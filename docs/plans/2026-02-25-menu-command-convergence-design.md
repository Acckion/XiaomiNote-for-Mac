# 菜单命令链路收敛设计

日期：2026-02-25
编号：spec-121（对应 architecture-next 建议编号）

## 1. 目标

将菜单、工具栏、快捷键入口统一到可替换命令调用，消除当前多入口分叉行为。

完成标准：
- undo/redo/cut/copy/paste/selectAll 全部具备真实行为，禁止空实现占位
- 格式操作空壳全部填实
- 引入轻量 AppCommand 协议统一业务操作入口
- 精简 MenuActionHandler 转发层

## 2. 当前问题

### 2.1 编辑操作链路断裂

MenuManager+EditMenu 中 undo/redo 使用 `Selector(("undo:"))` 和 `Selector(("redo:"))`，命中 MainWindowController 的空壳方法，导致 undo/redo 完全不工作。cut/copy/paste/selectAll 使用 `#selector(NSText.xxx)` 走 NSResponder 链能正常工作，但 MainWindowController 上的同名空壳方法可能拦截响应链。

### 2.2 格式操作双路径不一致

MenuActionHandler 中格式操作优先走 FormatStateManager，回退到 MainWindowController（空壳）。从菜单触发时 FormatStateManager 能工作；从工具栏触发时直接调用 MainWindowController 空壳方法，什么都不做。

### 2.3 业务操作三层转发

AppDelegate → MenuActionHandler → MainWindowController 三层转发，MenuActionHandler 对大部分业务操作只是简单转发，没有附加逻辑。同一个动作从菜单和工具栏走不同路径。

## 3. 设计方案

### 3.1 编辑操作：拥抱 NSResponder 链

修复方式：
1. 删除 MainWindowController+Actions 中 6 个空壳编辑方法（undo/redo/cut/copy/paste/selectAll）
2. 修改 MenuManager+EditMenu 中 undo/redo 的 action 为标准 NSResponder 选择器
3. 删除 AppDelegate 中对应的 6 个转发方法
4. 删除 MenuActionHandler 中对应的 6 个转发方法

结果：编辑操作完全走 macOS 原生 NSResponder 链，NSTextView（NativeTextView）内置了完整实现，系统响应链自动路由。

### 3.2 格式操作：填实空壳

填实 MainWindowController+Actions 中的格式空壳方法，统一调用 FormatStateManager：

```swift
@objc func toggleBold(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    coordinator.editorModule.formatStateManager.toggleFormat(.bold)
}
```

涉及方法：
- toggleBold/toggleItalic/toggleUnderline/toggleStrikethrough → `toggleFormat(.xxx)`
- toggleCode → `toggleFormat(.code)`
- insertLink → 调用 NativeEditorContext 插入链接 API
- increaseFontSize/decreaseFontSize → 调用 FontSizeManager 对应方法

### 3.3 轻量 AppCommand 协议

```swift
protocol AppCommand: Sendable {
    @MainActor func execute(with context: CommandContext)
}

@MainActor
struct CommandContext {
    let coordinator: AppCoordinator
}

@MainActor
class CommandDispatcher {
    private let context: CommandContext

    init(coordinator: AppCoordinator) {
        self.context = CommandContext(coordinator: coordinator)
    }

    func dispatch(_ command: AppCommand) {
        command.execute(with: context)
    }
}
```

本次 Command 化的业务操作（约 10-15 个高频操作）：
- 笔记：CreateNoteCommand、DeleteNoteCommand、ToggleStarCommand
- 文件夹：CreateFolderCommand
- 同步：SyncCommand、IncrementalSyncCommand
- 窗口：ShowSettingsCommand、ShowLoginCommand、ShowHistoryCommand、ShowTrashCommand
- 其他：ShareNoteCommand、ShowOfflineOperationsCommand

剩余业务操作的 Command 化留给后续 spec。

### 3.4 精简 MenuActionHandler

- 删除所有纯转发的业务操作方法（改由 CommandDispatcher 统一处理）
- 删除格式操作的"回退到 MainWindowController"分支
- 保留 validateMenuItem 和状态监听逻辑
- 预计从约 1334 行降到约 600-700 行

### 3.5 精简 AppDelegate

- 业务操作的 @objc 转发方法改为调用 CommandDispatcher
- 编辑操作的转发方法直接删除（走 NSResponder 链）

## 4. 文件变更清单

### 新增文件
- `Sources/Core/Command/AppCommand.swift` — 协议定义、CommandContext、CommandDispatcher
- `Sources/Core/Command/NoteCommands.swift` — 笔记相关命令
- `Sources/Core/Command/SyncCommands.swift` — 同步相关命令
- `Sources/Core/Command/WindowCommands.swift` — 窗口相关命令

### 修改文件
- `Sources/App/MenuManager+EditMenu.swift` — undo/redo 改用标准选择器
- `Sources/App/MenuActionHandler.swift` — 精简转发层
- `Sources/App/AppDelegate.swift` — 精简转发方法，注入 CommandDispatcher
- `Sources/Window/Controllers/MainWindowController+Actions.swift` — 删除编辑空壳，填实格式空壳
- `Sources/Coordinator/AppCoordinator.swift` — 暴露 CommandDispatcher

## 5. 不做的事

- 不改变 MenuState 和菜单验证逻辑
- 不改变工具栏构建逻辑（MainWindowToolbarDelegate）
- 不做全量 Command 化（只做高频业务操作）
- 不改变数据模型
- 不引入外部依赖

## 6. 未来工作

记录到 docs/plans/TODO：
- 剩余业务操作的 Command 化（格式菜单弹窗、视图选项、音频面板等）
- Command 日志/审计能力
- 菜单验证逻辑与 Command 的 canExecute 整合
