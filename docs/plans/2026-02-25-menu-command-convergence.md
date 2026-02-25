# 菜单命令链路收敛实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将菜单、工具栏、快捷键入口统一到可替换命令调用，消除多入口分叉行为，填实所有空壳方法。

**Architecture:** 编辑操作走 NSResponder 链（删除空壳），格式操作填实调用 FormatStateManager，业务操作引入轻量 AppCommand 协议统一调度，精简 MenuActionHandler 转发层。

**Tech Stack:** Swift 6.0, AppKit, NSResponder, @MainActor

**Design Doc:** `docs/plans/2026-02-25-menu-command-convergence-design.md`

---

## Task 1: 修复编辑操作 — 删除空壳，走 NSResponder 链

**Files:**
- Modify: `Sources/Window/Controllers/MainWindowController+Actions.swift` — 删除 undo/redo/cut/copy/paste/selectAll 6 个空壳方法
- Modify: `Sources/App/MenuManager+EditMenu.swift` — undo/redo 改用标准 NSResponder 选择器
- Modify: `Sources/App/AppDelegate.swift` — 删除 undo/redo/cut/copy/paste/selectAll 6 个转发方法
- Modify: `Sources/App/MenuActionHandler.swift` — 删除 undo/redo/cut/copy/paste/selectAll 6 个转发方法

**Step 1: 修改 MenuManager+EditMenu.swift**

将 undo/redo 的 action 从 `Selector(("undo:"))` / `Selector(("redo:"))` 改为标准选择器：

```swift
// undo: 改为
let undoItem = NSMenuItem(
    title: "撤销",
    action: Selector(("undo:")),  // 保持不变，这是标准 NSResponder 选择器
    keyEquivalent: "z"
)
// 注意：undo: 和 redo: 本身就是 NSResponder 标准选择器
// 问题在于 MainWindowController 上的空壳方法拦截了响应链
// 所以只需要删除 MainWindowController 上的空壳即可
```

实际上 `undo:` 和 `redo:` 就是 NSUndoManager 的标准选择器，MenuManager+EditMenu 不需要改。问题出在 MainWindowController 的空壳方法拦截了响应链。

**Step 2: 删除 MainWindowController+Actions.swift 中的 6 个空壳方法**

删除以下方法（约第 909-937 行）：
```swift
// 删除这些空壳方法：
@objc func undo(_: Any?) { ... }
@objc func redo(_: Any?) { ... }
@objc func cut(_: Any?) { ... }
@objc func copy(_: Any?) { ... }
@objc func paste(_: Any?) { ... }
@objc override func selectAll(_: Any?) { ... }
```

**Step 3: 删除 AppDelegate.swift 中的 6 个转发方法**

删除以下方法（约第 171-194 行）：
```swift
// 删除这些转发方法：
@objc func undo(_ sender: Any?) { menuActionHandler.undo(sender) }
@objc func redo(_ sender: Any?) { menuActionHandler.redo(sender) }
@objc func cut(_ sender: Any?) { menuActionHandler.cut(sender) }
@objc func copy(_ sender: Any?) { menuActionHandler.copy(sender) }
@objc func paste(_ sender: Any?) { menuActionHandler.paste(sender) }
@objc func selectAll(_ sender: Any?) { menuActionHandler.selectAll(sender) }
```

**Step 4: 删除 MenuActionHandler.swift 中的 6 个转发方法**

删除以下方法（约第 347-380 行）：
```swift
// 删除这些转发方法：
func undo(_ sender: Any?) { mainWindowController?.undo(sender) }
func redo(_ sender: Any?) { mainWindowController?.redo(sender) }
func cut(_ sender: Any?) { mainWindowController?.cut(sender) }
func copy(_ sender: Any?) { mainWindowController?.copy(sender) }
func paste(_ sender: Any?) { mainWindowController?.paste(sender) }
func selectAll(_ sender: Any?) { mainWindowController?.selectAll(sender) }
```

**Step 5: 编译验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

如果编译失败，检查是否有其他地方引用了这些方法。

**Step 6: 提交**

```bash
git add -A
git commit -m "refactor(window): 删除编辑操作空壳方法，走 NSResponder 链"
```

---

## Task 2: 填实格式操作空壳

**Files:**
- Modify: `Sources/Window/Controllers/MainWindowController+Actions.swift` — 填实 toggleBold/toggleItalic/toggleUnderline/toggleStrikethrough/toggleCode/insertLink/increaseFontSize/decreaseFontSize

**Step 1: 填实格式切换方法**

