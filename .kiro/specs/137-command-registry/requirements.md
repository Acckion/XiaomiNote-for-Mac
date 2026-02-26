# 需求文档：AppDelegate 命令注册表

## 概述

将 AppDelegate 的 84 个 `@objc` selector 转发方法收敛为 1 个统一的 `performCommand(_:)` 方法，通过 CommandRegistry 注册表驱动菜单项构建与命令分发，降低维护成本。

## 背景

当前 AppDelegate 有 84 个 `@objc func` 方法，每个方法体仅一行：构造 Command 并调用 `commandDispatcher?.dispatch()`。其中 6 个是别名方法（setHeading1/2/3、toggleBulletList、toggleNumberedList、toggleChecklist），重复映射到同一 Command。MenuManager 三个文件约 1900 行，手动逐个创建 NSMenuItem。新增一个菜单项需要修改 3 个文件（AppDelegate + MenuManager + MenuItemTag），维护成本高。

## 术语表

- **CommandRegistry**：命令注册表，持有 `[MenuItemTag: MenuCommandEntry]` 映射，集中管理所有菜单命令的元数据
- **MenuCommandEntry**：菜单命令条目，包含 tag、title、commandType、keyEquivalent、modifiers、symbolName、group 等属性
- **MenuGroup**：菜单分组枚举，定义菜单项的逻辑分组（如 fileNew、formatParagraph、editAttachment 等）
- **AppCommand**：应用命令协议，定义 `init()` 和 `execute(with:)` 方法
- **CommandDispatcher**：命令调度器，接收 Command 并构造 CommandContext 执行
- **MenuItemTag**：菜单项标签枚举，用于标识菜单项
- **performCommand**：统一的 @objc 方法，替代 84 个独立的 selector 转发方法
- **系统 selector 菜单项**：使用 AppKit 框架内置 selector（如 cut:、copy:、paste:、undo:、redo: 等）的菜单项，由系统响应链处理

## 需求列表

### 需求 1：CommandRegistry 数据结构

**用户故事：** 作为开发者，我希望有一个集中的命令注册表，以便在一处管理所有菜单命令的元数据。

#### 验收标准

1. THE CommandRegistry SHALL 持有 `[MenuItemTag: MenuCommandEntry]` 类型的映射表，存储所有注册表驱动的菜单命令条目
2. THE MenuCommandEntry SHALL 包含 tag（MenuItemTag）、title（String）、commandType（AppCommand.Type）、keyEquivalent（String）、modifiers（NSEvent.ModifierFlags）、symbolName（String?）、group（MenuGroup）属性
3. THE CommandRegistry SHALL 提供 `entry(for: MenuItemTag)` 方法，返回指定 tag 对应的 MenuCommandEntry
4. THE CommandRegistry SHALL 提供 `entries(for: MenuGroup)` 方法，返回指定分组下的所有 MenuCommandEntry 列表
5. WHEN CommandRegistry 初始化时，THE CommandRegistry SHALL 注册约 78 个菜单命令条目（84 个原始方法减去 6 个别名方法）

### 需求 2：MenuGroup 分组枚举

**用户故事：** 作为开发者，我希望菜单命令按逻辑分组，以便 MenuManager 按组批量构建菜单项。

#### 验收标准

1. THE MenuGroup SHALL 定义以下分组：fileNew、fileShare、fileImport、fileExport、fileNoteActions（文件菜单）；formatParagraph、formatChecklist、formatChecklistMore、formatMoveItem、formatAppearance、formatFont、formatAlignment、formatIndent（格式菜单）；editAttachment（编辑菜单）；viewMode、viewFolderOptions、viewZoom、viewSections（显示菜单）；windowLayout、windowTile、windowNote（窗口菜单）
2. THE MenuGroup SHALL 为 String 类型的 RawRepresentable 枚举

### 需求 3：AppCommand 协议变更

**用户故事：** 作为开发者，我希望所有 Command 可通过注册表零参数构造，以便 performCommand 方法能统一实例化任意命令。

#### 验收标准

1. THE AppCommand 协议 SHALL 新增 `init()` 要求，使所有遵循 AppCommand 的类型支持零参数构造
2. WHEN 现有 Command 类型已有自定义 init 参数时，THE Command SHALL 保留 `init()` 的默认实现
3. THE CommandContext SHALL 保持现有结构不变，继续持有 AppCoordinator 引用


### 需求 4：带参数 Command 改造

**用户故事：** 作为开发者，我希望带参数的 Command 改为在 execute() 中从 context 获取参数，以便支持零参数构造。

#### 验收标准

1. WHEN CreateNoteCommand 通过零参数构造时，THE CreateNoteCommand SHALL 在 execute() 中从 `context.coordinator.folderState.selectedFolderId` 获取目标文件夹 ID
2. WHEN ShareNoteCommand 通过零参数构造时，THE ShareNoteCommand SHALL 在 execute() 中从 `context.coordinator` 获取当前窗口引用
3. FOR ALL 约 8 个带参数的 Command，THE Command SHALL 支持 `init()` 零参数构造，并在 `execute(with:)` 中从 CommandContext 获取所需参数
4. WHEN 带参数 Command 改造完成后，THE Command SHALL 保持与改造前完全一致的业务行为

### 需求 5：AppDelegate 统一 performCommand 方法

