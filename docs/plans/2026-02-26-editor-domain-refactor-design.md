# 编辑器域重构设计文档

> 日期：2026-02-26
> 范围：编辑器大文件拆分 + 格式动作 Command 化
> 关联：TODO P2 项「拆分 UnifiedFormatManager.swift」

## 1. 问题概述

Editor 域是项目最大的业务域（85 个 Swift 文件，约 29000 行），存在以下问题：

1. 多个文件超过 600 行复杂度约束（UnifiedFormatManager 1122 行、CustomAttachments 902 行、AudioAttachment 871 行、NativeTextView 972 行）
2. `MainWindowController+Actions.swift` 中约 20 个格式相关 @objc 方法直接调用 `coordinator.editorModule.formatStateManager`，Window 层与编辑器内部 API 强耦合
3. `CustomAttachments.swift` 把 5 个不同类型的附件类塞在一个文件中，缺少按语义分组
4. 附件体系缺少统一抽象，文件类附件（音频、图片）和列表标记类附件（复选框、项目符号、有序编号）没有公共协议，不利于扩展

## 2. 设计目标

1. 所有编辑器相关文件控制在 600 行以内
2. 格式动作通过 Command 体系调度，消除 Window 层对编辑器的直接耦合
3. 附件按语义分组：文件类附件共享公共协议，列表标记类附件共享基类
4. 不改变任何用户可见行为，纯内部重构

## 3. 方案设计

### 3.1 格式动作 Command 化

当前状态：`MainWindowController+Actions.swift` 中有约 20 个格式相关方法，直接调用 `coordinator.editorModule.formatStateManager.toggleFormat(.bold)` 等。

目标：这些方法迁移到 `FormatCommands.swift`，通过 CommandRegistry 注册，MainWindowController 中的 @objc 方法缩减为 1-2 行的 Command dispatch。

涉及的格式动作：
- 内联格式：toggleBold、toggleItalic、toggleUnderline、toggleStrikethrough
- 段落格式：setHeading1/2/3、setBodyText
- 列表格式：toggleBulletList、toggleNumberedList、toggleCheckboxList
- 对齐格式：alignLeft、alignCenter、alignRight
- 缩进操作：increaseIndent、decreaseIndent
- 字号操作：increaseFontSize、decreaseFontSize（当前为 TODO 占位）

同时清理 `MainWindowController+Actions.swift` 中的空壳占位方法：
- toggleBlockQuote、markAsChecked、checkAll、uncheckAll、moveCheckedToBottom、deleteCheckedItems、moveItemUp、moveItemDown、toggleLightBackground、toggleHighlight、expandSection、expandAllSections、collapseSection、collapseAllSections
- 这些方法当前只调用 `showFeatureNotImplementedAlert`，应从菜单中移除或标记为 disabled，不保留空壳代码

预期效果：`MainWindowController+Actions.swift` 减少约 300-400 行。

### 3.2 UnifiedFormatManager 拆分

当前状态：1122 行，承担格式应用、换行处理、格式检测、typingAttributes 同步、列表操作、引用操作、缩进操作等所有格式职责。

拆分方案（使用 Swift extension 分文件）：

| 文件 | 职责 | 预估行数 |
|------|------|---------|
| `UnifiedFormatManager.swift` | 核心类定义、属性、注册/注销、统一入口 | ~200 |
| `UnifiedFormatManager+InlineFormat.swift` | 内联格式应用（加粗、斜体等） | ~150 |
| `UnifiedFormatManager+BlockFormat.swift` | 块级格式应用（标题、对齐等） | ~200 |
| `UnifiedFormatManager+Detection.swift` | 格式检测（光标位置格式状态） | ~250 |
| `UnifiedFormatManager+TypingAttributes.swift` | typingAttributes 同步 | ~120 |
| `UnifiedFormatManager+ListOps.swift` | 列表操作委托 | ~120 |
| `UnifiedFormatManager+QuoteIndent.swift` | 引用操作 + 缩进操作 | ~120 |

辅助类型保留在主文件中：`FormatCategory` 枚举、`TextFormat` 扩展、`NewLineContext` 结构体。

### 3.3 附件体系重组

#### 3.3.1 附件分类

按语义将附件分为三类：

1. 文件类附件（FileAttachment）：音频、图片，未来可扩展 PDF、视频等
2. 列表标记类附件（ListMarkerAttachment）：复选框、项目符号、有序编号
3. 装饰类附件（DecorativeAttachment）：分割线、引用块标记

#### 3.3.2 文件类附件

引入 `FileAttachmentProtocol` 协议，统一文件类附件的公共行为：

```swift
protocol FileAttachmentProtocol: ThemeAwareAttachment {
    var fileId: String { get }
    var loadingState: FileAttachmentLoadingState { get }
    func startLoading()
}

enum FileAttachmentLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}
```

