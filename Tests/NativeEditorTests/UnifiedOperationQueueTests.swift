import XCTest
@testable import MiNoteLibrary

/// UnifiedOperationQueue 单元测试
///
/// 测试统一操作队列的核心功能：
/// - 操作入队和去重合并
/// - 状态更新
/// - 查询方法
/// - 重试调度
/// - ID 更新
///
/// 任务: 12.1
final class UnifiedOperationQueueTests: XCTestCase {

    // MARK: - 测试数据

    /// 创建测试用的操作数据
    private func createTestData(_ content: [String: Any] = [:]) -> Data {
        let defaultContent: [String: Any] = [
            "title": "测试笔记",
            "content": "测试内容",
            "folderId": "0",
        ]
        let mergedContent = content.isEmpty ? defaultContent : content
        do {
            return try JSONSerialization.data(withJSONObject: mergedContent)
        } catch {
            fatalError("JSON 序列化失败: \(error)")
        }
    }

    /// 创建测试用的 NoteOperation
    private func createTestOperation(
        id: String = UUID().uuidString,
        type: OperationType = .cloudUpload,
        noteId: String = "test-note-123",
        status: OperationStatus = .pending,
        isLocalId: Bool = false
    ) -> NoteOperation {
        NoteOperation(
            id: id,
            type: type,
            noteId: noteId,
            data: createTestData(),
            status: status,
            isLocalId: isLocalId
        )
    }

    // MARK: - NoteOperation 测试

    /// 测试临时 ID 检测
    func testIsTemporaryId() {
        // 临时 ID 应该返回 true
        XCTAssertTrue(NoteOperation.isTemporaryId("local_123"))
        XCTAssertTrue(NoteOperation.isTemporaryId("local_abc-def"))
        XCTAssertTrue(NoteOperation.isTemporaryId("local_"))

        // 正式 ID 应该返回 false
        XCTAssertFalse(NoteOperation.isTemporaryId("123"))
        XCTAssertFalse(NoteOperation.isTemporaryId("abc-def"))
        XCTAssertFalse(NoteOperation.isTemporaryId(""))
        XCTAssertFalse(NoteOperation.isTemporaryId("LOCAL_123")) // 大小写敏感
    }

    /// 测试临时 ID 生成
    func testGenerateTemporaryId() {
        let id1 = NoteOperation.generateTemporaryId()
        let id2 = NoteOperation.generateTemporaryId()

        // 应该以 local_ 开头
        XCTAssertTrue(id1.hasPrefix("local_"))
        XCTAssertTrue(id2.hasPrefix("local_"))

        // 每次生成的 ID 应该不同
        XCTAssertNotEqual(id1, id2)

        // 生成的 ID 应该被识别为临时 ID
        XCTAssertTrue(NoteOperation.isTemporaryId(id1))
        XCTAssertTrue(NoteOperation.isTemporaryId(id2))
    }

    /// 测试操作优先级计算
    func testCalculatePriority() {
        // noteCreate 应该有最高优先级
        XCTAssertEqual(NoteOperation.calculatePriority(for: .noteCreate), 4)

        // 删除操作次之
        XCTAssertEqual(NoteOperation.calculatePriority(for: .cloudDelete), 3)
        XCTAssertEqual(NoteOperation.calculatePriority(for: .folderDelete), 3)

        // 上传和重命名
        XCTAssertEqual(NoteOperation.calculatePriority(for: .cloudUpload), 2)
        XCTAssertEqual(NoteOperation.calculatePriority(for: .folderRename), 2)

        // 图片上传和文件夹创建最低
        XCTAssertEqual(NoteOperation.calculatePriority(for: .imageUpload), 1)
        XCTAssertEqual(NoteOperation.calculatePriority(for: .folderCreate), 1)
    }

    /// 测试操作状态检查
    func testCanProcess() {
        // pending 状态可以处理
        var operation = createTestOperation(status: .pending)
        XCTAssertTrue(operation.canProcess)

        // failed 状态可以处理
        operation.status = .failed
        XCTAssertTrue(operation.canProcess)

        // processing 状态不能处理
        operation.status = .processing
        XCTAssertFalse(operation.canProcess)

        // completed 状态不能处理
        operation.status = .completed
        XCTAssertFalse(operation.canProcess)

        // authFailed 状态不能处理
        operation.status = .authFailed
        XCTAssertFalse(operation.canProcess)

        // maxRetryExceeded 状态不能处理
        operation.status = .maxRetryExceeded
        XCTAssertFalse(operation.canProcess)
    }

    /// 测试重试就绪检查
    func testIsReadyForRetry() {
        var operation = createTestOperation(status: .failed)

        // 没有设置 nextRetryAt，应该立即重试
        XCTAssertTrue(operation.isReadyForRetry)

        // 设置过去的时间，应该可以重试
        operation.nextRetryAt = Date().addingTimeInterval(-10)
        XCTAssertTrue(operation.isReadyForRetry)

        // 设置未来的时间，不应该重试
        operation.nextRetryAt = Date().addingTimeInterval(10)
        XCTAssertFalse(operation.isReadyForRetry)

        // 非 failed 状态不应该重试
        operation.status = .pending
        XCTAssertFalse(operation.isReadyForRetry)
    }

    // MARK: - OperationErrorType 测试

