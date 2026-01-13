import XCTest
@testable import MiNoteLibrary

/// SyncProtectionFilter 单元测试
/// 
/// 测试同步保护过滤器的核心功能：
/// - 活跃编辑检查
/// - 待上传检查
/// - 时间戳比较
/// - 跳过原因获取
final class SyncProtectionFilterTests: XCTestCase {
    
    // MARK: - 测试属性
    
    private var filter: SyncProtectionFilter!
    
    // MARK: - 测试生命周期
    
    override func setUp() async throws {
        try await super.setUp()
        // 重置协调器状态
        await NoteOperationCoordinator.shared.resetForTesting()
        // 清空待上传注册表
        PendingUploadRegistry.shared.clearAll()
        // 创建过滤器
        filter = SyncProtectionFilter()
    }
    
    override func tearDown() async throws {
        // 清理测试数据
        await NoteOperationCoordinator.shared.resetForTesting()
        PendingUploadRegistry.shared.clearAll()
        filter = nil
        try await super.tearDown()
    }
    
    // MARK: - 活跃编辑检查测试
    
    /// 测试活跃编辑笔记应该被跳过
    func testShouldSkipSync_ActivelyEditing() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证应该跳过同步
        let shouldSkip = await filter.shouldSkipSync(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertTrue(shouldSkip, "活跃编辑的笔记应该被跳过同步")
    }
    
    /// 测试检查活跃编辑状态
    func testIsActivelyEditing() async {
        let noteId = "test-note-123"
        
        // 初始状态不是活跃编辑
        let initialState = await filter.isActivelyEditing(noteId: noteId)
        XCTAssertFalse(initialState, "初始状态不应该是活跃编辑")
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证是活跃编辑状态
        let afterSet = await filter.isActivelyEditing(noteId: noteId)
        XCTAssertTrue(afterSet, "设置后应该是活跃编辑状态")
    }
    
    // MARK: - 待上传检查测试
    
    /// 测试待上传笔记应该被跳过
    func testShouldSkipSync_PendingUpload() async {
        let noteId = "test-note-123"
        let localTimestamp = Date()
        let cloudTimestamp = Date().addingTimeInterval(-60) // 云端时间戳早于本地
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: localTimestamp)
        
        // 验证应该跳过同步
        let shouldSkip = await filter.shouldSkipSync(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertTrue(shouldSkip, "待上传的笔记应该被跳过同步")
    }
    
    /// 测试检查待上传状态
    func testIsPendingUpload() {
        let noteId = "test-note-123"
        
        // 初始状态不是待上传
        XCTAssertFalse(filter.isPendingUpload(noteId: noteId), "初始状态不应该是待上传")
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: Date())
        
        // 验证是待上传状态
        XCTAssertTrue(filter.isPendingUpload(noteId: noteId), "注册后应该是待上传状态")
    }
    
    /// 测试获取本地保存时间戳
    func testGetLocalSaveTimestamp() {
        let noteId = "test-note-123"
        let timestamp = Date()
        
        // 初始状态没有时间戳
        XCTAssertNil(filter.getLocalSaveTimestamp(noteId: noteId), "初始状态应该没有时间戳")
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: timestamp)
        
        // 验证时间戳
        let savedTimestamp = filter.getLocalSaveTimestamp(noteId: noteId)
        XCTAssertNotNil(savedTimestamp, "注册后应该有时间戳")
        XCTAssertEqual(savedTimestamp!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 1.0, "时间戳应该匹配")
    }
    
    // MARK: - 普通笔记测试
    
    /// 测试普通笔记不应该被跳过
    func testShouldSkipSync_NormalNote() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 不设置活跃编辑状态，不注册待上传
        
        // 验证不应该跳过同步
        let shouldSkip = await filter.shouldSkipSync(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertFalse(shouldSkip, "普通笔记不应该被跳过同步")
    }
    
    // MARK: - 跳过原因测试
    
    /// 测试获取活跃编辑跳过原因
    func testGetSkipReason_ActivelyEditing() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 设置活跃编辑笔记
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        
        // 验证跳过原因
        let reason = await filter.getSkipReason(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(reason, .activelyEditing, "跳过原因应该是活跃编辑")
    }
    
    /// 测试获取待上传跳过原因
    func testGetSkipReason_PendingUpload() async {
        let noteId = "test-note-123"
        let localTimestamp = Date().addingTimeInterval(-60) // 本地时间戳早于云端
        let cloudTimestamp = Date()
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: localTimestamp)
        
        // 验证跳过原因
        let reason = await filter.getSkipReason(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(reason, .pendingUpload, "跳过原因应该是待上传")
    }
    
    /// 测试获取本地较新跳过原因
    func testGetSkipReason_LocalNewer() async {
        let noteId = "test-note-123"
        let localTimestamp = Date()
        let cloudTimestamp = Date().addingTimeInterval(-60) // 云端时间戳早于本地
        
        // 注册待上传笔记
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: localTimestamp)
        
        // 验证跳过原因
        let reason = await filter.getSkipReason(noteId: noteId, cloudTimestamp: cloudTimestamp)
        if case .localNewer(let local, let cloud) = reason {
            XCTAssertEqual(local.timeIntervalSince1970, localTimestamp.timeIntervalSince1970, accuracy: 1.0)
            XCTAssertEqual(cloud.timeIntervalSince1970, cloudTimestamp.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("跳过原因应该是本地较新")
        }
    }
    
    /// 测试普通笔记没有跳过原因
    func testGetSkipReason_NormalNote() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 不设置活跃编辑状态，不注册待上传
        
        // 验证没有跳过原因
        let reason = await filter.getSkipReason(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertNil(reason, "普通笔记不应该有跳过原因")
    }
    
    // MARK: - 边界情况测试
    
    /// 测试时间戳相等时的处理
    func testShouldSkipSync_EqualTimestamp() async {
        let noteId = "test-note-123"
        let timestamp = Date()
        
        // 注册待上传笔记，时间戳与云端相同
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: timestamp)
        
        // 验证应该跳过同步（本地 >= 云端）
        let shouldSkip = await filter.shouldSkipSync(noteId: noteId, cloudTimestamp: timestamp)
        XCTAssertTrue(shouldSkip, "时间戳相等时应该跳过同步")
    }
    
    /// 测试活跃编辑优先于待上传检查
    func testSkipReason_ActiveEditingPriority() async {
        let noteId = "test-note-123"
        let cloudTimestamp = Date()
        
        // 同时设置活跃编辑和待上传
        await NoteOperationCoordinator.shared.setActiveEditingNote(noteId)
        PendingUploadRegistry.shared.register(noteId: noteId, timestamp: Date())
        
        // 验证跳过原因是活跃编辑（优先级更高）
        let reason = await filter.getSkipReason(noteId: noteId, cloudTimestamp: cloudTimestamp)
        XCTAssertEqual(reason, .activelyEditing, "活跃编辑应该优先于待上传检查")
    }
}
