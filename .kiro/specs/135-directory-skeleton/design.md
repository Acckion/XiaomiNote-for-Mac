# spec-135：目录骨架建立 — 设计

## 技术方案

### 1. App 三层目录迁移

在 `Sources/App/` 下建立三个子目录，将现有文件迁入：

```
Sources/App/
├── Bootstrap/          # 启动相关
│   ├── AppDelegate.swift
│   └── AppLaunchAssembler.swift
├── Composition/        # 组合根（装配器）
│   ├── AppCoordinatorAssembler.swift
│   ├── NotesAssembler.swift      (spec-133 产出)
│   ├── SyncAssembler.swift       (spec-133 产出)
│   ├── AuthAssembler.swift       (spec-133 产出)
│   ├── EditorAssembler.swift     (spec-133 产出)
│   └── AudioAssembler.swift      (spec-133 产出)
├── Runtime/            # 运行时状态
│   └── AppStateManager.swift
├── App.swift           # SwiftUI 入口（保留原位）
├── Assets.xcassets     # 资源（保留原位）
├── MenuManager.swift   # 菜单相关（保留原位，后续 spec 处理）
├── MenuManager+EditMenu.swift
├── MenuManager+FormatMenu.swift
├── MenuState.swift
├── MenuStateManager.swift
└── MenuItemTag.swift
```

迁移步骤：
1. `git mv Sources/App/AppDelegate.swift Sources/App/Bootstrap/`
2. `git mv Sources/App/AppLaunchAssembler.swift Sources/App/Bootstrap/`
3. `git mv Sources/App/AppStateManager.swift Sources/App/Runtime/`
4. spec-133 产出的各域 Assembler 从 `Sources/Coordinator/` 迁入 `Sources/App/Composition/`
5. `git mv Sources/Coordinator/AppCoordinatorAssembler.swift Sources/App/Composition/`

### 2. Shared 两层目录（建壳）

```
Sources/Shared/
├── Kernel/
│   └── README.md       # 标注计划迁入 EventBus、LogService
├── Contracts/          # 已存在，保留
└── UICommons/
    └── README.md       # 标注计划迁入共享 UI 组件
```

`Sources/Shared/Contracts/` 已存在，无需新建。Kernel 和 UICommons 只建壳放 README，实际迁移在后续 spec 中执行。

### 3. Legacy 过渡目录

```
Sources/Legacy/
└── README.md           # 过渡规范说明
```

README 内容包含：
- 目录用途：仅接收临时兼容代码
- 文件规范：每个文件头部必须标注 `// Legacy: spec-XXX, 移除日期: YYYY-MM-DD`
- 审计频率：每个 spec 完成时检查是否有可清理的 Legacy 文件

### 4. XcodeGen 与编译验证

每次文件迁移后：
1. 执行 `xcodegen generate` 重新生成项目文件
2. 执行 `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -30` 验证编译通过
3. 如果编译失败，修复 import 路径后重试

### 5. project.yml 更新

XcodeGen 的 `project.yml` 使用 `Sources/` 作为源码根目录，新建子目录会被自动包含，无需手动修改 project.yml。但需确认 `sources` 配置的 glob 模式能覆盖新目录。

## 影响范围

- 迁移：`Sources/App/AppDelegate.swift` → `Sources/App/Bootstrap/`
- 迁移：`Sources/App/AppLaunchAssembler.swift` → `Sources/App/Bootstrap/`
- 迁移：`Sources/App/AppStateManager.swift` → `Sources/App/Runtime/`
- 迁移：`Sources/Coordinator/AppCoordinatorAssembler.swift` → `Sources/App/Composition/`
- 迁移：spec-133 产出的各域 Assembler → `Sources/App/Composition/`
- 新增：`Sources/Shared/Kernel/README.md`
- 新增：`Sources/Shared/UICommons/README.md`
- 新增：`Sources/Legacy/README.md`
- 更新：`AGENTS.md` 项目结构描述
