import XCTest
@testable import MiNoteLibrary

/// PendingUploadRegistry 单元测试
/// 
/// 测试待上传注册表的核心功能：
/// - 注册/注销操作
/// - 查询功能
/// - 线程安全
final class PendingUploadRegistryTests: XCTestCase {
    
    var registry: PendingUploadRegistry!
    
    override func setUp() {
        super.setUp()
        registry = PendingUploadRegistry.shared
        registry.clearAll()
    }
    
    override func tearDown() {
        registry.clearAll()
        super.tearDown()
    }
    
    // MARK: - 注册测试
    
    /// 测试注册单个笔记
    func testRegisterSingleNote() {
        // Given
        let noteId = "test-note-1"
        let timestamp = Date()
        
        // When
        registry.register(noteId: noteId, timestamp: timestamp)
        
        // Then
        XCTAssertTrue(registry.isRegistered(noteId))
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.getAllPendingNoteIds(), [noteId])
    }
    
    /// 测试注册多个笔记
    func testRegisterMultipleNotes() {
        // Given
        let noteIds = ["note-1", "note-2", "note-3"]
        let timestamp = Date()
        
        // When
        for noteId in noteIds {
            registry.register(noteId: noteId, timestamp: timestamp)
        }
        
        // Then
        XCTAssertEqual(registry.count, 3)
        for noteId in noteIds {
            XCTAssertTrue(registry.isRegistered(noteId))
        }
    }
    
    /// 测试重复注册同一笔记（应更新时间戳）
    func testRegisterSameNoteTwice() {
        // Given
        let noteId = "test-note-1"
        let timestamp1 = Date()
        let timestamp2 = Date().addingTimeInterval(10)
        
        // When
        registry.register(noteId: noteId, timestamp: timestamp1)
        registry.register(noteId: noteId, timestamp: timestamp2)
        
        // Then
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.getLocalSaveTimestamp(noteId), timestamp2)
    }
    
    // MARK: - 注销测试
    
    /// 测试注销已注册的笔记
    func testUnregisterExistingNote() {
        // Given
        let noteId = "test-note-1"
        registry.register(noteId: noteId, timestamp: Date())
        
        // When
        registry.unregister(noteId: noteId)
        
        // Then
        XCTAssertFalse(registry.isRegistered(noteId))
        XCTAssertEqual(registry.count, 0)
    }
    
    /// 测试注销未注册的笔记（应无副作用）
    func testUnregisterNonExistingNote() {
        // Given
        let noteId = "non-existing-note"
        
        // When
        registry.unregister(noteId: noteId)
        
        // Then
        XCTAssertFalse(registry.isRegistered(noteId))
        XCTAssertEqual(registry.count, 0)
    }
    
    // MARK: - 查询测试
    
    /// 测试获取本地保存时间戳
    func testGetLocalSaveTimestamp() {
        // Given
        let noteId = "test-note-1"
        let timestamp = Date()
        registry.register(noteId: noteId, timestamp: timestamp)
        
        // When
        let retrievedTimestamp = registry.getLocalSaveTimestamp(noteId)
        
        // Then
        XCTAssertNotNil(retrievedTimestamp)
        XCTAssertEqual(retrievedTimestamp!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }
    
    /// 测试获取不存在笔记的时间戳
    func testGetLocalSaveTimestampForNonExistingNote() {
        // Given
        let noteId = "non-existing-note"
        
        // When
        let timestamp = registry.getLocalSaveTimestamp(noteId)
        
        // Then
        XCTAssertNil(timestamp)
    }
    
    /// 测试获取所有待上传笔记 ID
    func testGetAllPendingNoteIds() {
        // Given
        let noteIds = ["note-1", "note-2", "note-3"]
        for noteId in noteIds {
            registry.register(noteId: noteId, timestamp: Date())
        }
        
        // When
        let allIds = registry.getAllPendingNoteIds()
        
        // Then
        XCTAssertEqual(Set(allIds), Set(noteIds))
    }
    
    /// 测试获取所有待上传条目
    func testGetAllEntries() {
        // Given
        let noteId1 = "note-1"
        let noteId2 = "note-2"
        let timestamp1 = Date()
        let timestamp2 = Date().addingTimeInterval(5)
        
        registry.register(noteId: noteId1, timestamp: timestamp1)
        registry.register(noteId: noteId2, timestamp: timestamp2)
        
        // When
        let entries = registry.getAllEntries()
        
        // Then
        XCTAssertEqual(entries.count, 2)
        
        let entry1 = entries.first { $0.noteId == noteId1 }
        let entry2 = entries.first { $0.noteId == noteId2 }
        
        XCTAssertNotNil(entry1)
        XCTAssertNotNil(entry2)
        XCTAssertEqual(entry1!.localSaveTimestamp.timeIntervalSince1970, timestamp1.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry2!.localSaveTimestamp.timeIntervalSince1970, timestamp2.timeIntervalSince1970, accuracy: 0.001)
    }
    
    // MARK: - 清空测试
    
    /// 测试清空所有条目
    func testClearAll() {
        // Given
        for i in 1...5 {
            registry.register(noteId: "note-\(i)", timestamp: Date())
        }
        XCTAssertEqual(registry.count, 5)
        
        // When
        registry.clearAll()
        
        // Then
        XCTAssertEqual(registry.count, 0)
        XCTAssertTrue(registry.getAllPendingNoteIds().isEmpty)
    }
    
    // MARK: - 线程安全测试
    
    /// 测试并发注册
    func testConcurrentRegistration() {
        // Given
        let expectation = XCTestExpectation(description: "并发注册完成")
        let iterations = 100
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        // When
        for i in 0..<iterations {
            group.enter()
            queue.async {
                self.registry.register(noteId: "note-\(i)", timestamp: Date())
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Then
            XCTAssertEqual(self.registry.count, iterations)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    /// 测试并发注册和注销
    func testConcurrentRegisterAndUnregister() {
        // Given
        let expectation = XCTestExpectation(description: "并发操作完成")
        let iterations = 50
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        // 先注册一些笔记
        for i in 0..<iterations {
            registry.register(noteId: "note-\(i)", timestamp: Date())
        }
        
        // When: 并发注册新笔记和注销旧笔记
        for i in 0..<iterations {
            group.enter()
            queue.async {
                // 注销旧笔记
                self.registry.unregister(noteId: "note-\(i)")
                group.leave()
            }
            
            group.enter()
            queue.async {
                // 注册新笔记
                self.registry.register(noteId: "new-note-\(i)", timestamp: Date())
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Then: 应该只有新笔记
            XCTAssertEqual(self.registry.count, iterations)
            for i in 0..<iterations {
                XCTAssertFalse(self.registry.isRegistered("note-\(i)"))
                XCTAssertTrue(self.registry.isRegistered("new-note-\(i)"))
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
}
