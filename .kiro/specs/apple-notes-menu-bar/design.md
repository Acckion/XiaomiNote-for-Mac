# 设计文档

## 概述

本设计文档描述小米笔记菜单栏系统的重构方案，按照 Apple Notes 的标准实现完整的 macOS 原生菜单体验。设计遵循"优先使用 macOS 标准实现"的原则，充分利用 AppKit 提供的标准选择器、响应链机制和系统菜单管理功能。

## 架构

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      NSApplication                           │
│                         mainMenu                             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐│
│  │应用程序 │ │  文件   │ │  编辑   │ │  格式   │ │ 显示   ││
│  │  菜单   │ │  菜单   │ │  菜单   │ │  菜单   │ │  菜单  ││
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └───┬────┘│
│       │           │           │           │          │      │
│  ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌───┴────┐│
│  │ 窗口    │ │         │ │         │ │         │ │        ││
│  │  菜单   │ │         │ │         │ │         │ │        ││
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     MenuManager                              │
│  - setupApplicationMenu()                                    │
│  - 管理菜单创建和配置                                         │
│  - 注册系统菜单（windowsMenu, servicesMenu）                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   响应链 (Responder Chain)                   │
│  NSApplication → NSWindow → NSWindowController →            │
│  NSView → NSTextView/NativeEditorView                       │
└─────────────────────────────────────────────────────────────┘
```

### 菜单动作路由策略

| 菜单类型 | 路由策略 | 实现方式 |
|---------|---------|---------|
| 标准编辑操作 | 响应链自动路由 | `#selector(NSText.cut(_:))` 等 |
| 查找操作 | NSTextFinder | `performFindPanelAction:` |
| 窗口操作 | NSWindow 标准方法 | `#selector(NSWindow.performMiniaturize(_:))` |
| 应用程序操作 | NSApplication | `#selector(NSApplication.terminate(_:))` |
| 自定义笔记操作 | MenuActionHandler | 自定义选择器 |
| 格式操作 | 编辑器响应链 | 转发到当前编辑器 |

### 菜单项图标规范

所有菜单项都应设置 SF Symbols 图标，使用以下辅助方法：

```swift
/// 为菜单项设置图标
/// - Parameters:
///   - menuItem: 菜单项
///   - symbolName: SF Symbols 图标名称
private func setMenuItemIcon(_ menuItem: NSMenuItem, symbolName: String) {
    if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        image.size = NSSize(width: 16, height: 16)
        menuItem.image = image
    }
}
```

#### 图标映射表

| 菜单项 | SF Symbol |
|-------|-----------|
| 关于 | info.circle |
| 设置 | gearshape |
| 隐藏 | eye.slash |
| 退出 | power |
| 新建笔记 | square.and.pencil |
| 新建文件夹 | folder.badge.plus |
| 共享 | square.and.arrow.up |
| 关闭 | xmark |
| 导入 | square.and.arrow.down |
| 导出 | square.and.arrow.up.on.square |
| 置顶 | pin |
| 复制 | doc.on.doc |
| 打印 | printer |
| 撤销 | arrow.uturn.backward |
| 重做 | arrow.uturn.forward |
| 剪切 | scissors |
| 拷贝 | doc.on.doc |
| 粘贴 | doc.on.clipboard |
| 删除 | trash |
| 全选 | selection.pin.in.out |
| 查找 | magnifyingglass |
| 附加文件 | paperclip |
| 添加链接 | link |
| 表情与符号 | face.smiling |

## 组件和接口

### 1. MenuManager（菜单管理器）

负责创建和配置所有菜单，是菜单系统的核心组件。

