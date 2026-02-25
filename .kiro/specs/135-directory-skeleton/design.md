# spec-135：目录骨架建立 + Target 合并 — 设计

## 1. Target 合并方案

### 1.1 当前结构

```yaml
MiNoteLibrary (framework):
  sources: Sources/ (excludes App/**)

MiNoteMac (application):
  sources: Sources/App
  dependencies: MiNoteLibrary

MiNoteLibraryTests (unit-test):
  dependencies: MiNoteLibrary
```

### 1.2 目标结构

```yaml
MiNoteMac (application):
  sources: Sources/
  # 不再排除 App，所有源码归入单一 target

MiNoteLibraryTests (unit-test):
  dependencies: MiNoteMac
  # @testable import MiNoteMac
```

### 1.3 影响范围

Sources 中 7 处删除 `import MiNoteLibrary`：
- Sources/App/AppDelegate.swift
- Sources/App/AppLaunchAssembler.swift
- Sources/App/AppStateManager.swift
- Sources/App/MenuManager.swift
- Sources/App/MenuStateManager.swift
- Sources/View/SwiftUIViews/Common/PreviewHelper.swift
- Sources/View/SwiftUIViews/Common/OperationProcessorProgressView.swift

Tests 中 6 处改为 `@testable import MiNoteMac`：
- Tests/CommandTests/CommandDispatcherTests.swift
- Tests/CoordinatorTests/AssemblerSmokeTests.swift
- Tests/ImportTests/ImportContentConverterTests.swift
- Tests/NativeEditorTests/ParagraphStyleConsistencyTests.swift
- Tests/NativeEditorTests/ParagraphStylePreservationTests.swift
- Tests/SyncTests/OperationQueueTests.swift
- Tests/SyncTests/OperationFailurePolicyTests.swift

现有 `public` 访问控制保留不动（合并后多余但不报错，后续按需清理）。

## 2. App 三层目录迁移

```
Sources/App/
├── Bootstrap/          # 启动相关
│   ├── AppDelegate.swift
│   └── AppLaunchAssembler.swift
├── Composition/        # 组合根（装配器）
│   ├── AppCoordinatorAssembler.swift
│   ├── NotesAssembler.swift
│   ├── SyncAssembler.swift
│   ├── AuthAssembler.swift
│   ├── EditorAssembler.swift
│   └── AudioAssembler.swift
├── Runtime/            # 运行时状态
│   └── AppStateManager.swift
├── App.swift           # SwiftUI 入口（保留原位）
├── Assets.xcassets     # 资源（保留原位）
├── MenuManager.swift   # 菜单相关（保留原位）
├── MenuManager+EditMenu.swift
├── MenuManager+FormatMenu.swift
├── MenuState.swift
├── MenuStateManager.swift
└── MenuItemTag.swift
```

迁移后 `Sources/Coordinator/` 仅保留 AppCoordinator.swift。

## 3. Shared 两层目录（建壳）

```
Sources/Shared/
├── Kernel/
│   └── README.md       # 标注计划迁入 EventBus、LogService
├── Contracts/          # 已存在，保留
└── UICommons/
    └── README.md       # 标注计划迁入共享 UI 组件
```

## 4. Legacy 过渡目录

```
Sources/Legacy/
└── README.md           # 过渡规范说明
```

## 5. 执行顺序

1. 先合并 target（修改 project.yml + 删除 import + 修改测试 import）
2. 验证编译和测试通过
3. 再做目录迁移（此时不再有 target 边界限制）
4. 每步迁移后 xcodegen generate + 编译验证
