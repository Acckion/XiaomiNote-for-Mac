# 调试基础设施清理 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 移除 NativeEditorLogger、NativeEditorMetrics、NativeEditorErrorHandler、ParagraphManagerDebugView、ParagraphDebugWindowController、PerformanceMonitor 共 6 个调试/性能监控文件，统一使用 LogService.shared 记录日志。

**Architecture:** 提取 NativeEditorError 枚举到独立文件（SafeRenderer 和 NativeEditorInitializer 依赖它抛出错误），然后逐步移除调试基础设施的引用，最后删除文件并更新文档。

**Tech Stack:** Swift 6.0, AppKit, XcodeGen

---

## 依赖关系分析

### 要删除的 6 个文件

| 文件 | 外部消费者 |
|------|-----------|
| `Sources/View/NativeEditor/Debug/NativeEditorLogger.swift` | SafeRenderer, NativeEditorInitializer, EditorRecoveryManager, NativeEditorErrorHandler |
| `Sources/View/NativeEditor/Debug/NativeEditorMetrics.swift` | SafeRenderer, NativeEditorInitializer, NativeEditorLogger, NativeEditorErrorHandler |
| `Sources/View/NativeEditor/Debug/NativeEditorErrorHandler.swift` | SafeRenderer, NativeEditorInitializer |
| `Sources/View/NativeEditor/Debug/ParagraphManagerDebugView.swift` | ParagraphDebugWindowController |
| `Sources/Window/Controllers/ParagraphDebugWindowController.swift` | WindowManager |
| `Sources/View/NativeEditor/Performance/PerformanceMonitor.swift` | EditorModule, NativeEditorContext, NativeEditorCoordinator, UnifiedEditorWrapper, AppCoordinator |

### 要保留的类型

- `NativeEditorError` 枚举（从 NativeEditorErrorHandler.swift 提取）：SafeRenderer 和 NativeEditorInitializer 用它 throw 错误

### 安全删除的类型（无外部引用）

- NativeEditorLogger 内部：LogLevel, LogCategory, LogEntry, FormatStateChangeRecord, FormatStateChangeTrigger
- NativeEditorErrorHandler 内部：ErrorRecoveryAction, ErrorHandlingResult, ErrorRecord, Notification.Name.nativeEditorNeedsRefresh, Notification.Name.nativeEditorErrorOccurred
- NativeEditorMetrics 内部：MetricType, MetricRecord, MetricStatistics, PerformanceMeasurer

---

## 要修改的文件清单

| 文件 | 修改内容 |
|------|---------|
| `Sources/View/NativeEditor/Core/SafeRenderer.swift` | 移除 logger/errorHandler/metrics 属性，移除所有 CFAbsoluteTimeGetCurrent 计时代码，catch 块改用 LogService.shared.error |
| `Sources/View/NativeEditor/Core/NativeEditorInitializer.swift` | NativeEditorInitializer + EditorRecoveryManager 两个类：移除 logger/errorHandler/metrics，改用 LogService.shared |
| `Sources/View/NativeEditor/Core/NativeEditorCoordinator.swift` | 移除所有 performanceMonitor 调用（5 处） |
| `Sources/View/Bridge/NativeEditorContext.swift` | 移除 `var performanceMonitor: PerformanceMonitor?` 属性 |
| `Sources/View/Bridge/UnifiedEditorWrapper.swift` | 移除 performanceMonitor 调用（1 处） |
| `Sources/Service/Editor/EditorModule.swift` | 移除 performanceMonitor 属性和构造 |
| `Sources/Coordinator/AppCoordinator.swift` | 移除 performanceMonitor 接线（1 行） |
| `Sources/Window/WindowManager.swift` | 移除 paragraphDebugWindowController 属性和 showParagraphDebugWindow 方法 |
| `Sources/App/MenuManager.swift` | 移除调试子菜单中的"段落管理器调试"菜单项 |
| `Sources/App/MenuActionHandler.swift` | 移除 showParagraphDebugWindow 方法 |
| `Sources/App/AppDelegate.swift` | 移除 showParagraphDebugWindow 方法 |
| `Sources/View/NativeEditor/Core/NativeEditorView.swift` | 移除引用 NativeEditorErrorHandler 的注释 |
| `AGENTS.md` | 从 15 个单例列表中移除 NativeEditorLogger, NativeEditorMetrics, NativeEditorErrorHandler（变为 12 个） |
| `CHANGELOG.md` | 添加本次重构记录 |


---

## Task 1: 创建分支 + 提取 NativeEditorError 枚举

**Files:**
- Create: `Sources/View/NativeEditor/Core/NativeEditorError.swift`

**Step 1: 从 dev 创建重构分支**

```bash
git checkout dev
git checkout -b refactor/119-debug-infrastructure-cleanup
```