```swift
@MainActor
class MenuManager {
    // MARK: - 属性
    weak var appDelegate: AppDelegate?
    weak var mainWindowController: MainWindowController?
    
    // MARK: - 公共方法
    func setupApplicationMenu()
    func updateReferences(appDelegate: AppDelegate?, mainWindowController: MainWindowController?)
    
    // MARK: - 私有方法 - 菜单创建
    private func setupAppMenu(in mainMenu: NSMenu)
    private func setupFileMenu(in mainMenu: NSMenu)
    private func setupEditMenu(in mainMenu: NSMenu)
    private func setupFormatMenu(in mainMenu: NSMenu)
    private func setupViewMenu(in mainMenu: NSMenu)
    private func setupWindowMenu(in mainMenu: NSMenu)
    private func setupHelpMenu(in mainMenu: NSMenu)
    
    // MARK: - 私有方法 - 子菜单创建
    private func createFindSubmenu() -> NSMenu
    private func createExportSubmenu() -> NSMenu
    private func createParagraphStyleSubmenu() -> NSMenu
    private func createChecklistSubmenu() -> NSMenu
    private func createFontSubmenu() -> NSMenu
    private func createTextAlignmentSubmenu() -> NSMenu
    private func createIndentSubmenu() -> NSMenu
}
```

### 2. MenuActionHandler（菜单动作处理器）

处理自定义菜单动作，不处理标准系统动作。

```swift
@MainActor
class MenuActionHandler: NSObject, NSMenuItemValidation {
    // MARK: - 属性
    weak var mainWindowController: MainWindowController?
    let windowManager: WindowManager
    
    // MARK: - 文件菜单动作
    func createNewNote(_ sender: Any?)
    func createNewFolder(_ sender: Any?)
    func createSmartFolder(_ sender: Any?)
    func importNotes(_ sender: Any?)
    func importMarkdown(_ sender: Any?)
    func exportAsPDF(_ sender: Any?)
    func exportAsMarkdown(_ sender: Any?)
    func exportAsPlainText(_ sender: Any?)
    func toggleStarNote(_ sender: Any?)
    func addToPrivateNotes(_ sender: Any?)
    func duplicateNote(_ sender: Any?)
    func printNote(_ sender: Any?)
    
    // MARK: - 格式菜单动作
    func setHeading(_ sender: Any?)
    func setSubheading(_ sender: Any?)
    func setSubtitle(_ sender: Any?)
    func setBodyText(_ sender: Any?)
    func toggleOrderedList(_ sender: Any?)
    func toggleUnorderedList(_ sender: Any?)
    func toggleBlockQuote(_ sender: Any?)
    func toggleChecklist(_ sender: Any?)
    func markAsChecked(_ sender: Any?)
    func checkAll(_ sender: Any?)
    func uncheckAll(_ sender: Any?)
    func moveCheckedToBottom(_ sender: Any?)
    func deleteCheckedItems(_ sender: Any?)
    func moveItemUp(_ sender: Any?)
    func moveItemDown(_ sender: Any?)
    func toggleLightBackground(_ sender: Any?)
    func toggleBold(_ sender: Any?)
    func toggleItalic(_ sender: Any?)
    func toggleUnderline(_ sender: Any?)
    func toggleStrikethrough(_ sender: Any?)
    func toggleHighlight(_ sender: Any?)
    func alignLeft(_ sender: Any?)
    func alignCenter(_ sender: Any?)
    func alignRight(_ sender: Any?)
    func increaseIndent(_ sender: Any?)
    func decreaseIndent(_ sender: Any?)
    
    // MARK: - 显示菜单动作
    func setListView(_ sender: Any?)
    func setGalleryView(_ sender: Any?)
    func toggleFolderVisibility(_ sender: Any?)
    func toggleNoteCount(_ sender: Any?)
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func actualSize(_ sender: Any?)
    func expandSection(_ sender: Any?)
    func expandAllSections(_ sender: Any?)
    func collapseSection(_ sender: Any?)
    func collapseAllSections(_ sender: Any?)
    
    // MARK: - 窗口菜单动作
    func openNoteInNewWindow(_ sender: Any?)
    
    // MARK: - NSMenuItemValidation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
}
```

### 3. 菜单项标签枚举

用于标识菜单项，便于状态管理和验证。

