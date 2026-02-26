# spec-132：关键链路回归测试 — 设计

## 技术方案

### 1. 测试框架

使用 XCTest（项目现有测试均使用 XCTest）。所有测试文件使用 `@testable import MiNoteLibrary`。

### 2. 测试目录组织

```
Tests/
├── CommandTests/           # Command 链路测试
│   └── CommandDispatcherTests.swift
├── ImportTests/            # 导入流程测试
│   └── ImportContentConverterTests.swift
├── SyncTests/              # 同步队列测试
│   └── OperationQueueTests.swift
├── CoordinatorTests/       # 组合根冒烟测试（已有目录）
│   └── AssemblerSmokeTests.swift
```

### 3. Command 链路测试设计

由于 CommandDispatcher 依赖 AppCoordinator，而 AppCoordinator 有便利构造器 `init()`，可直接用于测试：

```swift
class CommandDispatcherTests: XCTestCase {
    @MainActor
    func testDispatchCreateNoteCommand() {
        let coordinator = AppCoordinator()
        let dispatcher = coordinator.commandDispatcher!
        // 验证 dispatch 不崩溃，Command 能正确执行
        dispatcher.dispatch(SyncCommand())
    }
}
```

重点验证：dispatch 调用链不崩溃、context 正确传递。

### 4. 导入流程测试设计

ImportContentConverter 是纯函数工具类，可直接测试：

```swift
class ImportContentConverterTests: XCTestCase {
    func testPlainTextToXML() {
        let result = ImportContentConverter.plainTextToXML("Hello\nWorld")
        XCTAssertTrue(result.contains("<text indent=\"1\">"))
        XCTAssertTrue(result.contains("Hello"))
    }
}
```

### 5. 同步队列测试设计

需要构造 UnifiedOperationQueue 实例（通过 SyncModule 或直接构造），插入测试操作，验证处理逻辑。具体实现取决于 OperationProcessor 的可测试性。

### 6. 组合根冒烟测试设计

直接调用 `AppCoordinatorAssembler.buildDependencies()`，断言所有关键属性非 nil。

## 影响范围

- 新增测试文件（不修改生产代码）
- 可能需要更新 `project.yml` 以包含新测试目录