将以下空壳方法替换为真实实现：

```swift
@objc func toggleBold(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    coordinator.editorModule.formatStateManager.toggleFormat(.bold)
}

@objc func toggleItalic(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    coordinator.editorModule.formatStateManager.toggleFormat(.italic)
}

@objc func toggleUnderline(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    coordinator.editorModule.formatStateManager.toggleFormat(.underline)
}

@objc func toggleStrikethrough(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    coordinator.editorModule.formatStateManager.toggleFormat(.strikethrough)
}

@objc internal func toggleCode(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    coordinator.editorModule.formatStateManager.toggleFormat(.code)
}

@objc internal func insertLink(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    // TODO(spec-121): 链接插入需要 NativeEditorContext 提供 insertLink API
    LogService.shared.debug(.window, "insertLink 待实现")
}
```

**Step 2: 填实字体大小方法**

```swift
@objc func increaseFontSize(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    // TODO(spec-121): FontSizeManager 暂无 increase/decrease API，需后续 spec 补充
    LogService.shared.debug(.window, "increaseFontSize 待实现")
}

@objc func decreaseFontSize(_: Any?) {
    guard coordinator.noteListState.selectedNote != nil else { return }
    // TODO(spec-121): FontSizeManager 暂无 increase/decrease API，需后续 spec 补充
    LogService.shared.debug(.window, "decreaseFontSize 待实现")
}
```

**Step 3: 编译验证**

```bash
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 4: 提交**

```bash
git add -A
git commit -m "fix(window): 填实格式操作空壳方法，统一调用 FormatStateManager"
```

---

## Task 3: 创建 AppCommand 协议和 CommandDispatcher

**Files:**
- Create: `Sources/Core/Command/AppCommand.swift`

**Step 1: 创建 AppCommand 协议、CommandContext、CommandDispatcher**

```swift
//
//  AppCommand.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 应用命令协议
    /// 菜单、工具栏、快捷键统一通过 Command 调度业务操作
    @MainActor
    protocol AppCommand: Sendable {
        func execute(with context: CommandContext)
    }

    /// 命令执行上下文
    @MainActor
    struct CommandContext: Sendable {
        let coordinator: AppCoordinator
    }

    /// 命令调度器
    @MainActor
    final class CommandDispatcher: Sendable {
        private let context: CommandContext

        init(coordinator: AppCoordinator) {
            self.context = CommandContext(coordinator: coordinator)
        }

        func dispatch(_ command: AppCommand) {
            command.execute(with: context)
        }
    }
#endif
```

**Step 2: 运行 xcodegen 并编译验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 3: 提交**

```bash
git add -A
git commit -m "feat(core): 添加 AppCommand 协议和 CommandDispatcher"
```

---

## Task 4: 创建笔记相关命令

**Files:**
- Create: `Sources/Core/Command/NoteCommands.swift`

**Step 1: 实现笔记命令**

将 MainWindowController+Actions 中的笔记业务逻辑提取为 Command：

```swift
//
//  NoteCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 新建笔记命令
    struct CreateNoteCommand: AppCommand {
        let folderId: String?

        func execute(with context: CommandContext) {
            let targetFolderId = folderId ?? context.coordinator.folderState.selectedFolderId ?? "0"
            Task {
                await context.coordinator.noteListState.createNewNote(inFolder: targetFolderId)
            }
        }
    }

    /// 删除笔记命令
    struct DeleteNoteCommand: AppCommand {
        func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }

            let alert = NSAlert()
            alert.messageText = "删除笔记"
            alert.informativeText = "确定要删除笔记 \"\(note.title)\" 吗？此操作无法撤销。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Task {
                    await context.coordinator.noteListState.deleteNote(note)
                }
            }
        }
    }

    /// 切换星标命令
    struct ToggleStarCommand: AppCommand {
        func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }
            Task {
                await context.coordinator.noteListState.toggleStar(note)
            }
        }
    }

    /// 分享笔记命令
    struct ShareNoteCommand: AppCommand {
        weak var window: NSWindow?

        func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }

            let sharingService = NSSharingServicePicker(items: [
                note.title,
                note.content,
            ])

            if let window,
               let contentView = window.contentView
            {
                sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: .minY)
            }
        }
    }

    /// 新建文件夹命令
    struct CreateFolderCommand: AppCommand {
        func execute(with context: CommandContext) {
            let alert = NSAlert()
            alert.messageText = "新建文件夹"
            alert.informativeText = "请输入文件夹名称："
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            inputField.placeholderString = "文件夹名称"
            alert.accessoryView = inputField
            alert.window.initialFirstResponder = inputField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let folderName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !folderName.isEmpty {
                    Task {
                        await context.coordinator.folderState.createFolder(name: folderName)
                    }
                }
            }
        }
    }