```swift
enum MenuItemTag: Int {
    // 段落样式（互斥选择）
    case heading = 1001
    case subheading = 1002
    case subtitle = 1003
    case bodyText = 1004
    case orderedList = 1005
    case unorderedList = 1006
    
    // 视图模式（互斥选择）
    case listView = 2001
    case galleryView = 2002
    
    // 切换状态
    case lightBackground = 3001
    case hideFolders = 3002
    case showNoteCount = 3003
    
    // 查找操作
    case showFindInterface = 4001
    case findNext = 4002
    case findPrevious = 4003
    case showReplaceInterface = 4004
}
```

## 数据模型

### 菜单状态模型

```swift
struct MenuState {
    // 段落样式状态
    var currentParagraphStyle: ParagraphStyle = .body
    
    // 视图模式状态
    var currentViewMode: ViewMode = .list
    
    // 切换状态
    var isLightBackgroundEnabled: Bool = false
    var isFolderHidden: Bool = false
    var isNoteCountVisible: Bool = true
    
    // 选中状态
    var hasSelectedNote: Bool = false
    var hasSelectedText: Bool = false
    var isEditorFocused: Bool = false
}

enum ParagraphStyle {
    case heading, subheading, subtitle, body, orderedList, unorderedList
}

enum ViewMode {
    case list, gallery
}
```


## 详细菜单结构

### 应用程序菜单（小米笔记）

```
小米笔记
├── 关于小米笔记                    → orderFrontStandardAboutPanel:
├── ─────────────────
├── 设置...                    ⌘,  → showSettings:
├── ─────────────────
├── 隐藏小米笔记               ⌘H  → hide:
├── 隐藏其他                  ⌥⌘H  → hideOtherApplications:
├── 全部显示                        → unhideAllApplications:
├── ─────────────────
└── 退出小米笔记               ⌘Q  → terminate:
```

### 文件菜单

```
文件
├── 新建笔记                   ⌘N  → createNewNote:
├── 新建文件夹                ⇧⌘N  → createNewFolder:
├── 新建智能文件夹                  → createSmartFolder:
├── ─────────────────
├── 共享                            → shareNote: (NSSharingServicePicker)
├── ─────────────────
├── 关闭                       ⌘W  → performClose:
├── ─────────────────
├── 导入至笔记...                   → importNotes:
├── 导入 Markdown...                → importMarkdown:
├── ─────────────────
├── 导出为                     ▶
│   ├── PDF...                      → exportAsPDF:
│   ├── Markdown...                 → exportAsMarkdown:
│   └── 纯文本...                   → exportAsPlainText:
├── ─────────────────
├── 置顶笔记                        → toggleStarNote:
├── 添加到私密笔记                  → addToPrivateNotes: (待实现)
├── 复制笔记                        → duplicateNote:
├── ─────────────────
└── 打印...                    ⌘P  → print:
```

### 编辑菜单（使用标准选择器）

```
编辑
├── 撤销                       ⌘Z  → undo: (NSResponder)
├── 重做                      ⇧⌘Z  → redo: (NSResponder)
├── ─────────────────
├── 剪切                       ⌘X  → cut: (NSText)
├── 拷贝                       ⌘C  → copy: (NSText)
├── 粘贴                       ⌘V  → paste: (NSText)
├── 粘贴并匹配样式            ⌥⇧⌘V → pasteAsPlainText: (待实现)
├── 删除                            → delete: (NSText)
├── 全选                       ⌘A  → selectAll: (NSText)
├── ─────────────────
├── 附加文件...                     → attachFile:
├── 添加链接...                ⌘K  → addLink:
├── ─────────────────
├── 查找                       ▶
│   ├── 查找...                ⌘F  → performFindPanelAction: (tag: showFindInterface)
│   ├── 查找下一个             ⌘G  → performFindPanelAction: (tag: nextMatch)
│   ├── 查找上一个            ⇧⌘G  → performFindPanelAction: (tag: previousMatch)
│   ├── 使用所选内容查找       ⌘E  → performFindPanelAction: (tag: setSearchString)
│   └── 查找并替换...         ⌥⌘F  → performFindPanelAction: (tag: showReplaceInterface)
├── 拼写和语法                 ▶   → (系统标准子菜单)
├── 替换                       ▶   → (系统标准子菜单)
├── 转换                       ▶   → (系统标准子菜单)
├── 语音                       ▶   → (系统标准子菜单)
├── ─────────────────
├── 开始听写                   fn fn → startDictation:
└── 表情与符号               ⌃⌘空格 → orderFrontCharacterPalette:
```

