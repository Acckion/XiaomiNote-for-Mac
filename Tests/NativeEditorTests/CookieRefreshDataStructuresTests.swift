import XCTest
@testable import MiNoteLibrary

/// Cookie 刷新数据结构测试
/// 验证 RefreshType、RefreshResult、CooldownState 和 CookieRefreshError 的基本功能
final class CookieRefreshDataStructuresTests: XCTestCase {
    
    // MARK: - RefreshType 测试
    
    func testRefreshTypeEnumValues() {
        // 验证三种刷新类型都能正确创建
        let reactive: RefreshType = .reactive
        let manual: RefreshType = .manual
        let automatic: RefreshType = .automatic
        
        XCTAssertNotNil(reactive)
        XCTAssertNotNil(manual)
        XCTAssertNotNil(automatic)
    }
    
    // MARK: - RefreshResult 测试
    
    func testRefreshResultSuccess() {
        // 测试成功的刷新结果
        let result = RefreshResult.success(type: .manual, verified: true)
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.verified)
        XCTAssertNil(result.error)
    }
    
    func testRefreshResultFailure() {
        // 测试失败的刷新结果
        let error = CookieRefreshError.timeout
        let result = RefreshResult.failure(type: .automatic, error: error)
        
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.verified)
        XCTAssertNotNil(result.error)
    }
    
    // MARK: - CooldownState 测试
    
    func testCooldownStateNotInCooldown() {
        // 测试不在冷却期的状态
        let state = CooldownState(lastRefreshTime: nil, cooldownPeriod: 60.0)
        
        XCTAssertFalse(state.isInCooldown)
        XCTAssertEqual(state.remainingTime, 0)
    }

    
    func testCooldownStateInCooldown() {
        // 测试在冷却期内的状态
        let now = Date()
        let state = CooldownState(lastRefreshTime: now, cooldownPeriod: 60.0)
        
        XCTAssertTrue(state.isInCooldown)
        XCTAssertGreaterThan(state.remainingTime, 0)
        XCTAssertLessThanOrEqual(state.remainingTime, 60.0)
    }
    
    func testCooldownStateExpired() {
        // 测试冷却期已过期的状态
        let pastTime = Date(timeIntervalSinceNow: -120) // 2分钟前
        let state = CooldownState(lastRefreshTime: pastTime, cooldownPeriod: 60.0)
        
        XCTAssertFalse(state.isInCooldown)
        XCTAssertEqual(state.remainingTime, 0)
    }
    
    func testCooldownStateRemainingTimeCalculation() {
        // 测试剩余时间计算的准确性
        let recentTime = Date(timeIntervalSinceNow: -30) // 30秒前
        let state = CooldownState(lastRefreshTime: recentTime, cooldownPeriod: 60.0)
        
        XCTAssertTrue(state.isInCooldown)
        // 剩余时间应该接近 30 秒（允许小误差）
        XCTAssertGreaterThan(state.remainingTime, 29.0)
        XCTAssertLessThan(state.remainingTime, 31.0)
    }
    
    // MARK: - CookieRefreshError 测试
    
    func testCookieRefreshErrorDescriptions() {
        // 测试所有错误类型都有描述
        let errors: [CookieRefreshError] = [
            .alreadyRefreshing,
            .timeout,
            .networkError(NSError(domain: "test", code: -1)),
            .verificationFailed,
            .maxRetriesExceeded
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
