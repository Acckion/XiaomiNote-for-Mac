import XCTest
@testable import MiNoteLibrary

/// IdMappingRegistry 单元测试
///
/// 测试 ID 映射注册表的核心功能：
/// - 临时 ID 检测
/// - ID 解析
/// - 映射注册和查询
/// - 统计信息
///
/// 任务: 12.4
final class IdMappingRegistryTests: XCTestCase {
    
    // MARK: - 临时 ID 检测测试
    
    /// 测试临时 ID 检测
    func testIsTemporaryId() {
        let registry = IdMappingRegistry.shared
        
        // 临时 ID 应该返回 true
        XCTAssertTrue(registry.isTemporaryId("local_123"))
        XCTAssertTrue(registry.isTemporaryId("local_abc-def-ghi"))
        XCTAssertTrue(registry.isTemporaryId("local_"))
        XCTAssertTrue(registry.isTemporaryId("local_550e8400-e29b-41d4-a716-446655440000"))
        
        // 正式 ID 应该返回 false
        XCTAssertFalse(registry.isTemporaryId("123"))
        XCTAssertFalse(registry.isTemporaryId("abc-def-ghi"))
        XCTAssertFalse(registry.isTemporaryId(""))
        XCTAssertFalse(registry.isTemporaryId("LOCAL_123"))  // 大小写敏感
        XCTAssertFalse(registry.isTemporaryId("local123"))  // 缺少下划线
        XCTAssertFalse(registry.isTemporaryId("_local_123"))  // 前缀不对
    }
    
    // MARK: - ID 解析测试
    
    /// 测试正式 ID 解析（无映射）
    func testResolveRegularId() {
        let registry = IdMappingRegistry.shared
        let regularId = "regular-id-123"
        
        // 正式 ID 应该直接返回
        let resolved = registry.resolveId(regularId)
        XCTAssertEqual(resolved, regularId)
    }
    
    /// 测试临时 ID 解析（无映射）
    func testResolveTemporaryIdWithoutMapping() {
        let registry = IdMappingRegistry.shared
        let temporaryId = "local_unmapped-id"
        
        // 没有映射的临时 ID 应该返回原 ID
        let resolved = registry.resolveId(temporaryId)
        XCTAssertEqual(resolved, temporaryId)
    }
    
    /// 测试批量 ID 解析
    func testResolveIds() {
        let registry = IdMappingRegistry.shared
        let ids = ["regular-1", "regular-2", "local_unmapped"]
        
        let resolved = registry.resolveIds(ids)
        
        // 正式 ID 应该保持不变
        XCTAssertEqual(resolved[0], "regular-1")
        XCTAssertEqual(resolved[1], "regular-2")
        // 没有映射的临时 ID 应该保持不变
        XCTAssertEqual(resolved[2], "local_unmapped")
    }
    
    // MARK: - 映射查询测试
    
    /// 测试映射存在性检查
    func testHasMapping() {
        let registry = IdMappingRegistry.shared
        
        // 未注册的 ID 应该返回 false
        let hasMapping = registry.hasMapping(for: "local_nonexistent")
        XCTAssertFalse(hasMapping)
    }
    
    /// 测试获取映射记录
    func testGetMapping() {
        let registry = IdMappingRegistry.shared
        
        // 未注册的 ID 应该返回 nil
        let mapping = registry.getMapping(for: "local_nonexistent")
        XCTAssertNil(mapping)
    }
    
    /// 测试获取正式 ID
    func testGetServerId() {
        let registry = IdMappingRegistry.shared
        
        // 未注册的 ID 应该返回 nil
        let serverId = registry.getServerId(for: "local_nonexistent")
        XCTAssertNil(serverId)
    }
    
    // MARK: - 统计信息测试
    
    /// 测试获取统计信息
    func testGetStatistics() {
        let registry = IdMappingRegistry.shared
        
        let stats = registry.getStatistics()
        
        // 验证统计信息包含所有必要的键
        XCTAssertNotNil(stats["total"])
        XCTAssertNotNil(stats["completed"])
        XCTAssertNotNil(stats["incomplete"])
        XCTAssertNotNil(stats["notes"])
        XCTAssertNotNil(stats["folders"])
        
        // 验证数值的一致性
        XCTAssertEqual(stats["total"], stats["completed"]! + stats["incomplete"]!)
    }
    
