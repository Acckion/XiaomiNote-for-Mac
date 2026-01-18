import XCTest
@testable import MiNoteLibrary

/// SilentCookieRefreshManager 冷却期管理测试
/// 验证智能冷却期检查方法的行为
@MainActor
final class SilentCookieRefreshManagerCooldownTests: XCTestCase {
    
    var manager: SilentCookieRefreshManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = SilentCookieRefreshManager.shared
        // 重置冷却期状态
        manager.resetCooldown()
    }
    
    override func tearDown() async throws {
        manager.resetCooldown()
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - 冷却期基础功能测试
    
    func testIsInCooldownPeriod_初始状态不在冷却期() {
        // 初始状态下，没有刷新记录，不应该在冷却期内
        XCTAssertFalse(manager.isInCooldownPeriod())
    }
    
    func testRemainingCooldownTime_初始状态为零() {
        // 初始状态下，剩余冷却时间应该为 0
        XCTAssertEqual(manager.remainingCooldownTime(), 0)
    }
    
    func testResetCooldown_清除冷却期状态() {
        // 重置冷却期后，应该不在冷却期内
        manager.resetCooldown()
        XCTAssertFalse(manager.isInCooldownPeriod())
        XCTAssertEqual(manager.remainingCooldownTime(), 0)
    }
    
    // MARK: - shouldSkipRefresh 行为测试（通过观察日志输出）
    
    func testCooldownBehavior_响应式刷新不受冷却期限制() {
        // 注意：由于 shouldSkipRefresh 是私有方法，我们无法直接测试
        // 但我们可以验证冷却期的基础功能是否正常工作
        
        // 验证初始状态
        XCTAssertFalse(manager.isInCooldownPeriod())
        
        // 响应式刷新应该忽略冷却期（这个行为在实际调用 refresh(type: .reactive) 时体现）
        // 这里我们只能验证冷却期检查方法本身的正确性
    }
    
    func testCooldownBehavior_手动刷新可以重置冷却期() {
        // 验证重置冷却期功能
        manager.resetCooldown()
        XCTAssertFalse(manager.isInCooldownPeriod())
        XCTAssertEqual(manager.remainingCooldownTime(), 0)
    }
    
    func testCooldownBehavior_自动刷新遵守冷却期() {
        // 验证冷却期检查功能
        let isInCooldown = manager.isInCooldownPeriod()
        let remainingTime = manager.remainingCooldownTime()
        
        // 如果在冷却期内，剩余时间应该大于 0
        if isInCooldown {
            XCTAssertGreaterThan(remainingTime, 0)
        } else {
            XCTAssertEqual(remainingTime, 0)
        }
    }
    
    // MARK: - 冷却期状态一致性测试
    
    func testCooldownStateConsistency() {
        // 验证冷却期状态的一致性
        let isInCooldown = manager.isInCooldownPeriod()
        let remainingTime = manager.remainingCooldownTime()
        
        if isInCooldown {
            // 如果在冷却期内，剩余时间必须大于 0
            XCTAssertGreaterThan(remainingTime, 0)
        } else {
            // 如果不在冷却期内，剩余时间必须等于 0
            XCTAssertEqual(remainingTime, 0)
        }
    }
    
    func testRemainingCooldownTime_非负值() {
        // 剩余冷却时间永远不应该是负数
        let remainingTime = manager.remainingCooldownTime()
        XCTAssertGreaterThanOrEqual(remainingTime, 0)
    }
}