#endif
```

**Step 2: 运行 xcodegen 并编译验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 3: 提交**

```bash
git add -A
git commit -m "feat(core): 添加笔记和文件夹相关命令"
```

---

## Task 5: 创建同步和窗口相关命令

**Files:**
- Create: `Sources/Core/Command/SyncCommands.swift`
- Create: `Sources/Core/Command/WindowCommands.swift`

**Step 1: 实现同步命令**

```swift
//
//  SyncCommands.swift
//  MiNoteLibrary
//

#if os(macOS)

    /// 全量同步命令
    struct SyncCommand: AppCommand {
        func execute(with context: CommandContext) {
            context.coordinator.syncState.requestFullSync(mode: .normal)
        }
    }

    /// 增量同步命令
    struct IncrementalSyncCommand: AppCommand {
        func execute(with context: CommandContext) {
            context.coordinator.syncState.requestSync(mode: .incremental)
        }
    }
#endif
```

**Step 2: 实现窗口命令**

```swift
//
//  WindowCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit
    import SwiftUI

    /// 显示设置窗口命令
    struct ShowSettingsCommand: AppCommand {
        func execute(with context: CommandContext) {
            let settingsWindowController = SettingsWindowController(coordinator: context.coordinator)
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
        }
    }
#endif
```

**Step 3: 运行 xcodegen 并编译验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 4: 提交**

```bash
git add -A
git commit -m "feat(core): 添加同步和窗口相关命令"
```

---

## Task 6: 注入 CommandDispatcher 到 AppCoordinator

**Files:**
- Modify: `Sources/Coordinator/AppCoordinator.swift` — 添加 commandDispatcher 属性

**Step 1: 在 AppCoordinator 中添加 CommandDispatcher**

在 AppCoordinator 的属性声明区域添加：

```swift
/// 命令调度器
public let commandDispatcher: CommandDispatcher
```

在 init 方法中初始化：

```swift
self.commandDispatcher = CommandDispatcher(coordinator: self)
```

注意：CommandDispatcher 需要 AppCoordinator 引用，所以必须在 init 的最后阶段创建（所有其他属性初始化完成后）。如果 init 中有 `self` 使用限制，可以改为 lazy 或在 init 结束后单独赋值。

**Step 2: 编译验证**

```bash
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 3: 提交**

```bash
git add -A
git commit -m "feat(coordinator): 注入 CommandDispatcher 到 AppCoordinator"
```

---

## Task 7: 改造 MainWindowController+Actions 使用 Command

**Files:**
- Modify: `Sources/Window/Controllers/MainWindowController+Actions.swift` — 高频业务操作改用 CommandDispatcher

**Step 1: 改造业务操作方法**

将以下方法改为调用 CommandDispatcher：

```swift
@objc func createNewNote(_: Any?) {
    coordinator.commandDispatcher.dispatch(CreateNoteCommand(
        folderId: coordinator.folderState.selectedFolderId
    ))
}

@objc func createNewFolder(_: Any?) {
    coordinator.commandDispatcher.dispatch(CreateFolderCommand())
}

@objc func performSync(_: Any?) {
    coordinator.commandDispatcher.dispatch(SyncCommand())
}

@objc func shareNote(_: Any?) {
    coordinator.commandDispatcher.dispatch(ShareNoteCommand(window: window))
}

@objc internal func toggleStarNote(_: Any?) {
    coordinator.commandDispatcher.dispatch(ToggleStarCommand())
}

@objc internal func deleteNote(_: Any?) {
    coordinator.commandDispatcher.dispatch(DeleteNoteCommand())
}

@objc internal func showSettings(_: Any?) {
    coordinator.commandDispatcher.dispatch(ShowSettingsCommand())
}

@objc internal func performIncrementalSync(_: Any?) {
    coordinator.commandDispatcher.dispatch(IncrementalSyncCommand())
}
```

**Step 2: 编译验证**