### 格式菜单

```
格式
├── 标题                            → setHeading: (tag: 1001, 单选)
├── 小标题                          → setSubheading: (tag: 1002, 单选)
├── 副标题                          → setSubtitle: (tag: 1003, 单选)
├── 正文                            → setBodyText: (tag: 1004, 单选)
├── 有序列表                        → toggleOrderedList: (tag: 1005, 单选)
├── 无序列表                        → toggleUnorderedList: (tag: 1006, 单选)
├── ─────────────────
├── 块引用                          → toggleBlockQuote:
├── ─────────────────
├── 核对清单                        → toggleChecklist:
├── 标记为已勾选                    → markAsChecked:
├── 更多                       ▶
│   ├── 全部勾选                    → checkAll:
│   ├── 全部取消勾选                → uncheckAll:
│   ├── 将勾选的项目移到底部        → moveCheckedToBottom:
│   └── 删除已勾选项目              → deleteCheckedItems:
├── ─────────────────
├── 移动项目                   ▶
│   ├── 向上                   ⌃⌘↑ → moveItemUp:
│   └── 向下                   ⌃⌘↓ → moveItemDown:
├── ─────────────────
├── 使用浅色背景显示笔记            → toggleLightBackground: (tag: 3001, 勾选)
├── ─────────────────
├── 字体                       ▶
│   ├── 粗体                   ⌘B  → toggleBold:
│   ├── 斜体                   ⌘I  → toggleItalic:
│   ├── 下划线                 ⌘U  → toggleUnderline:
│   ├── 删除线                      → toggleStrikethrough:
│   └── 高亮                        → toggleHighlight:
├── 文本                       ▶
│   ├── 左对齐                      → alignLeft:
│   ├── 居中                        → alignCenter:
│   └── 右对齐                      → alignRight:
└── 缩进                       ▶
    ├── 增大                   ⌘]  → increaseIndent:
    └── 减小                   ⌘[  → decreaseIndent:
```

### 显示菜单

```
显示
├── 列表视图                        → setListView: (tag: 2001, 单选)
├── 画廊视图                        → setGalleryView: (tag: 2002, 单选)
├── ─────────────────
├── 隐藏文件夹                      → toggleFolderVisibility: (tag: 3002, 勾选)
├── 显示笔记数量                    → toggleNoteCount: (tag: 3003, 勾选)
├── ─────────────────
├── 放大                       ⌘+  → zoomIn:
├── 缩小                       ⌘-  → zoomOut:
├── 实际大小                   ⌘0  → actualSize:
├── ─────────────────
├── 展开区域                        → expandSection:
├── 展开所有区域                    → expandAllSections:
├── 折叠区域                        → collapseSection:
├── 折叠所有区域                    → collapseAllSections:
├── ─────────────────
├── 隐藏工具栏                      → toggleToolbarShown: (NSWindow)
├── 自定义工具栏...                 → runToolbarCustomizationPalette: (NSWindow)
└── 进入全屏幕                ⌃⌘F  → toggleFullScreen: (NSWindow)
```

### 窗口菜单（系统管理）

```
窗口
├── 最小化                     ⌘M  → performMiniaturize: (NSWindow)
├── 缩放                            → performZoom: (NSWindow)
├── 填充                            → (系统标准)
├── 居中                            → center (NSWindow)
├── ─────────────────
├── 移动与调整大小             ▶   → (系统标准子菜单)
├── 全屏幕平铺                 ▶   → (系统标准子菜单)
├── ─────────────────
├── 在新窗口中打开笔记              → openNoteInNewWindow:
├── ─────────────────
├── [窗口列表 - 系统自动管理]
├── ─────────────────
└── 前置全部窗口                    → arrangeInFront: (NSApplication)
```