**Step 2: 创建 NativeEditorError.swift**

从 `Sources/View/NativeEditor/Debug/NativeEditorErrorHandler.swift` 提取 `NativeEditorError` 枚举到新文件 `Sources/View/NativeEditor/Core/NativeEditorError.swift`。

只保留枚举本身和 `errorDescription` 计算属性。不保留 `errorCode`、`isRecoverable`、`suggestedRecovery`（这些只被 NativeEditorErrorHandler 内部使用）。

```swift
//
//  NativeEditorError.swift
//  MiNoteMac
//
//  原生编辑器错误类型

import Foundation

/// 原生编辑器错误类型
enum NativeEditorError: Error, LocalizedError {
    // 初始化错误
    case initializationFailed(reason: String)
    case systemVersionNotSupported(required: String, current: String)
    case frameworkNotAvailable(framework: String)

    // 渲染错误
    case renderingFailed(element: String, reason: String)
    case attachmentCreationFailed(type: String)
    case layoutManagerError(reason: String)

    // 格式转换错误
    case xmlParsingFailed(xml: String, reason: String)
    case attributedStringConversionFailed(reason: String)
    case unsupportedXMLElement(element: String)
    case invalidXMLStructure(details: String)

    // 内容错误
    case contentLoadFailed(reason: String)
    case contentSaveFailed(reason: String)
    case imageLoadFailed(fileId: String?, reason: String)

    // 状态错误
    case invalidEditorState(state: String)
    case contextSyncFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .initializationFailed(reason):
            "编辑器初始化失败: \(reason)"
        case let .systemVersionNotSupported(required, current):
            "系统版本不支持: 需要 \(required)，当前 \(current)"
        case let .frameworkNotAvailable(framework):
            "框架不可用: \(framework)"
        case let .renderingFailed(element, reason):
            "渲染失败 [\(element)]: \(reason)"
        case let .attachmentCreationFailed(type):
            "附件创建失败: \(type)"
        case let .layoutManagerError(reason):
            "布局管理器错误: \(reason)"
        case let .xmlParsingFailed(_, reason):
            "XML 解析失败: \(reason)"
        case let .attributedStringConversionFailed(reason):
            "AttributedString 转换失败: \(reason)"
        case let .unsupportedXMLElement(element):
            "不支持的 XML 元素: \(element)"
        case let .invalidXMLStructure(details):
            "无效的 XML 结构: \(details)"
        case let .contentLoadFailed(reason):
            "内容加载失败: \(reason)"
        case let .contentSaveFailed(reason):
            "内容保存失败: \(reason)"
        case let .imageLoadFailed(fileId, reason):
            "图片加载失败 [\(fileId ?? "unknown")]: \(reason)"
        case let .invalidEditorState(state):
            "无效的编辑器状态: \(state)"
        case let .contextSyncFailed(reason):
            "上下文同步失败: \(reason)"
        }
    }
}
```

**Step 3: xcodegen + 构建验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

预期：编译成功（NativeEditorError 现在有两份定义，但因为在不同文件中定义了相同类型名会报重复定义错误）。

注意：此时会编译失败，因为 NativeEditorErrorHandler.swift 中还有同名枚举。这是预期的，Task 2 会删除旧文件解决冲突。所以 Task 1 只创建文件，不做构建验证，与 Task 2 合并提交。

**Step 4: 不提交（与 Task 2 合并提交）**

---

## Task 2: 删除 NativeEditorLogger + NativeEditorMetrics + NativeEditorErrorHandler

**Files:**
- Delete: `Sources/View/NativeEditor/Debug/NativeEditorLogger.swift`
- Delete: `Sources/View/NativeEditor/Debug/NativeEditorMetrics.swift`
- Delete: `Sources/View/NativeEditor/Debug/NativeEditorErrorHandler.swift`

**Step 1: 删除 3 个文件**

```bash
rm Sources/View/NativeEditor/Debug/NativeEditorLogger.swift
rm Sources/View/NativeEditor/Debug/NativeEditorMetrics.swift
rm Sources/View/NativeEditor/Debug/NativeEditorErrorHandler.swift
```

**Step 2: xcodegen generate**

```bash
xcodegen generate
```

预期：此时编译会失败，因为 SafeRenderer、NativeEditorInitializer、EditorRecoveryManager 还引用了已删除的类型。Task 3-4 会修复这些引用。不做构建验证，继续下一个 Task。

---

## Task 3: 清理 SafeRenderer.swift

**Files:**
- Modify: `Sources/View/NativeEditor/Core/SafeRenderer.swift`

**修改内容：**

