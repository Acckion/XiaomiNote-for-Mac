# MiNote macOS 编码规范

## 文档概述

本文档定义了 MiNote macOS 项目的编码规范和最佳实践，确保代码风格一致、可读性强、易于维护。

**最后更新：** 2026-01-22

---

## Swift 代码风格

### 1. 缩进和空格

- **使用 4 个空格缩进**，不使用 Tab
- **运算符两侧加空格**：`let sum = a + b`
- **逗号后加空格**：`func foo(a: Int, b: Int)`
- **冒号后加空格**：`let dict: [String: Int]`

### 2. 行长度

- **每行不超过 120 个字符**
- 超过时适当换行，保持可读性

### 3. 命名规范

#### 类型命名（PascalCase）

```swift
class NoteListViewModel { }
struct Note { }
enum SortOption { }
protocol NoteServiceProtocol { }
```

#### 变量和函数命名（camelCase）

```swift
var noteCount: Int
func fetchNotes() async throws -> [Note]
let isAuthenticated: Bool
```

#### 常量命名

```swift
// 全局常量使用 PascalCase
let MaxRetryCount = 3

// 局部常量使用 camelCase
let maxRetryCount = 3
```

#### 布尔值命名

使用 `is`, `has`, `should`, `can` 等前缀：

```swift
var isLoading: Bool
var hasError: Bool
var shouldSync: Bool
var canEdit: Bool
```

---

## 代码组织

### 1. MARK 注释

使用 `MARK` 组织代码结构：

```swift
class NoteListViewModel {
    // MARK: - Properties

    private let noteStorage: NoteStorageProtocol
    @Published var notes: [Note] = []

    // MARK: - Initialization

    init(noteStorage: NoteStorageProtocol) {
        self.noteStorage = noteStorage
    }

    // MARK: - Public Methods

    func loadNotes() async throws {
        // Implementation
    }

    // MARK: - Private Methods

    private func sortNotes(_ notes: [Note]) -> [Note] {
        // Implementation
    }
}
```

### 2. 代码顺序

类内部代码按以下顺序组织：

1. 类型定义（嵌套类型、枚举）
2. 属性（存储属性、计算属性）
3. 初始化方法
4. 生命周期方法
5. 公开方法
6. 私有方法

### 3. 扩展

使用扩展组织协议实现：

```swift
// MARK: - NoteServiceProtocol

extension MiNoteService: NoteServiceProtocol {
    func fetchNotes() async throws -> [Note] {
        // Implementation
    }
}
```

---

## 注释规范

### 1. 文档注释

使用三斜线 `///` 为公开 API 添加文档注释：

```swift
/// 笔记网络服务协议
///
/// 定义了与服务器交互的笔记操作接口，包括：
/// - 笔记的 CRUD 操作
/// - 同步操作
/// - 批量操作
protocol NoteServiceProtocol {
    /// 获取所有笔记
    ///
    /// - Returns: 笔记数组
    /// - Throws: 网络错误或解析错误
    func fetchNotes() async throws -> [Note]
}
```

### 2. 行内注释

- 使用 `//` 添加行内注释
- 注释应该解释"为什么"而不是"是什么"
- 避免显而易见的注释

```swift
// ✅ 好的注释
// 使用 weak 避免循环引用
weak var delegate: NoteListDelegate?

// ❌ 不好的注释
// 设置 delegate 为 weak
weak var delegate: NoteListDelegate?
```

### 3. TODO 和 FIXME

```swift
// TODO: 实现离线缓存功能
// FIXME: 修复同步冲突时的崩溃问题
```

---

## 错误处理

### 1. 使用 Result 类型

对于可能失败的操作，优先使用 `async throws`：

```swift
func fetchNotes() async throws -> [Note] {
    // Implementation
}
```

### 2. 自定义错误类型

```swift
enum NoteServiceError: Error {
    case networkError(Error)
    case invalidResponse
    case notFound
    case unauthorized
}
```

### 3. 错误处理最佳实践

```swift
// ✅ 好的错误处理
do {
    let notes = try await noteService.fetchNotes()
    self.notes = notes
} catch let error as NoteServiceError {
    handleServiceError(error)
} catch {
    handleUnknownError(error)
}

// ❌ 避免空的 catch
do {
    try someOperation()
} catch {
    // 什么都不做
}
```

---

## 异步编程

### 1. 使用 async/await

优先使用 `async/await` 而不是回调：

```swift
// ✅ 使用 async/await
func loadNotes() async throws {
    let notes = try await noteService.fetchNotes()
    self.notes = notes
}

// ❌ 避免回调地狱
func loadNotes(completion: @escaping (Result<[Note], Error>) -> Void) {
    noteService.fetchNotes { result in
        // ...
    }
}
```

### 2. MainActor

UI 相关的类使用 `@MainActor`：

```swift
@MainActor
class NoteListViewModel: ObservableObject {
    @Published var notes: [Note] = []
}
```

### 3. Task 管理

```swift
class NoteListViewModel {
    private var loadTask: Task<Void, Never>?

    func loadNotes() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let notes = try await noteService.fetchNotes()
                self.notes = notes
            } catch {
                handleError(error)
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }
}
```

---

## 内存管理

