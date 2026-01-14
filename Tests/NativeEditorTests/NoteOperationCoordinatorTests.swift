import XCTest
@testable import MiNoteLibrary

/// NoteOperationCoordinator 单元测试
/// 
/// 测试笔记操作协调器的核心功能：
/// - 保存流程
/// - 活跃编辑状态管理
/// - 同步保护检查
/// - 冲突解决逻辑
/// - 离线创建笔记
/// - 临时 ID 处理
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
    }
    
    override func tearDown() async throws {
        // 清理测试数据
        await NoteOperationCoordinator.shared.resetForTesting()
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
    
    /// 测试普通笔记可以同步更新
    func testCanSyncUpdateNote_NormalNote() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 不设置活跃编辑状态
        
        // 验证可以同步更新普通笔记
        let canUpdate = await NoteOperationCoordinator.shared.canSyncUpdateNote(noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertTrue(canUpdate, "普通笔记应该可以被同步更新")
    }
    
    /// 测试临时 ID 笔记的同步保护
    func testCanSyncUpdateNote_TemporaryId() async {
        let temporaryId = NoteOperation.generateTemporaryId()
        let cloudTimestamp = Date()
        
        // 验证临时 ID 笔记不能被同步更新
        let canUpdate = await NoteOperationCoordinator.shared.canSyncUpdateNote(temporaryId, cloudTimestamp: cloudTimestamp)
        XCTAssertFalse(canUpdate, "临时 ID 笔记不应该被同步更新")
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
    
    /// 测试临时 ID 笔记的冲突解决
    func testResolveConflict_TemporaryId() async {
        let temporaryId = NoteOperation.generateTemporaryId()
        let cloudTimestamp = Date()
        
        // 验证临时 ID 笔记的冲突解决结果为保留本地
        let resolution = await NoteOperationCoordinator.shared.resolveConflict(noteId: temporaryId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(resolution, .keepLocal, "临时 ID 笔记应该保留本地内容")
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
    
    // MARK: - 临时 ID 测试
    
    /// 测试检查临时 ID
    func testIsTemporaryNoteId() async {
        let temporaryId = NoteOperation.generateTemporaryId()
        let normalId = UUID().uuidString
        
        // 验证临时 ID 检查
        let isTemporary = await NoteOperationCoordinator.shared.isTemporaryNoteId(temporaryId)
        XCTAssertTrue(isTemporary, "临时 ID 应该被正确识别")
        
        // 验证普通 ID 检查
        let isNormalTemporary = await NoteOperationCoordinator.shared.isTemporaryNoteId(normalId)
        XCTAssertFalse(isNormalTemporary, "普通 ID 不应该被识别为临时 ID")
    }
    
    /// 测试临时 ID 格式
    func testTemporaryIdFormat() {
        let temporaryId = NoteOperation.generateTemporaryId()
        
        // 验证临时 ID 格式
        XCTAssertTrue(temporaryId.hasPrefix("local_"), "临时 ID 应该以 'local_' 开头")
        XCTAssertTrue(NoteOperation.isTemporaryId(temporaryId), "生成的临时 ID 应该被正确识别")
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