1. 移除 3 个属性：`errorHandler`、`logger`、`metrics`
2. 移除所有 `CFAbsoluteTimeGetCurrent()` 计时代码
3. 移除所有 `metrics.recordRendering()` 调用
4. 移除所有 `logger.logRendering()` 调用
5. catch 块中的 `errorHandler.handleError()` 改为 `LogService.shared.error(.editor, ...)`
6. `safeRenderElement` 中的 `logger.logWarning()` 改为 `LogService.shared.warning(.editor, ...)`

**修改后的 SafeRenderer 结构：**

每个 safe 方法简化为：
```swift
func safeCreateXxxAttachment(...) -> NSAttributedString {
    do {
        let attachment = try createXxxAttachmentWithValidation(...)
        return NSAttributedString(attachment: attachment)
    } catch {
        LogService.shared.error(.editor, "Xxx 附件创建失败: \(error.localizedDescription)")
        return createFallbackXxx(...)
    }
}
```

---

## Task 4: 清理 NativeEditorInitializer.swift

**Files:**
- Modify: `Sources/View/NativeEditor/Core/NativeEditorInitializer.swift`

**修改内容（NativeEditorInitializer 类）：**

1. 移除 3 个属性：`logger`、`errorHandler`、`metrics`
2. 移除所有 `CFAbsoluteTimeGetCurrent()` 计时代码
3. 移除所有 `metrics.recordInitialization()` 调用
4. 所有 `logger.logXxx()` 改为 `LogService.shared.xxx(.editor, ...)`
5. 所有 `errorHandler.handleError()` 调用直接删除（错误已通过返回值传递）
6. `resetInitializationState()` 中移除 `errorHandler.resetErrorCount()`

**修改内容（EditorRecoveryManager 类）：**

1. 移除 `logger` 属性
2. 所有 `logger.logXxx()` 改为 `LogService.shared.xxx(.editor, ...)`
3. `logger.logError(error, context:, category:)` 改为 `LogService.shared.error(.editor, "xxx: \(error.localizedDescription)")`

**Step: xcodegen + 构建验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

预期：编译成功。

**Step: 提交**

```bash
git add -A
git commit -m "refactor(editor): 移除 NativeEditorLogger/Metrics/ErrorHandler，统一使用 LogService

- 提取 NativeEditorError 枚举到独立文件
- SafeRenderer 移除计时代码和调试日志，catch 块改用 LogService
- NativeEditorInitializer 和 EditorRecoveryManager 改用 LogService
- 删除 NativeEditorLogger.swift（800+ 行）
- 删除 NativeEditorMetrics.swift（400+ 行）
- 删除 NativeEditorErrorHandler.swift（490+ 行）"
```

---

## Task 5: 移除 PerformanceMonitor

**Files:**
- Delete: `Sources/View/NativeEditor/Performance/PerformanceMonitor.swift`
- Modify: `Sources/View/Bridge/NativeEditorContext.swift` - 移除 `var performanceMonitor: PerformanceMonitor?`
- Modify: `Sources/Service/Editor/EditorModule.swift` - 移除 `performanceMonitor` 属性和构造
- Modify: `Sources/Coordinator/AppCoordinator.swift` - 移除 `performanceMonitor` 接线
- Modify: `Sources/View/NativeEditor/Core/NativeEditorCoordinator.swift` - 移除 5 处 `performanceMonitor` 调用
- Modify: `Sources/View/Bridge/UnifiedEditorWrapper.swift` - 移除 1 处 `performanceMonitor` 调用

**Step 1: 删除文件**

```bash
rm Sources/View/NativeEditor/Performance/PerformanceMonitor.swift
```

**Step 2: 修改 NativeEditorContext.swift**

移除：
```swift
var performanceMonitor: PerformanceMonitor?
```

**Step 3: 修改 EditorModule.swift**

移除：
```swift
let performanceMonitor: PerformanceMonitor
```
和构造中的：
```swift
let perfMonitor = PerformanceMonitor()
self.performanceMonitor = perfMonitor
```

**Step 4: 修改 AppCoordinator.swift**

移除：
```swift
noteEditorState.nativeEditorContext.performanceMonitor = editorModule.performanceMonitor
```

**Step 5: 修改 NativeEditorCoordinator.swift**

移除 `textDidChange` 方法中的 5 处 `parent.editorContext.performanceMonitor?.xxx()` 调用。

**Step 6: 修改 UnifiedEditorWrapper.swift**

移除：
```swift
nativeEditorContext.performanceMonitor?.recordContentReload()
```

**Step 7: xcodegen + 构建验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 8: 提交**

```bash
git add -A
git commit -m "refactor(editor): 移除 PerformanceMonitor

- 删除 PerformanceMonitor.swift
- 从 EditorModule、NativeEditorContext、AppCoordinator 移除属性和接线
- 从 NativeEditorCoordinator 移除 5 处性能监控调用
- 从 UnifiedEditorWrapper 移除 1 处性能监控调用"
```