### 1. 避免循环引用

使用 `weak` 或 `unowned` 打破循环引用：

```swift
// ✅ 使用 weak
syncService.isSyncing
    .sink { [weak self] isSyncing in
        self?.updateUI(isSyncing)
    }
    .store(in: &cancellables)

// ✅ 使用 capture list
Task { [weak self] in
    await self?.loadNotes()
}
```

### 2. Combine 订阅管理

```swift
class NoteListViewModel {
    private var cancellables = Set<AnyCancellable>()

    func setupBindings() {
        syncService.isSyncing
            .sink { [weak self] isSyncing in
                self?.isLoading = isSyncing
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.removeAll()
    }
}
```

---

## 可选值处理

### 1. 使用 guard 提前返回

```swift
// ✅ 使用 guard
func processNote(id: String?) {
    guard let id = id else {
        return
    }
    // 使用 id
}

// ❌ 避免深层嵌套
func processNote(id: String?) {
    if let id = id {
        // 使用 id
    }
}
```

### 2. 可选链

```swift
// ✅ 使用可选链
let title = note?.title?.uppercased()

// ❌ 避免强制解包
let title = note!.title!.uppercased()
```

### 3. nil 合并运算符

```swift
let title = note.title ?? "Untitled"
```

---

## 协议和泛型

### 1. 协议设计

```swift
// ✅ 清晰的协议定义
protocol NoteServiceProtocol {
    func fetchNotes() async throws -> [Note]
    func createNote(_ note: Note) async throws -> Note
}

// ❌ 避免过大的协议
protocol MassiveProtocol {
    // 50+ 个方法
}
```

### 2. 泛型约束

```swift
// ✅ 使用泛型约束
func save<T: Codable>(_ item: T, for key: String) throws {
    // Implementation
}

// ✅ 使用 where 子句
extension Array where Element: Equatable {
    func removeDuplicates() -> [Element] {
        // Implementation
    }
}
```

---

## SwiftUI 最佳实践

### 1. 视图拆分

保持视图小而专注：

```swift
// ✅ 拆分为小视图
struct NoteListView: View {
    var body: some View {
        List {
            ForEach(notes) { note in
                NoteRowView(note: note)
            }
        }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        // Row implementation
    }
}
```

### 2. 使用 @StateObject 和 @ObservedObject

```swift
// ✅ 在创建 ViewModel 的视图中使用 @StateObject
struct NoteListView: View {
    @StateObject private var viewModel = NoteListViewModel()
}

// ✅ 在传递 ViewModel 的视图中使用 @ObservedObject
struct NoteDetailView: View {
    @ObservedObject var viewModel: NoteDetailViewModel
}
```

---

## 测试规范

### 1. 测试命名

```swift
func test_方法名_场景_期望结果() {
    // Test implementation
}

// 示例
func test_fetchNotes_whenSuccess_returnsNotes() async throws {
    // Given
    let expectedNotes = [createTestNote()]
    mockNoteService.mockNotes = expectedNotes

    // When
    let notes = try await mockNoteService.fetchNotes()

    // Then
    XCTAssertEqual(notes.count, 1)
}
```

### 2. Given-When-Then 模式

```swift
func test_example() {
    // Given - 准备测试数据
    let input = "test"

    // When - 执行操作
    let result = processInput(input)

    // Then - 验证结果
    XCTAssertEqual(result, "expected")
}
```

---

## 性能优化

### 1. 避免不必要的计算

```swift
// ✅ 使用 lazy
lazy var expensiveProperty: String = {
    // 昂贵的计算
    return result
}()

// ✅ 缓存结果
private var cachedResult: [Note]?

func getFilteredNotes() -> [Note] {
    if let cached = cachedResult {
        return cached
    }
    let result = performExpensiveFiltering()
    cachedResult = result
    return result
}
```

### 2. 使用 @Published 谨慎

```swift
// ✅ 只对需要观察的属性使用 @Published
@Published var notes: [Note] = []

// ❌ 避免对所有属性使用 @Published
@Published private var internalCache: [String: Any] = [:]
```

---

## 安全性

### 1. 避免硬编码敏感信息

```swift
// ❌ 不要硬编码
let apiKey = "sk-1234567890abcdef"

// ✅ 从配置或环境变量读取
let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
```

### 2. 输入验证

```swift
func processUserInput(_ input: String) throws {
    guard !input.isEmpty else {
        throw ValidationError.emptyInput
    }

    guard input.count <= 1000 else {
        throw ValidationError.inputTooLong
    }

    // Process input
}
```

---

## 代码审查检查清单

提交代码前检查：

- [ ] 代码风格符合规范
- [ ] 有适当的注释和文档
- [ ] 没有硬编码的敏感信息
- [ ] 错误处理完善
- [ ] 没有内存泄漏风险
- [ ] 有单元测试覆盖
- [ ] 性能考虑合理
- [ ] 命名清晰易懂
- [ ] 没有不必要的复杂度
- [ ] 遵循 SOLID 原则

---

## 工具推荐

- **SwiftLint**：自动检查代码风格
- **SwiftFormat**：自动格式化代码
- **Instruments**：性能分析工具

---

**文档维护者：** MiNote 开发团队
**版本：** 1.0
