# 代码质量重构设计文档

日期：2026-02-22

## 概述

本次重构针对代码审计中发现的三个核心"屎山"模块，按优先级分两阶段执行：
1. **阶段一**：MiNoteService 网络层拆分（spec-102）
2. **阶段二**：编辑器桥接层拆分（spec-103）

---

## 阶段一：MiNoteService 拆分

### 现状问题

`MiNoteService.swift` 共 2,028 行，40+ 方法，承担了以下职责：
- Cookie/ServiceToken 认证管理
- HTTP 请求执行与错误处理
- 笔记 CRUD API
- 文件夹管理 API
- 文件上传/下载（图片、音频、通用文件）
- 同步 API
- 用户信息 API
- 响应解析（JSON → Model）

典型的 God Object 反模式，所有网络功能堆砌在一个类中。

### 拆分方案：完全拆分

将 MiNoteService 拆分为独立的功能类，每个类只负责一个领域。

#### 新文件结构

```
Sources/Network/
├── APIClient.swift              # 认证管理 + 请求执行（~300行）
├── API/
│   ├── NoteAPI.swift            # 笔记 CRUD（~250行）
│   ├── FolderAPI.swift          # 文件夹管理（~200行）
│   ├── FileAPI.swift            # 文件上传/下载（~500行）
│   ├── SyncAPI.swift            # 同步接口（~50行）
│   └── UserAPI.swift            # 用户信息（~100行）
├── ResponseParser.swift         # 响应解析工具（~150行）
├── MiNoteService.swift          # 保留为 Facade，标记 @available(*, deprecated)
├── MiNoteService+Encryption.swift
├── MiNoteService+NoteServiceProtocol.swift
├── NetworkClient.swift
├── NetworkClientProtocol.swift
├── NetworkErrorHandler.swift
├── NetworkLogger.swift
├── NetworkMonitor.swift
├── NetworkRecoveryHandler.swift
├── NetworkRequestManager.swift
└── Implementation/
    └── DefaultNoteService.swift
```

#### 各类职责

| 类名 | 职责 | 从 MiNoteService 提取的方法 |
|------|------|---------------------------|
| `APIClient` | 认证状态管理、请求执行、401处理 | `performRequest()`, `handle401Error()`, `setCookie()`, `clearCookie()`, `isAuthenticated()`, `hasValidCookie()`, `getHeaders()`, `getPostHeaders()`, `encodeURIComponent()`, `loadCredentials()`, `saveCredentials()`, `extractServiceToken()`, `checkIfInGracePeriod()` |
| `NoteAPI` | 笔记增删改查 | `createNote()`, `updateNote()`, `deleteNote()`, `restoreDeletedNote()`, `fetchNoteDetails()`, `fetchPage()`, `fetchPrivateNotes()`, `fetchDeletedNotes()`, 历史版本相关方法 |
| `FolderAPI` | 文件夹管理 | `createFolder()`, `renameFolder()`, `deleteFolder()`, `fetchFolderDetails()` |
| `FileAPI` | 文件上传下载 | `uploadImage()`, `uploadAudio()`, `uploadFile()`, `downloadFile()`, `downloadAudio()`, `downloadAndCacheAudio()`, 以及所有 private upload 流程方法 |
| `SyncAPI` | 全量同步 | `syncFull()` |
| `UserAPI` | 用户信息 | `fetchUserProfile()`, `checkServiceStatus()`, `checkCookieValidity()`, `updateCookieValidityCache()`, `getEncryptionInfo()` |
| `ResponseParser` | 响应解析（static） | `parseNotes()`, `parseFolders()`, `extractSyncTag()` |

#### 依赖关系

```
NoteAPI / FolderAPI / FileAPI / SyncAPI / UserAPI
                    ↓
              APIClient（认证 + 请求执行）
                    ↓
          NetworkRequestManager（底层网络）
```

所有 API 类持有 `APIClient` 引用，通过它执行请求。

#### 调用方迁移

主要调用方及迁移方式：
- `SyncEngine` → 注入 `NoteAPI`, `FolderAPI`, `SyncAPI`, `ResponseParser`
- `AuthState` → 注入 `APIClient`, `UserAPI`
- `NoteEditorState` → 注入 `NoteAPI`, `FileAPI`
- `NoteListState` → 注入 `NoteAPI`, `FolderAPI`
- `OperationProcessor` → 注入 `NoteAPI`, `FolderAPI`, `FileAPI`
- `ServiceLocator` → 注册所有新服务

#### 过渡策略

1. `MiNoteService` 保留为 Facade，内部转发到新类
2. 所有转发方法标记 `@available(*, deprecated, message: "请直接使用 XxxAPI")`
3. 逐步迁移调用方后，最终删除 Facade

---

## 阶段二：编辑器桥接层拆分

### 现状问题

两个核心文件过于庞大：
- `NativeEditorView.swift`（2,423行）：Coordinator 1,204行 + NativeTextView 910行 + NSViewRepresentable 约300行，全部挤在一个文件
- `NativeEditorContext.swift`（1,827行）：God Object，承担 10+ 职责

### NativeEditorView.swift 拆分

#### 新文件结构

```
Sources/View/NativeEditor/Core/
├── NativeEditorView.swift           # 纯 NSViewRepresentable（~250行）
├── NativeEditorCoordinator.swift    # NSTextViewDelegate + 内容同步（~500行）
├── CoordinatorFormatApplier.swift   # 格式应用方法（~400行）
└── NativeTextView.swift             # 自定义 NSTextView（~900行）
```

| 文件 | 职责 |
|------|------|
| `NativeEditorView.swift` | `makeNSView()`, `updateNSView()`, `makeCoordinator()` |
| `NativeEditorCoordinator.swift` | `NSTextViewDelegate` 实现、内容同步、音频附件检测、选择变化处理 |
| `CoordinatorFormatApplier.swift` | Coordinator 的 extension，所有格式应用方法 |
| `NativeTextView.swift` | 自定义 NSTextView 子类、键盘处理、列表行为、粘贴逻辑 |

### NativeEditorContext.swift 拆分

#### 新文件结构

```
Sources/View/Bridge/
├── NativeEditorContext.swift        # 核心状态 + 格式入口 + XML 加载/导出（~600行）
├── EditorEnums.swift                # TextFormat, SpecialElement 等枚举（~160行）
├── EditorContentManager.swift       # 内容管理、录音模板、内容保护（~300行）
└── EditorFormatDetector.swift       # 格式检测逻辑（~300行）
```

| 文件 | 职责 |
|------|------|
| `NativeEditorContext.swift` | 核心 @Published 属性、格式应用入口、XML 加载/导出、缩放 |
| `EditorEnums.swift` | `TextFormat`, `SpecialElement`, `IndentOperation`, `EditorType` 枚举定义 |
| `EditorContentManager.swift` | 内容管理方法、录音模板、内容保护逻辑 |
| `EditorFormatDetector.swift` | 格式检测、当前格式状态判断 |

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 拆分后编译错误 | 每个 Task 完成后立即编译验证 |
| 循环依赖 | API 类单向依赖 APIClient，不互相引用 |
| 运行时行为变化 | Facade 转发确保行为一致，逐步迁移 |
| 编辑器状态同步问题 | 拆分后保持同一个 NativeEditorContext 实例，只是代码组织变化 |
