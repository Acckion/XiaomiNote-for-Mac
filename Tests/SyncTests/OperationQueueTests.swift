//
//  OperationQueueTests.swift
//  MiNoteLibraryTests
//
//  同步队列关键路径回归测试
//  验证 nextRetryAt 门控、retryCount 递增、操作状态过滤
//

import XCTest
@testable import MiNoteLibrary

final class OperationQueueTests: XCTestCase {

    // MARK: - NoteOperation 值类型逻辑测试

    func testPendingOperationCanProcess() {
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .pending
        )

        XCTAssertTrue(op.canProcess)
    }

    func testCompletedOperationCannotProcess() {
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .completed
        )

        XCTAssertFalse(op.canProcess)
    }

    func testFailedOperationCanProcess() {
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .failed
        )

        XCTAssertTrue(op.canProcess)
    }

    // MARK: - isReadyForRetry 门控测试

    func testFailedOperationWithoutNextRetryAt_isReady() {
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .failed,
            nextRetryAt: nil
        )

        XCTAssertTrue(op.isReadyForRetry)
    }

    func testFailedOperationWithPastNextRetryAt_isReady() {
        let pastDate = Date().addingTimeInterval(-60)
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .failed,
            nextRetryAt: pastDate
        )

        XCTAssertTrue(op.isReadyForRetry)
    }

    func testFailedOperationWithFutureNextRetryAt_isNotReady() {
        let futureDate = Date().addingTimeInterval(3600)
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .failed,
            nextRetryAt: futureDate
        )

        XCTAssertFalse(op.isReadyForRetry)
    }

    func testPendingOperationIsNotReadyForRetry() {
        let op = NoteOperation(
            type: .noteCreate,
            noteId: "test-note-1",
            data: NoteCreateData().encoded(),
            status: .pending
        )

        // pending 状态不算"需要重试"
        XCTAssertFalse(op.isReadyForRetry)
    }

    // MARK: - UnifiedOperationQueue 集成测试

    /// 构造有效的操作数据（数据库 data 列 NOT NULL，不能传空 Data）
    private func makeTestData() -> Data {
        NoteCreateData().encoded()
    }

    func testGetPendingOperations_nextRetryAtGate() throws {
        let queue = UnifiedOperationQueue(databaseService: DatabaseService.shared)
        try queue.clearAll()

        let pendingOp = NoteOperation(
            id: "test-pending-\(UUID().uuidString)",
            type: .noteCreate,
            noteId: "test-note-gate",
            data: makeTestData(),
            status: .pending
        )
        try queue.enqueue(pendingOp)

        let pending = queue.getPendingOperations()
        XCTAssertTrue(
            pending.contains { $0.id == pendingOp.id },
            "pending 操作应出现在 getPendingOperations 结果中"
        )

        try queue.clearAll()
    }

    func testGetPendingOperations_futureRetrySkipped() throws {
        let queue = UnifiedOperationQueue(databaseService: DatabaseService.shared)
        try queue.clearAll()

        let opId = "test-future-\(UUID().uuidString)"
        let op = NoteOperation(
            id: opId,
            type: .noteCreate,
            noteId: "test-note-future",
            data: makeTestData(),
            status: .pending
        )
        try queue.enqueue(op)

        // 标记失败并设置未来重试时间
        try queue.markFailed(opId, errorMessage: "test error", errorType: .network)
        try queue.scheduleRetry(opId, delay: 3600)

        let pending = queue.getPendingOperations()
        XCTAssertFalse(
            pending.contains { $0.id == opId },
            "未到重试时间的 failed 操作不应出现在 getPendingOperations 结果中"
        )

        try queue.clearAll()
    }

    func testMarkFailed_retryCountIncrements() throws {
        let queue = UnifiedOperationQueue(databaseService: DatabaseService.shared)
        try queue.clearAll()

        let opId = "test-retry-\(UUID().uuidString)"
        let op = NoteOperation(
            id: opId,
            type: .noteCreate,
            noteId: "test-note-retry",
            data: makeTestData(),
            status: .pending,
            retryCount: 0
        )
        try queue.enqueue(op)

        // 第一次标记失败
        try queue.markFailed(opId, errorMessage: "error 1", errorType: .network)

        let afterFirst = queue.getPendingOperations().first { $0.id == opId }
        XCTAssertEqual(afterFirst?.retryCount, 1, "第一次 markFailed 后 retryCount 应为 1")

        // 第二次标记失败
        try queue.markFailed(opId, errorMessage: "error 2", errorType: .network)

        let afterSecond = queue.getPendingOperations().first { $0.id == opId }
        XCTAssertEqual(afterSecond?.retryCount, 2, "第二次 markFailed 后 retryCount 应为 2")

        try queue.clearAll()
    }
}