文件结构：
- `FileAttachmentProtocol.swift`：公共协议定义
- `AudioAttachment.swift`：音频附件核心（属性、生命周期）
- `AudioAttachment+Rendering.swift`：音频附件 UI 渲染
- `AudioAttachment+Playback.swift`：播放状态管理与控制
- `ImageAttachment.swift`：图片附件（468 行，暂不拆分）

#### 3.3.3 列表标记类附件

引入 `ListMarkerAttachment` 基类，统一列表标记的公共逻辑（主题适配、尺寸计算、缩进处理）：

```swift
class ListMarkerAttachment: NSTextAttachment, ThemeAwareAttachment {
    var level: Int
    var indent: Int
    var isDarkMode: Bool
    func updateTheme() { /* 公共主题适配 */ }
}
```

文件结构：
- `ListMarkerAttachment.swift`：基类定义（公共属性、主题适配、尺寸计算）
- `CheckboxAttachment.swift`：复选框标记（从 CustomAttachments 提取，含 InteractiveAttachment 协议实现）
- `BulletAttachment.swift`：项目符号标记
- `OrderAttachment.swift`：有序编号标记

#### 3.3.4 装饰类附件

- `HorizontalRuleAttachment.swift`：分割线（从 CustomAttachments 提取）
- `QuoteBlockAttachment` 保留在 `QuoteBlockRenderer.swift` 中（与渲染逻辑紧密耦合）

#### 3.3.5 协议文件

- `AttachmentProtocols.swift`：保留 `InteractiveAttachment`、`ThemeAwareAttachment` 协议定义

### 3.4 NativeTextView 拆分

当前状态：972 行，混合了光标限制、键盘事件处理、粘贴逻辑、附件交互等。

拆分方案：

| 文件 | 职责 | 预估行数 |
|------|------|---------|
| `NativeTextView.swift` | 核心类定义、属性、基础重写 | ~250 |
| `NativeTextView+CursorRestriction.swift` | 列表光标位置限制逻辑 | ~200 |
| `NativeTextView+KeyboardHandling.swift` | keyDown、键盘快捷键处理 | ~250 |
| `NativeTextView+Paste.swift` | 粘贴逻辑（富文本/纯文本/图片） | ~200 |
| `NativeTextView+AttachmentInteraction.swift` | 附件点击、拖拽交互 | ~100 |

## 4. 目录结构变更

重构后 Attachment 目录结构：

```text
Sources/Features/Editor/UI/NativeEditor/Attachment/
├── AttachmentProtocols.swift           # InteractiveAttachment, ThemeAwareAttachment
├── FileAttachmentProtocol.swift        # 文件类附件公共协议
├── AudioAttachment.swift               # 音频附件核心
├── AudioAttachment+Rendering.swift     # 音频附件渲染
├── AudioAttachment+Playback.swift      # 音频播放控制
├── ImageAttachment.swift               # 图片附件（不变）
├── ImageStorageManager.swift           # 图片存储管理（不变）
├── ListMarkerAttachment.swift          # 列表标记基类
├── CheckboxAttachment.swift            # 复选框标记
├── BulletAttachment.swift              # 项目符号标记
├── OrderAttachment.swift               # 有序编号标记
├── HorizontalRuleAttachment.swift      # 分割线
├── AttachmentHighlightView.swift       # 不变
├── AttachmentKeyboardHandler.swift     # 不变
├── AttachmentSelectionManager.swift    # 不变
└── AttachmentSelectionState.swift      # 不变
```

删除文件：`CustomAttachments.swift`（内容已拆分到各独立文件）

## 5. 执行顺序

1. 格式动作 Command 化（风险最低，与文件拆分无依赖）
2. CustomAttachments 拆分 + 附件协议引入（独立性强）
3. AudioAttachment 拆分（依赖步骤 2 的协议）
4. UnifiedFormatManager 拆分（纯 extension 拆分，风险低）
5. NativeTextView 拆分（纯 extension 拆分，风险低）

每步完成后执行 `xcodegen generate` + 编译验证。

## 6. 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 附件基类引入导致现有渲染行为变化 | 基类只提取公共属性和主题适配，不改变渲染逻辑 |
| extension 拆分后编译顺序问题 | Swift extension 无编译顺序依赖，但需确保 access control 正确 |
| Command 化后格式菜单响应链断裂 | 每个 Command 迁移后立即手动测试对应菜单项 |
| XcodeGen 配置遗漏新文件 | 使用通配符 glob，新文件自动包含 |

## 7. 验收标准

1. 所有编辑器相关文件不超过 600 行
2. `MainWindowController+Actions.swift` 中无 `formatStateManager` 直接调用
3. 格式菜单功能行为不变
4. `./scripts/check-architecture.sh --strict` 通过
5. 编译通过，测试通过
