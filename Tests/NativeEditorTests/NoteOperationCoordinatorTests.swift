import XCTest
@testable import MiNoteLibrary

/// NoteOperationCoordinator 单元测试
/// 
/// 测试笔记操作协调器的核心功能：
/// - 保存流程
/// - 活跃编辑状态管理
/// - 同步保护检查
/// - 冲突解决逻辑
final class NoteOperationCoordinatorTests: XCTestCase {
    
    // MARK: - 测试辅助
    
    /// 创建测试用笔记
    private func createTestNote(id: String = UUID().uuidString) -> Note {
        return Note(
            id: id,
            title: "测试笔记",
            content: "<p>测试内容</p>",
            folderId: "test-folder",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    override func setUp() async throws {
        try await super.setUp()
        // 重置协调器状态
        await NoteOperationCoordinator.shared.resetForTesting()
        // 清空待上传注册表
        PendingUploadRegistry.shared.clearAll()
    }
    
    override func tearDown() async throws {
        // 清理测试数据
        await NoteOperationCoordinator.shared.resetForTesting()
        PendingUploadRegistry.shared.clearAll()
        try await super.tearDown()
    }
    
    // MARK: - 活跃编辑状态测试
    
    /// 测试设置活跃编辑笔记
    func testSetActiveEditingNote() async {
        let noteId = "test-note-123"
        
        // 初始状态应该没有活跃编辑笔记
        let initialActiveNote = await NoteOperationCoordinator.shared.getActiveEditingNoteId()
        XCTAssertNil(initialActiveNote, "初始状态应该没有活跃编辑笔记")
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证活跃编辑笔记已设置
        let activeNote = await NoteOperationCoordinator.shared.getActiveEditingNoteId()
        XCTAssertEqual(activeNote, noteId, "活跃编辑笔记应该被正确设置")
    }
    
    /// 测试清除活跃编辑状态
    func testClearActiveEditingNote() async {
        let noteId = "test-note-123"
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 清除活跃编辑状态
        await NoteOperationCoordinator.shared.setActiveEditingNote(nil)
        
        // 验证活跃编辑状态已清除
        let activeNote = await NoteOperationCoordinator.shared.getActiveEditingNoteId()
        XCTAssertNil(activeNote, "活跃编辑状态应该被清除")
    }
    
    /// 测试切换活跃编辑笔记
    func testSwitchActiveEditingNote() async {
        let noteId1 = "test-note-1"
        let noteId2 = "test-note-2"
        
        // 设置第一个活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId1)
        
        // 切换到第二个笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId2)
        
        // 验证活跃编辑笔记已切换
        let activeNote = await NoteOperationCoordinator.shared.getActiveEditingNoteId()
        XCTAssertEqual(activeNote, noteId2, "活跃编辑笔记应该切换到新笔记")
        
        // 验证第一个笔记不再是活跃编辑状态
        let isNote1Editing = await NoteOperationCoordinator.shared.isNoteActivelyEditing(noteId1)
        XCTAssertFalse(isNote1Editing, "第一个笔记不应该是活跃编辑状态")
    }
    
    /// 测试检查笔记是否正在编辑
    func testIsNoteActivelyEditing() async {
        let noteId = "test-note-123"
        let otherNoteId = "other-note-456"
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证正在编辑的笔记
        let isEditing = await NoteOperationCoordinator.shared.isNoteActivelyEditing(noteId)
        XCTAssertTrue(isEditing, "设置的笔记应该是活跃编辑状态")
        
        // 验证其他笔记不是活跃编辑状态
        let isOtherEditing = await NoteOperationCoordinator.shared.isNoteActivelyEditing(otherNoteId)
        XCTAssertFalse(isOtherEditing, "其他笔记不应该是活跃编辑状态")
    }
    
    // MARK: - 同步保护测试
    
    /// 测试活跃编辑笔记的同步保护
    func testCanSyncUpdateNote_ActiveEditing() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证不能同步更新正在编辑的笔记
        let canUpdate = await NoteOperationCoordinator.shared.canSyncUpdateNote(noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertFalse(canUpdate, "正在编辑的笔记不应该被同步更新")
    }
    
    /// 测试待上传笔记的同步保护
    func testCanSyncUpdateNote_PendingUpload() async {
        let noteId = "test-note-123"
        let localTimestamp = Date()
        let cloudTimestamp = Date().addingTimeInterval(-60) // 云端时间戳早于本地
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: localTimestamp)
        
        // 验证不能同步更新待上传的笔记
        let canUpdate = await NoteOperationCoordinator.shared.canSyncUpdateNote(noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertFalse(canUpdate, "待上传的笔记不应该被同步更新")
    }
    
    /// 测试普通笔记可以同步更新
    func testCanSyncUpdateNote_NormalNote() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 不设置活跃编辑状态，不注册待上传
        
        // 验证可以同步更新普通笔记
        let canUpdate = await NoteOperationCoordinator.shared.canSyncUpdateNote(noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertTrue(canUpdate, "普通笔记应该可以被同步更新")
    }

    
    // MARK: - 冲突解决测试
    
    /// 测试正在编辑笔记的冲突解决
    func testResolveConflict_ActiveEditing() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证冲突解决结果为保留本地
        let resolution = await NoteOperationCoordinator.shared.resolveConflict(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(resolution, .keepLocal, "正在编辑的笔记应该保留本地内容")
    }
    
    /// 测试本地较新时的冲突解决
    func testResolveConflict_LocalNewer() async {
        let noteId = "test-note-123"
        let localTimestamp = Date()
        let cloudTimestamp = Date().addingTimeInterval(-60) // 云端时间戳早于本地
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: localTimestamp)
        
        // 验证冲突解决结果为保留本地
        let resolution = await NoteOperationCoordinator.shared.resolveConflict(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(resolution, .keepLocal, "本地较新时应该保留本地内容")
    }
    
    /// 测试云端较新但待上传时的冲突解决（用户优先策略）
    func testResolveConflict_CloudNewerButPending() async {
        let noteId = "test-note-123"
        let localTimestamp = Date().addingTimeInterval(-60) // 本地时间戳早于云端
        let cloudTimestamp = Date()
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: localTimestamp)
        
        // 验证冲突解决结果为保留本地（用户优先策略）
        let resolution = await NoteOperationCoordinator.shared.resolveConflict(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(resolution, .keepLocal, "云端较新但待上传时应该保留本地内容（用户优先策略）")
    }
    
    /// 测试云端较新且不在待上传列表时的冲突解决
    func testResolveConflict_CloudNewerNotPending() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 不注册待上传笔记
        
        // 验证冲突解决结果为使用云端
        let resolution = await NoteOperationCoordinator.shared.resolveConflict(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(resolution, .useCloud, "云端较新且不在待上传列表时应该使用云端内容")
    }
    
    // MARK: - 上传回调测试
    
    /// 测试上传成功回调
    func testOnUploadSuccess() async {
        let noteId = "test-note-123"
        let timestamp = Date()
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: timestamp)
        XCTAssertTrue(PendingUploadRegistry.shared.isRegistered(noteId), "笔记应该在待上传列表中")
        
        // 调用上传成功回调
        await NoteOperationCoordinator.shared.onUploadSuccess(noteId: noteId)
        
        // 验证笔记已从待上传列表中移除
        XCTAssertFalse(PendingUploadRegistry.shared.isRegistered(noteId), "上传成功后笔记应该从待上传列表中移除")
    }
    
    /// 测试上传失败回调
    func testOnUploadFailure() async {
        let noteId = "test-note-123"
        let timestamp = Date()
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: timestamp)
        XCTAssertTrue(PendingUploadRegistry.shared.isRegistered(noteId), "笔记应该在待上传列表中")
        
        // 调用上传失败回调
        let error = NSError(domain: "test", code: 500, userInfo: nil)
        await NoteOperationCoordinator.shared.onUploadFailure(noteId: noteId, error: error)
        
        // 验证笔记仍在待上传列表中
        XCTAssertTrue(PendingUploadRegistry.shared.isRegistered(noteId), "上传失败后笔记应该保留在待上传列表中")
    }
    
