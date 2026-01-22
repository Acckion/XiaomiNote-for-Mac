# MiNote macOS 架构规范

## 文档概述

本文档定义了 MiNote macOS 项目的架构规范和最佳实践，旨在确保代码质量、可维护性和团队协作效率。

**最后更新：** 2026-01-22

---

## 架构原则

### 1. 依赖注入优先

- **禁止创建新的单例**：所有服务通过依赖注入传递
- **使用 DIContainer**：统一管理服务依赖
- **构造函数注入**：优先使用构造函数注入依赖

### 2. 协议抽象

- **所有服务必须有协议接口**：便于测试和替换实现
- **面向接口编程**：依赖抽象而非具体实现
- **协议命名**：使用 `XxxProtocol` 或 `XxxServiceProtocol`

### 3. 单一职责

- **每个类不超过 500 行**：超过则需要拆分
- **一个类只做一件事**：明确的职责边界
- **高内聚低耦合**：相关功能聚合，减少依赖

### 4. 测试覆盖

- **新代码必须有单元测试**：测试覆盖率目标 > 70%
- **使用 Mock 服务**：隔离外部依赖
- **测试先行**：重要功能先写测试

---

## 目录结构

```
Sources/
├── Core/                   # 核心基础设施
│   ├── DependencyInjection/
│   │   ├── DIContainer.swift
│   │   └── ServiceLocator.swift
│   └── Extensions/
├── Model/                  # 数据模型
│   ├── Note.swift
│   ├── Folder.swift
│   └── UserProfile.swift
├── Service/                # 服务层
│   ├── Protocols/          # 服务协议
│   │   ├── NoteServiceProtocol.swift
│   │   ├── NoteStorageProtocol.swift
│   │   ├── SyncServiceProtocol.swift
│   │   ├── AuthenticationServiceProtocol.swift
│   │   ├── NetworkMonitorProtocol.swift
│   │   ├── ImageServiceProtocol.swift
│   │   ├── AudioServiceProtocol.swift
│   │   └── CacheServiceProtocol.swift
│   ├── Network/            # 网络服务
│   ├── Storage/            # 存储服务
│   ├── Sync/               # 同步服务
│   ├── Audio/              # 音频服务
│   └── Editor/             # 编辑器服务
├── ViewModel/              # 视图模型
│   └── NotesViewModel.swift
├── View/                   # 视图
│   ├── NativeEditor/
│   ├── Bridge/
│   └── Shared/
└── App/                    # 应用入口
    └── App.swift

Tests/
├── TestSupport/            # 测试支持
│   └── BaseTestCase.swift
└── Mocks/                  # Mock 服务
    ├── MockNoteService.swift
    ├── MockNoteStorage.swift
    ├── MockSyncService.swift
    ├── MockAuthenticationService.swift
    └── MockNetworkMonitor.swift
```

---

## 命名规范

### 协议

- **格式**：`XxxProtocol` 或 `XxxServiceProtocol`
- **示例**：`NoteServiceProtocol`, `NoteStorageProtocol`

### 实现类

- **格式**：具体的业务名称，避免使用 `Default` 或 `Impl` 后缀
- **示例**：`MiNoteService`, `SQLiteNoteStorage`

### Mock 类

- **格式**：`MockXxx`
- **示例**：`MockNoteService`, `MockNoteStorage`

### ViewModel

- **格式**：`XxxViewModel`
- **示例**：`NoteListViewModel`, `NoteEditorViewModel`

### UseCase（未来）

- **格式**：`XxxUseCase`
- **示例**：`FetchNotesUseCase`, `SyncNotesUseCase`

---

## 依赖注入模式

### 使用 DIContainer

```swift
// 注册服务
let container = DIContainer.shared
container.register(NoteServiceProtocol.self, instance: MiNoteService.shared)
container.register(NoteStorageProtocol.self, instance: DatabaseService.shared)

// 解析服务
let noteService = container.resolve(NoteServiceProtocol.self)
```

### 构造函数注入

```swift
class NoteListViewModel {
    private let noteStorage: NoteStorageProtocol
    private let syncService: SyncServiceProtocol

    init(
        noteStorage: NoteStorageProtocol,
        syncService: SyncServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.syncService = syncService
    }
}
```

---

## 协议设计原则

### 1. 接口隔离

- 协议应该小而专注
- 不要强迫实现类实现不需要的方法

### 2. 清晰的职责

- 每个协议定义一个明确的职责
- 使用注释说明协议的用途

### 3. 异步优先

- 网络和 I/O 操作使用 `async/await`
- 状态变化使用 Combine

### 示例

```swift
/// 笔记网络服务协议
///
/// 定义了与服务器交互的笔记操作接口
protocol NoteServiceProtocol {
    /// 获取所有笔记
    func fetchNotes() async throws -> [Note]

    /// 创建新笔记
    func createNote(_ note: Note) async throws -> Note
}
```

---

## 测试规范

### 测试文件组织

- 测试文件放在 `Tests/` 目录
- Mock 服务放在 `Tests/Mocks/` 目录
- 测试支持类放在 `Tests/TestSupport/` 目录

### 测试命名

- 测试类：`XxxTests`
- 测试方法：`test_方法名_场景_期望结果`

### 示例

```swift
class NoteServiceTests: BaseTestCase {
    var mockNoteService: MockNoteService!

    override func configureMockServices() {
        mockNoteService = MockNoteService()
        container.register(NoteServiceProtocol.self, instance: mockNoteService)
    }

    func test_fetchNotes_whenSuccess_returnsNotes() async throws {
        // Given
        let expectedNotes = [createTestNote()]
        mockNoteService.mockNotes = expectedNotes

        // When
        let notes = try await mockNoteService.fetchNotes()

        // Then
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(mockNoteService.fetchNotesCallCount, 1)
    }
}
```

---

## 代码审查清单

在提交代码前，请确保：

- [ ] 是否使用依赖注入？
- [ ] 是否有协议抽象？
- [ ] 是否有单元测试？
- [ ] 文件是否小于 500 行？
- [ ] 是否遵循单一职责原则？
- [ ] 是否有适当的注释和文档？
- [ ] 是否遵循命名规范？
- [ ] 是否处理了错误情况？
- [ ] 是否考虑了线程安全？
- [ ] 是否避免了循环依赖？

---

## 重构策略

### 渐进式重构

1. **新功能使用新架构**：所有新代码遵循新规范
2. **旧代码逐步迁移**：按优先级逐步重构旧代码
3. **保持向后兼容**：新旧代码共存，逐步过渡

### 重构优先级

1. **高优先级**：核心业务逻辑、频繁修改的代码
2. **中优先级**：稳定但需要改进的代码
3. **低优先级**：很少修改的代码

---

## 常见问题

### Q: 如何处理现有的单例？

A: 逐步迁移到依赖注入：
1. 为单例创建协议
2. 在 DIContainer 中注册单例
3. 新代码通过依赖注入使用
4. 逐步移除 `.shared` 调用

### Q: 测试覆盖率要求是多少？

A: 目标是 70% 以上，核心业务逻辑应达到 90% 以上。

### Q: 如何避免过度设计？

A: 遵循 YAGNI 原则（You Aren't Gonna Need It），只实现当前需要的功能。

---

## 参考资源

- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)

---

**文档维护者：** MiNote 开发团队
**版本：** 1.0