    /// 测试获取映射数量
    func testGetMappingCount() {
        let registry = IdMappingRegistry.shared
        
        let count = registry.getMappingCount()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    /// 测试获取未完成映射数量
    func testGetIncompleteMappingCount() {
        let registry = IdMappingRegistry.shared
        
        let incompleteCount = registry.getIncompleteMappingCount()
        let totalCount = registry.getMappingCount()
        
        // 未完成数量应该小于等于总数量
        XCTAssertLessThanOrEqual(incompleteCount, totalCount)
    }
    
    // MARK: - 映射列表测试
    
    /// 测试获取所有映射
    func testGetAllMappings() {
        let registry = IdMappingRegistry.shared
        
        let mappings = registry.getAllMappings()
        let count = registry.getMappingCount()
        
        // 映射数组长度应该等于映射数量
        XCTAssertEqual(mappings.count, count)
    }
    
    /// 测试获取未完成映射
    func testGetIncompleteMappings() {
        let registry = IdMappingRegistry.shared
        
        let incompleteMappings = registry.getIncompleteMappings()
        let incompleteCount = registry.getIncompleteMappingCount()
        
        // 未完成映射数组长度应该等于未完成映射数量
        XCTAssertEqual(incompleteMappings.count, incompleteCount)
        
        // 所有返回的映射都应该是未完成的
        for mapping in incompleteMappings {
            XCTAssertFalse(mapping.completed)
        }
    }
    
    /// 测试获取待处理映射
    func testGetPendingMappings() {
        let registry = IdMappingRegistry.shared
        
        let pendingMappings = registry.getPendingMappings()
        
        // 待处理映射应该都是未完成的
        for mapping in pendingMappings {
            XCTAssertFalse(mapping.completed)
        }
    }
    
    // MARK: - 通知名称测试
    
    /// 测试通知名称定义
    func testNotificationName() {
        let notificationName = IdMappingRegistry.idMappingCompletedNotification
        
        // 验证通知名称不为空
        XCTAssertFalse(notificationName.rawValue.isEmpty)
        XCTAssertTrue(notificationName.rawValue.contains("IdMappingRegistry"))
    }
    
    // MARK: - 重新加载测试
    
    /// 测试重新加载功能
    func testReload() {
        let registry = IdMappingRegistry.shared
        
        // 记录当前数量
        let countBefore = registry.getMappingCount()
        
        // 重新加载
        registry.reload()
        
        // 重新加载后数量应该保持一致（假设数据库没有变化）
        let countAfter = registry.getMappingCount()
        XCTAssertEqual(countBefore, countAfter)
    }
}

// MARK: - IdMapping 结构体测试

/// IdMapping 结构体测试
final class IdMappingTests: XCTestCase {
    
    /// 测试 IdMapping 初始化
    func testIdMappingInit() {
        let mapping = IdMapping(
            localId: "local_test-123",
            serverId: "server-456",
            entityType: "note",
            createdAt: Date(),
            completed: false
        )
        
        XCTAssertEqual(mapping.localId, "local_test-123")
        XCTAssertEqual(mapping.serverId, "server-456")
        XCTAssertEqual(mapping.entityType, "note")
        XCTAssertFalse(mapping.completed)
    }
    
    /// 测试 IdMapping 实体类型
    func testIdMappingEntityTypes() {
        // 笔记类型
        let noteMapping = IdMapping(
            localId: "local_note",
            serverId: "server_note",
            entityType: "note",
            createdAt: Date(),
            completed: false
        )
        XCTAssertEqual(noteMapping.entityType, "note")
        
        // 文件夹类型
        let folderMapping = IdMapping(
            localId: "local_folder",
            serverId: "server_folder",
            entityType: "folder",
            createdAt: Date(),
            completed: false
        )
        XCTAssertEqual(folderMapping.entityType, "folder")
    }
    
    /// 测试 IdMapping 完成状态
    func testIdMappingCompletedState() {
        var mapping = IdMapping(
            localId: "local_test",
            serverId: "server_test",
            entityType: "note",
            createdAt: Date(),
            completed: false
        )
        
        // 初始状态未完成
        XCTAssertFalse(mapping.completed)
        
        // 修改为已完成
        mapping.completed = true
        XCTAssertTrue(mapping.completed)
    }
}