**用户故事：** 作为开发者，我希望 AppDelegate 只保留 1 个统一的菜单命令入口方法，以便大幅减少样板代码。

#### 验收标准

1. THE AppDelegate SHALL 提供 1 个 `@objc func performCommand(_ sender: Any?)` 方法，替代现有 84 个 @objc 转发方法
2. WHEN performCommand 接收到 NSMenuItem sender 时，THE AppDelegate SHALL 从 sender 的 tag 属性解析出 MenuItemTag，查询 CommandRegistry 获取对应的 commandType，零参数构造 Command 实例并通过 CommandDispatcher 分发
3. IF performCommand 无法从 sender 解析出有效的 MenuItemTag 或未在 CommandRegistry 中找到对应条目，THEN THE AppDelegate SHALL 记录警告日志并忽略该调用
4. WHEN performCommand 替代完成后，THE AppDelegate SHALL 删除原有 84 个 @objc 转发方法
5. WHEN performCommand 替代完成后，THE AppDelegate SHALL 删除 6 个别名方法（setHeading1、setHeading2、setHeading3、toggleBulletList、toggleNumberedList、toggleChecklist）

### 需求 6：MenuManager 注册表驱动构建

**用户故事：** 作为开发者，我希望 MenuManager 从注册表驱动构建菜单项，以便减少手写 NSMenuItem 的样板代码。

#### 验收标准

1. THE MenuManager SHALL 提供 `buildMenuItem(for: MenuItemTag)` 方法，从 CommandRegistry 查询条目并构建 NSMenuItem
2. WHEN buildMenuItem 构建 NSMenuItem 时，THE MenuManager SHALL 设置 title、action（指向 AppDelegate.performCommand）、keyEquivalent、keyEquivalentModifierMask、tag 属性
3. WHEN MenuCommandEntry 包含 symbolName 时，THE MenuManager SHALL 为 NSMenuItem 设置对应的 SF Symbol 图标
4. WHEN MenuManager 构建菜单时，THE MenuManager SHALL 将手写 NSMenuItem 代码（每项 5-10 行）替换为 `buildMenuItem(for:)` 调用（每项 1 行）
5. THE MenuManager SHALL 继续手动控制分隔线、子菜单结构和菜单层级，CommandRegistry 只负责单个菜单项属性

### 需求 7：系统 selector 菜单项保持不变

**用户故事：** 作为开发者，我希望使用系统 selector 的菜单项保持原样，以便 AppKit 响应链机制正常工作。

#### 验收标准

1. THE MenuManager SHALL 保持约 15-20 个系统 selector 菜单项的原有构建方式不变
2. THE 系统 selector 菜单项 SHALL 包括但不限于：terminate、hide、unhideAll、orderFrontStandardAboutPanel、orderFrontCharacterPalette（NSApplication）；performClose、performMiniaturize、performZoom、toggleToolbarShown、runToolbarCustomizationPalette、toggleFullScreen（NSWindow）；cut、copy、paste、pasteAsPlainText、delete、selectAll、undo、redo（NSText/NSTextView）；performFindPanelAction 及拼写/替换/转换/语音相关（NSTextView）
3. THE 系统 selector 菜单项 SHALL 不纳入 CommandRegistry 注册表

### 需求 8：代码清理与验证

**用户故事：** 作为开发者，我希望重构后代码量显著减少且功能行为不变，以便降低长期维护成本。

#### 验收标准

1. WHEN 重构完成后，THE AppDelegate SHALL 净减少约 235 行代码（84 个方法约 250 行减至 1 个方法约 15 行）
2. WHEN 重构完成后，THE MenuManager（含扩展文件）SHALL 净减少约 1200-1300 行代码（从约 1900 行减至约 600-700 行）
3. WHEN 重构完成后，THE CommandRegistry（新增文件）SHALL 约 200 行代码
4. WHEN 重构完成后，THE 项目 SHALL 净减少约 700-800 行代码
5. WHEN 重构完成后，THE 项目 SHALL 编译通过且无新增警告
6. WHEN 重构完成后，所有菜单项、快捷键的功能 SHALL 与重构前完全一致
7. THE validateMenuItem 机制 SHALL 保持不变，无需额外处理

### 需求 9：新增菜单项流程简化

**用户故事：** 作为开发者，我希望新增菜单项只需修改 1 处，以便降低日常开发的维护成本。

#### 验收标准

1. WHEN 需要新增一个菜单命令时，THE 开发者 SHALL 只需在 CommandRegistry 添加 1 条 MenuCommandEntry 记录，并创建对应的 AppCommand 实现
2. WHEN 需要新增一个菜单命令时，THE 开发者 SHALL 不再需要修改 AppDelegate 添加 @objc 方法
3. WHEN 需要新增一个菜单命令时，THE MenuManager SHALL 通过 `buildMenuItem(for:)` 自动从注册表获取菜单项属性

## 非目标

- 不修改 MenuItemTag 枚举的值定义（保持现有 rawValue 不变）
- 不修改 CommandContext 的粒度（细粒度 Context 属于后续优化）
- 不实现尚未实现的功能（空实现的 Command 保持原样）
- 不修改 validateMenuItem 的验证逻辑
- 不修改 MenuStateManager 的状态管理逻辑
