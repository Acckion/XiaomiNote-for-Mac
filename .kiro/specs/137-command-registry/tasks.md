# 实现任务：AppDelegate 命令注册表

## 任务列表

- [x] 1. 创建 CommandRegistry 基础设施
  - [x] 1.1 创建 `Sources/Shared/Kernel/Command/CommandRegistry.swift`，定义 MenuGroup 枚举、MenuCommandEntry 结构体、CommandRegistry 类（含 entry(for:) 和 entries(for:) 方法）
  - [x] 1.2 修改 AppCommand 协议，新增 `init()` 要求
  - [x] 1.3 编译验证

- [x] 2. 改造带参数的 Command
  - [x] 2.1 改造 CreateNoteCommand：移除 folderId 参数，在 execute() 中从 context.coordinator.folderState.selectedFolderId 获取
  - [x] 2.2 改造 ShareNoteCommand：移除 window 参数，在 execute() 中从 context.coordinator 获取窗口引用
  - [x] 2.3 为所有缺少 `public init()` 的 Command 添加零参数构造器
  - [x] 2.4 编译验证

- [x] 3. 注册所有命令条目
  - [x] 3.1 在 CommandRegistry.registerAll() 中注册文件菜单命令（fileNew、fileShare、fileImport、fileExport、fileNoteActions 分组）
  - [x] 3.2 注册格式菜单命令（formatParagraph、formatChecklist、formatChecklistMore、formatMoveItem、formatAppearance、formatFont、formatAlignment、formatIndent 分组）
  - [x] 3.3 注册编辑菜单命令（editAttachment 分组）
  - [x] 3.4 注册显示菜单命令（viewMode、viewFolderOptions、viewZoom、viewSections 分组）
  - [x] 3.5 注册窗口菜单命令（windowLayout、windowTile、windowNote 分组）
  - [x] 3.6 注册杂项命令（应用菜单中的设置、帮助、调试等）
  - [x] 3.7 编译验证

- [x] 4. 实现 AppDelegate 统一 performCommand 方法
  - [x] 4.1 在 AppDelegate 中添加 `@objc func performCommand(_ sender: Any?)` 方法
  - [x] 4.2 删除 AppDelegate 中 84 个旧的 @objc 转发方法（含 6 个别名方法）
  - [x] 4.3 编译验证

- [x] 5. 改造 MenuManager 使用注册表驱动构建
  - [x] 5.1 在 MenuManager 中添加 `buildMenuItem(for: MenuItemTag)` 方法
  - [x] 5.2 改造 MenuManager.swift 中的 setupFileMenu、setupViewMenu、setupWindowMenu，将手写 NSMenuItem 替换为 buildMenuItem(for:) 调用（系统 selector 菜单项保持不变）
  - [x] 5.3 改造 MenuManager+FormatMenu.swift，将手写 NSMenuItem 替换为 buildMenuItem(for:) 调用
  - [x] 5.4 改造 MenuManager+EditMenu.swift 中的 setupAttachmentItems，将手写 NSMenuItem 替换为 buildMenuItem(for:) 调用（系统 selector 菜单项保持不变）
  - [x] 5.5 改造 MenuManager.swift 中的 setupAppMenu，将设置等自定义命令菜单项替换为 buildMenuItem(for:) 调用
  - [x] 5.6 编译验证

- [x] 6. 补充 MenuItemTag 缺失的 case
  - [x] 6.1 检查 AppDelegate 中所有通过 CommandRegistry 分发的命令，确保每个命令在 MenuItemTag 中都有对应的 case（如 increaseFontSize、decreaseFontSize、showSettings、showHelp、showLogin、showDebugSettings、testAudioFileAPI、showOfflineOperations、showAboutPanel、showFindPanel、showFindAndReplacePanel、findNext、findPrevious、createNewWindow、moveWindowToLeftHalf、moveWindowToRightHalf、moveWindowToTopHalf、moveWindowToBottomHalf、maximizeWindow、restoreWindow、tileWindowToLeft、tileWindowToRight 等）
  - [x] 6.2 编译验证

- [x] 7. 最终验证与清理
  - [x] 7.1 执行完整编译，确保无错误无新增警告
  - [x] 7.2 更新 project.yml 并执行 xcodegen generate（如有新增文件）
  - [x] 7.3 验证代码量变化符合预期（AppDelegate 净减约 235 行，MenuManager 净减约 1200 行）