```bash
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 3: 提交**

```bash
git add -A
git commit -m "refactor(window): 业务操作改用 CommandDispatcher 调度"
```

---

## Task 8: 精简 MenuActionHandler 转发层

**Files:**
- Modify: `Sources/App/MenuActionHandler.swift` — 删除已被 Command 化的业务操作转发方法，精简格式操作回退分支

**Step 1: 删除已 Command 化的业务操作转发方法**

在 MenuActionHandler 中，以下方法现在可以直接调用 CommandDispatcher 而不是转发到 MainWindowController：

对于已 Command 化的操作（createNewNote、createNewFolder、performSync、shareNote、toggleStarNote、deleteNote、showSettings、performIncrementalSync），将 MenuActionHandler 中的转发方法改为调用 commandDispatcher。

需要先给 MenuActionHandler 注入 CommandDispatcher 引用：

```swift
private var commandDispatcher: CommandDispatcher?

func setCommandDispatcher(_ dispatcher: CommandDispatcher) {
    commandDispatcher = dispatcher
}
```

然后改造转发方法：

```swift
func createNewNote(_ sender: Any?) {
    if let commandDispatcher {
        commandDispatcher.dispatch(CreateNoteCommand(
            folderId: mainWindowController?.coordinator.folderState.selectedFolderId
        ))
    } else {
        mainWindowController?.createNewNote(sender)
    }
}
```

**Step 2: 精简格式操作回退分支**

格式操作方法中的"回退到 MainWindowController"分支现在可以删除，因为 MainWindowController 的格式方法已经填实了。简化为：

```swift
func toggleBold(_ sender: Any?) {
    if formatStateManager?.hasActiveEditor ?? false {
        formatStateManager?.toggleFormat(.bold)
    } else {
        mainWindowController?.toggleBold(sender)
    }
}
// 保持不变 — 回退分支现在有真实实现了
```

实际上格式操作的双路径保留是合理的（FormatStateManager 优先，MainWindowController 回退），因为 MainWindowController 的方法现在有真实实现了。不需要删除回退分支。

**Step 3: 在 AppDelegate 中注入 CommandDispatcher**

在 AppDelegate 的启动链中，AppCoordinator 创建后注入：

```swift
menuActionHandler.setCommandDispatcher(coordinator.commandDispatcher)
```

**Step 4: 编译验证**

```bash
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 5: 提交**

```bash
git add -A
git commit -m "refactor(app): 精简 MenuActionHandler，注入 CommandDispatcher"
```

---

## Task 9: 精简 AppDelegate 转发方法

**Files:**
- Modify: `Sources/App/AppDelegate.swift` — 已 Command 化的业务操作转发方法改用 CommandDispatcher

**Step 1: 给 AppDelegate 添加 CommandDispatcher 引用**

```swift
private var commandDispatcher: CommandDispatcher?
```

在启动链中赋值：

```swift
self.commandDispatcher = coordinator.commandDispatcher
```

**Step 2: 改造已 Command 化的业务操作转发方法**

```swift
@objc func createNewNote(_ sender: Any?) {
    commandDispatcher?.dispatch(CreateNoteCommand(folderId: nil))
}

@objc func showSettings(_ sender: Any?) {
    commandDispatcher?.dispatch(ShowSettingsCommand())
}
// ... 其他已 Command 化的操作
```

**Step 3: 编译验证**

```bash
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 4: 提交**

```bash
git add -A
git commit -m "refactor(app): AppDelegate 业务操作改用 CommandDispatcher"
```

---

## Task 10: 最终验证和文档更新

**Files:**
- Modify: `AGENTS.md` — 更新项目结构，添加 Command 目录说明
- Modify: `CHANGELOG.md` — 添加变更记录
- Modify: `docs/plans/TODO` — 确认未来工作已记录

**Step 1: 更新 AGENTS.md**

在项目结构的 Core 部分添加：

```
├── Core/
│   ├── Command/            # 命令模式（AppCommand, CommandDispatcher, 业务命令）
│   ├── EventBus/           # 事件总线
│   └── Pagination/         # 分页工具
```

**Step 2: 更新 CHANGELOG.md**

添加 spec-121 的变更记录。

**Step 3: 全量编译验证**

```bash
xcodegen generate
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 4: 提交**

```bash
git add -A
git commit -m "docs: 更新 AGENTS.md 和 CHANGELOG.md"
```

---

## 验收标准

1. undo/redo/cut/copy/paste/selectAll 走 NSResponder 链，无空壳方法
2. toggleBold/toggleItalic/toggleUnderline/toggleStrikethrough/toggleCode 调用 FormatStateManager
3. increaseFontSize/decreaseFontSize/insertLink 有 TODO 标注，不再是无声空壳
4. 高频业务操作通过 CommandDispatcher 统一调度
5. MenuActionHandler 精简，无冗余纯转发方法
6. 全量编译通过