## 正确性属性

*正确性属性是系统在所有有效执行中应该保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 笔记选中状态与菜单启用状态同步

*对于任意* 菜单状态和笔记选中状态，当没有选中笔记时，所有笔记相关操作菜单项（导出为、置顶笔记、复制笔记、打印等）应该被禁用；当有选中笔记时，这些菜单项应该被启用。

**Validates: Requirements 2.20, 14.4**

### Property 2: 段落样式互斥选择

*对于任意* 段落样式菜单项集合和当前段落样式状态，有且仅有一个段落样式菜单项处于勾选状态，且该菜单项对应当前的段落样式。

**Validates: Requirements 4.7, 14.6**

### Property 3: 视图模式互斥选择

*对于任意* 视图模式菜单项集合和当前视图模式状态，有且仅有一个视图模式菜单项处于勾选状态，且该菜单项对应当前的视图模式。

**Validates: Requirements 8.3, 14.7**

### Property 4: 编辑器焦点与格式菜单启用状态同步

*对于任意* 编辑器焦点状态和格式菜单项集合，当编辑器没有焦点时，所有格式相关菜单项应该被禁用；当编辑器有焦点时，格式菜单项应该根据当前选中内容的状态启用。

**Validates: Requirements 14.5**

### Property 5: 快捷键唯一性

*对于任意* 菜单项集合中的所有菜单项，不存在两个不同的菜单项使用相同的快捷键组合（keyEquivalent + keyEquivalentModifierMask）。

**Validates: Requirements 15.4**

## 错误处理

### 菜单动作错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 笔记操作时无选中笔记 | 菜单项应已禁用，若仍触发则静默忽略 |
| 导出失败 | 显示错误对话框，说明失败原因 |
| 导入文件格式不支持 | 显示错误对话框，列出支持的格式 |
| 打印失败 | 显示系统打印错误对话框 |
| 格式操作时编辑器无焦点 | 菜单项应已禁用，若仍触发则静默忽略 |

### 菜单状态同步错误处理

```swift
// 菜单项验证失败时的安全处理
func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    // 使用 guard 确保必要条件
    guard let tag = MenuItemTag(rawValue: menuItem.tag) else {
        // 未知标签的菜单项默认启用
        return true
    }
    
    // 根据标签类型进行验证
    switch tag {
    case .heading, .subheading, .subtitle, .bodyText, .orderedList, .unorderedList:
        // 段落样式需要编辑器焦点
        return isEditorFocused
    case .listView, .galleryView:
        // 视图模式始终可用
        return true
    default:
        return true
    }
}
```

## 测试策略

### 单元测试

1. **菜单结构测试**
   - 验证所有菜单项存在
   - 验证菜单项顺序正确
   - 验证分隔线位置正确
   - 验证快捷键配置正确

2. **菜单动作测试**
   - 验证标准选择器正确绑定
   - 验证自定义动作正确路由
   - 验证动作执行结果正确

3. **菜单状态测试**
   - 验证 validateMenuItem 返回正确值
   - 验证勾选状态正确更新

### 属性测试

1. **Property 1 测试**: 生成随机笔记选中状态，验证菜单启用状态一致性
2. **Property 2 测试**: 生成随机段落样式，验证勾选状态互斥性
3. **Property 3 测试**: 生成随机视图模式，验证勾选状态互斥性
4. **Property 4 测试**: 生成随机编辑器焦点状态，验证格式菜单启用状态
5. **Property 5 测试**: 遍历所有菜单项，验证快捷键唯一性

### 测试框架

- 使用 XCTest 进行单元测试
- 使用 SwiftCheck 或自定义属性测试框架进行属性测试
- 每个属性测试至少运行 100 次迭代
