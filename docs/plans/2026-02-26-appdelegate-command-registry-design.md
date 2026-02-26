# AppDelegate 命令注册表设计

## 背景

AppDelegate 当前有 84 个 `@objc func` 方法，全部是一行转发：构造 Command 并调用 `commandDispatcher?.dispatch()`。其中 6 个是别名方法（重复映射到同一 Command）。MenuManager 三个文件约 1900 行，手动逐个创建 NSMenuItem。

新增一个菜单项需要修改 3 个文件（AppDelegate + MenuManager + MenuItemTag），维护成本高。

## 目标

- AppDelegate 的 84 个 @objc 方法收敛为 1 个统一 `performCommand(_:)` 方法
- MenuManager 从手写 NSMenuItem 改为注册表驱动构建
- 新增菜单项只需在 CommandRegistry 添加 1 条记录
- 删除 6 个别名方法（setHeading1/2/3、toggleBulletList、toggleNumberedList、toggleChecklist）

## 设计

### 1. CommandRegistry 数据结构

新增 `CommandRegistry` 类，持有所有菜单命令的映射关系：

```swift
struct MenuCommandEntry {
    let tag: MenuItemTag
    let title: String
    let commandType: AppCommand.Type
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
    let symbolName: String?
    let group: MenuGroup
}

@MainActor
final class CommandRegistry {
    static let shared = CommandRegistry()
    private var entries: [MenuItemTag: MenuCommandEntry] = [:]

    func entry(for tag: MenuItemTag) -> MenuCommandEntry? { entries[tag] }
    func entries(for group: MenuGroup) -> [MenuCommandEntry] { ... }
}
```

文件位置：`Sources/Shared/Kernel/Command/CommandRegistry.swift`

### 2. MenuGroup 分组枚举

```swift
enum MenuGroup: String {
    // 文件菜单
    case fileNew, fileShare, fileImport, fileExport, fileNoteActions
    // 格式菜单
    case formatParagraph, formatChecklist, formatChecklistMore
    case formatMoveItem, formatAppearance
    case formatFont, formatAlignment, formatIndent
    // 编辑菜单
    case editAttachment
    // 显示菜单
    case viewMode, viewFolderOptions, viewZoom, viewSections
    // 窗口菜单
    case windowLayout, windowTile, windowNote
}
```

### 3. AppDelegate 统一 action 方法

改造后 AppDelegate 只保留 1 个 @objc 方法：

```swift
@objc func performCommand(_ sender: Any?) {
    guard let menuItem = sender as? NSMenuItem,
          let tag = MenuItemTag(rawValue: menuItem.tag),
          let entry = CommandRegistry.shared.entry(for: tag)
    else {
        LogService.shared.warning(.app, "未找到菜单命令映射")
        return
    }
    let command = entry.commandType.init()
    commandDispatcher?.dispatch(command)
}
```

### 4. AppCommand 协议变更

新增 `init()` 要求，使所有 Command 可通过注册表零参数构造：

```swift
@MainActor
public protocol AppCommand {
    init()
    func execute(with context: CommandContext)
}
```

### 5. 带参数 Command 改造

约 8 个 Command 当前在构造时接收参数（如 `CreateNoteCommand(folderId:)`、`ShareNoteCommand(window:)`）。改造为在 `execute()` 中从 `context.coordinator` 获取参数：

```swift
// 改造后
public struct CreateNoteCommand: AppCommand {
    public init() {}
    public func execute(with context: CommandContext) {
        let targetFolderId = context.coordinator.folderState.selectedFolderId ?? "0"
        Task {
            await context.coordinator.noteListState.createNewNote(inFolder: targetFolderId)
        }
    }
}
```

### 6. MenuManager 注册表驱动构建

新增通用方法，从 registry 生成 NSMenuItem：

```swift
private func buildMenuItem(for tag: MenuItemTag) -> NSMenuItem {
    guard let entry = CommandRegistry.shared.entry(for: tag) else {
        fatalError("未注册的菜单项: \(tag)")
    }
    let item = NSMenuItem(
        title: entry.title,
        action: #selector(AppDelegate.performCommand(_:)),
        keyEquivalent: entry.keyEquivalent
    )
    item.keyEquivalentModifierMask = entry.modifiers
    item.tag = tag.rawValue
    if let symbolName = entry.symbolName {
        setMenuItemIcon(item, symbolName: symbolName)
    }
    return item
}
```

菜单构建方法从手写每个 NSMenuItem（5-10 行/项）变为 `menu.addItem(buildMenuItem(for: .bold))`（1 行/项）。

分隔线、子菜单结构仍由 MenuManager 控制，registry 只负责单个菜单项属性。

### 7. 不纳入注册表的系统菜单项

约 15-20 个使用系统 selector 的菜单项保持原样：

- NSApplication: terminate, hide, unhideAll, orderFrontStandardAboutPanel, orderFrontCharacterPalette
- NSWindow: performClose, performMiniaturize, performZoom, toggleToolbarShown, runToolbarCustomizationPalette, toggleFullScreen
- NSText/NSTextView: cut, copy, paste, pasteAsPlainText, delete, selectAll, undo, redo
- NSTextView: performFindPanelAction, 拼写/替换/转换/语音相关

### 8. 验证策略

- 编译验证：每个任务完成后 xcodebuild build
- 运行时验证：手动点击菜单项确认命令正确触发
- 重点关注带参数的 8 个 Command 改造后行为一致
- validateMenuItem 机制不变，无需额外处理

## 预估代码量变化

| 组件 | 改造前 | 改造后 |
|------|--------|--------|
| AppDelegate @objc 方法 | ~250 行（84 个方法） | ~15 行（1 个方法） |
| MenuManager（3 个文件） | ~1900 行 | ~600-700 行 |
| CommandRegistry（新增） | 0 | ~200 行 |
| 净变化 | - | 减少 ~700-800 行 |