---

## Task 6: 移除 ParagraphManagerDebugView + ParagraphDebugWindowController + 调试菜单项

**Files:**
- Delete: `Sources/View/NativeEditor/Debug/ParagraphManagerDebugView.swift`
- Delete: `Sources/Window/Controllers/ParagraphDebugWindowController.swift`
- Modify: `Sources/Window/WindowManager.swift` - 移除调试工具区域
- Modify: `Sources/App/MenuManager.swift` - 移除"段落管理器调试"菜单项
- Modify: `Sources/App/MenuActionHandler.swift` - 移除 showParagraphDebugWindow 方法
- Modify: `Sources/App/AppDelegate.swift` - 移除 showParagraphDebugWindow 方法

**Step 1: 删除文件**

```bash
rm Sources/View/NativeEditor/Debug/ParagraphManagerDebugView.swift
rm Sources/Window/Controllers/ParagraphDebugWindowController.swift
```

**Step 2: 修改 WindowManager.swift**

移除整个 `// MARK: - 调试工具` 区域（约 10 行）：
```swift
// MARK: - 调试工具

/// 段落管理器调试窗口控制器
private var paragraphDebugWindowController: ParagraphDebugWindowController?

/// 显示段落管理器调试窗口
public func showParagraphDebugWindow() {
    if paragraphDebugWindowController == nil {
        paragraphDebugWindowController = ParagraphDebugWindowController()
    }
    paragraphDebugWindowController?.show()
}
```

**Step 3: 修改 MenuManager.swift**

在 `createDebugToolsSubmenu()` 方法中，移除"段落管理器调试"菜单项（保留"调试设置"菜单项）。

**Step 4: 修改 MenuActionHandler.swift**

移除 `showParagraphDebugWindow` 方法。

**Step 5: 修改 AppDelegate.swift**

移除 `showParagraphDebugWindow` 方法。

**Step 6: 修改 NativeEditorView.swift**

移除注释行：
```swift
// nativeEditorNeedsRefresh 已在 NativeEditorErrorHandler.swift 中定义
```

**Step 7: xcodegen + 构建验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

**Step 8: 提交**

```bash
git add -A
git commit -m "refactor(editor): 移除段落调试面板和调试菜单项

- 删除 ParagraphManagerDebugView.swift
- 删除 ParagraphDebugWindowController.swift
- 从 WindowManager 移除调试窗口管理代码
- 从菜单系统移除段落管理器调试入口"
```

---

## Task 7: 更新文档 + 清理过时文档

**Files:**
- Modify: `AGENTS.md`
- Modify: `CHANGELOG.md`
- Delete: `docs/如何打开段落管理器调试窗口.md`（如果存在）
- Delete: `docs/PARAGRAPH_MANAGER_DEMO.md`（如果存在）

**Step 1: 更新 AGENTS.md**

将单例列表从 15 个改为 12 个，移除 NativeEditorLogger、NativeEditorMetrics、NativeEditorErrorHandler：

```
仅 12 个基础设施类保留 `static let shared`：LogService, DatabaseService, EventBus, NetworkMonitor, NetworkErrorHandler, NetworkLogger, AudioPlayerService, AudioRecorderService, AudioDecryptService, PrivateNotesPasswordManager, ViewOptionsManager, PreviewHelper
```

**Step 2: 更新 CHANGELOG.md**

在最新版本下添加：
```
- 调试基础设施清理：移除 NativeEditorLogger（800+ 行）、NativeEditorMetrics（400+ 行）、NativeEditorErrorHandler（490+ 行）、PerformanceMonitor（130 行）、ParagraphManagerDebugView、ParagraphDebugWindowController，统一使用 LogService.shared 记录日志，提取 NativeEditorError 枚举到独立文件，单例数量从 15 个减少到 12 个
```

**Step 3: 删除过时文档**

```bash
rm -f docs/如何打开段落管理器调试窗口.md
rm -f docs/PARAGRAPH_MANAGER_DEMO.md
```

**Step 4: 提交**

```bash
git add -A
git commit -m "docs: 更新文档，移除过时的调试工具文档

- AGENTS.md 单例列表从 15 个更新为 12 个
- CHANGELOG.md 添加调试基础设施清理记录
- 删除段落管理器调试相关文档"
```

---

## Task 8: 最终构建验证

**Step 1: 完整构建**

```bash
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30
```

预期：BUILD SUCCEEDED，零错误。

**Step 2: 确认删除文件数量**

```bash
git diff --stat dev
```

预期：6 个文件删除，1 个文件创建（NativeEditorError.swift），约 10 个文件修改，净减少约 2800+ 行代码。