    /// 测试错误类型可重试判断
    func testErrorTypeIsRetryable() {
        // 可重试的错误类型
        XCTAssertTrue(OperationErrorType.network.isRetryable)
        XCTAssertTrue(OperationErrorType.timeout.isRetryable)
        XCTAssertTrue(OperationErrorType.serverError.isRetryable)

        // 不可重试的错误类型
        XCTAssertFalse(OperationErrorType.authExpired.isRetryable)
        XCTAssertFalse(OperationErrorType.notFound.isRetryable)
        XCTAssertFalse(OperationErrorType.conflict.isRetryable)
        XCTAssertFalse(OperationErrorType.unknown.isRetryable)
    }

    // MARK: - 重试延迟计算测试

    /// 测试重试延迟计算（指数退避）
    func testCalculateRetryDelay() {
        let queue = UnifiedOperationQueue.shared

        // 验证指数退避序列：1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s...
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 1), 2.0, accuracy: 0.01)
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 2), 4.0, accuracy: 0.01)
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 3), 8.0, accuracy: 0.01)
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 4), 16.0, accuracy: 0.01)
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 5), 32.0, accuracy: 0.01)
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 6), 60.0, accuracy: 0.01) // 最大值
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 7), 60.0, accuracy: 0.01) // 保持最大值
        XCTAssertEqual(queue.calculateRetryDelay(retryCount: 100), 60.0, accuracy: 0.01) // 保持最大值
    }

    // MARK: - OperationType 测试

    /// 测试所有操作类型都有定义
    func testAllOperationTypes() {
        let allTypes = OperationType.allCases

        // 验证所有类型都存在
        XCTAssertTrue(allTypes.contains(.noteCreate))
        XCTAssertTrue(allTypes.contains(.cloudUpload))
        XCTAssertTrue(allTypes.contains(.cloudDelete))
        XCTAssertTrue(allTypes.contains(.imageUpload))
        XCTAssertTrue(allTypes.contains(.folderCreate))
        XCTAssertTrue(allTypes.contains(.folderRename))
        XCTAssertTrue(allTypes.contains(.folderDelete))

        // 验证总数
        XCTAssertEqual(allTypes.count, 7)
    }

    // MARK: - OperationStatus 测试

    /// 测试所有操作状态的原始值
    func testOperationStatusRawValues() {
        XCTAssertEqual(OperationStatus.pending.rawValue, "pending")
        XCTAssertEqual(OperationStatus.processing.rawValue, "processing")
        XCTAssertEqual(OperationStatus.completed.rawValue, "completed")
        XCTAssertEqual(OperationStatus.failed.rawValue, "failed")
        XCTAssertEqual(OperationStatus.authFailed.rawValue, "authFailed")
        XCTAssertEqual(OperationStatus.maxRetryExceeded.rawValue, "maxRetryExceeded")
    }

    // MARK: - NoteOperation Codable 测试

    /// 测试 NoteOperation 的编码和解码
    func testNoteOperationCodable() throws {
        let operation = NoteOperation(
            id: "test-id",
            type: .cloudUpload,
            noteId: "note-123",
            data: createTestData(),
            createdAt: Date(),
            localSaveTimestamp: Date(),
            status: .pending,
            priority: 2,
            retryCount: 1,
            nextRetryAt: Date().addingTimeInterval(60),
            lastError: "测试错误",
            errorType: .network,
            isLocalId: true
        )

        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(operation)

        // 解码
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NoteOperation.self, from: data)

        // 验证
        XCTAssertEqual(decoded.id, operation.id)
        XCTAssertEqual(decoded.type, operation.type)
        XCTAssertEqual(decoded.noteId, operation.noteId)
        XCTAssertEqual(decoded.status, operation.status)
        XCTAssertEqual(decoded.priority, operation.priority)
        XCTAssertEqual(decoded.retryCount, operation.retryCount)
        XCTAssertEqual(decoded.lastError, operation.lastError)
        XCTAssertEqual(decoded.errorType, operation.errorType)
        XCTAssertEqual(decoded.isLocalId, operation.isLocalId)
    }

    // MARK: - NoteOperation Equatable 测试

    /// 测试 NoteOperation 的相等性比较
    func testNoteOperationEquatable() {
        let operation1 = createTestOperation(id: "same-id", noteId: "note-1")
        let operation2 = createTestOperation(id: "same-id", noteId: "note-2") // 不同的 noteId
        let operation3 = createTestOperation(id: "different-id", noteId: "note-1")

        // 相同 ID 应该相等（即使其他属性不同）
        XCTAssertEqual(operation1, operation2)

        // 不同 ID 应该不相等
        XCTAssertNotEqual(operation1, operation3)
    }

    // MARK: - NoteOperation Hashable 测试

    /// 测试 NoteOperation 的哈希值
    func testNoteOperationHashable() {
        let operation1 = createTestOperation(id: "same-id", noteId: "note-1")
        let operation2 = createTestOperation(id: "same-id", noteId: "note-2")
        let operation3 = createTestOperation(id: "different-id", noteId: "note-1")

        // 相同 ID 应该有相同的哈希值
        XCTAssertEqual(operation1.hashValue, operation2.hashValue)

        // 可以放入 Set 中
        var set = Set<NoteOperation>()
        set.insert(operation1)
        set.insert(operation2) // 应该被忽略（相同 ID）
        set.insert(operation3)

        XCTAssertEqual(set.count, 2)
    }
}