    // MARK: - 重置测试
    
    /// 测试重置功能
    func testResetForTesting() async {
        let noteId = "test-note-123"
        
        // 设置一些状态
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 重置
        await NoteOperationCoordinator.shared.resetForTesting()
        
        // 验证状态已重置
        let activeNote = await NoteOperationCoordinator.shared.getActiveEditingNoteId()
        XCTAssertNil(activeNote, "重置后应该没有活跃编辑笔记")
    }
    
    // MARK: - 并发安全测试
    
    /// 测试并发设置活跃编辑笔记
    func testConcurrentSetActiveEditingNote() async {
        let noteIds = (0..<10).map { "note-\($0)" }
        
        // 并发设置活跃编辑笔记
        await withTaskGroup(of: Void.self) { group in
            for noteId in noteIds {
                group.addTask {
                    await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
                }
            }
        }
        
        // 验证最终只有一个活跃编辑笔记
        let activeNote = await NoteOperationCoordinator.shared.getActiveEditingNoteId()
        XCTAssertNotNil(activeNote, "应该有一个活跃编辑笔记")
        XCTAssertTrue(noteIds.contains(activeNote!), "活跃编辑笔记应该是设置的笔记之一")
    }
    
    /// 测试并发检查同步保护
    func testConcurrentCanSyncUpdateNote() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 并发检查同步保护
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await NoteOperationCoordinator.shared.canSyncUpdateNote(noteId, cloudTimestamp: cloudTimestamp)
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // 验证所有结果都是 false（不能同步更新正在编辑的笔记）
        XCTAssertTrue(results.allSatisfy { !$0 }, "所有并发检查都应该返回 false")
    }
}
