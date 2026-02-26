# ADR-001: 依赖方向规则

## 状态

已采纳

## 上下文

MiNoteMac 采用分层架构，各层职责明确。如果允许任意层之间互相引用，会导致循环依赖、编译耦合和测试困难。需要明确规定各层之间允许的依赖方向。

当前架构分层：

```
AppKit 控制器层 (AppDelegate, WindowController)
        |
模块工厂层 (NetworkModule, SyncModule, EditorModule, AudioModule)
        |
协调器层 (AppCoordinator)
        |
SwiftUI 视图层 (View)
        |
状态层 (State)
        |
数据层 (NoteStore, DatabaseService, SyncEngine)
        |
数据模型层 (Model)
```

## 决策

### 规则

1. Domain 层（`Sources/Model/` 与 `Sources/Features/*/Domain/`）禁止 import AppKit、SwiftUI
2. UI 层（View/）禁止直接 import Store、Network 具体实现类
3. 依赖方向为单向：上层可以依赖下层，下层不可依赖上层
4. 跨层通信通过 EventBus 或协议抽象实现

### 当前阶段适用范围

- Domain 层对应 `Sources/Model/` 与 `Sources/Features/*/Domain/`

### 豁免机制

代码中可使用 `// arch-ignore` 注释豁免单行检查。

## 后果

- 正面：各层可独立编译和测试，降低耦合度
- 代价：跨层通信需要通过 EventBus 或协议，增加间接层

## 自动化检查

- RULE-001（`scripts/check-architecture.sh`）：扫描 Domain 层中的 AppKit/SwiftUI import

## 相关 Spec

- spec-125: 架构治理与约束自动化
- spec-136: Editor/Search/Audio 纵向切片（规则已覆盖全部 Domain 目录）
