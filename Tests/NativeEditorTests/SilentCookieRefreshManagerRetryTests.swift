import XCTest
@testable import MiNoteLibrary

/// 测试 SilentCookieRefreshManager 的失败记录和重试逻辑
@MainActor
final class SilentCookieRefreshManagerRetryTests: XCTestCase {

    var manager: SilentCookieRefreshManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = SilentCookieRefreshManager.shared

        // 重置状态
        manager.resetCooldown()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - 失败计数测试

    /// 测试初始状态下失败计数为 0
    func testInitialFailureCountIsZero() {
        XCTAssertEqual(manager.getConsecutiveFailures(), 0, "初始失败计数应该为 0")
        XCTAssertNil(manager.getLastFailureError(), "初始状态不应该有失败错误")
        XCTAssertFalse(manager.hasReachedMaxRetries(), "初始状态不应该达到最大重试次数")
    }

    /// 测试失败计数查询方法
    func testFailureCountQueryMethods() {
        // 初始状态
        XCTAssertEqual(manager.getConsecutiveFailures(), 0)
        XCTAssertFalse(manager.hasReachedMaxRetries())

        // 注意：我们无法直接测试失败计数的增加，因为这需要实际的刷新失败
        // 这个测试主要验证查询方法的可用性
    }

    // MARK: - 冷却期重置测试

    /// 测试重置冷却期方法
    func testResetCooldown() {
        // 调用重置方法
        manager.resetCooldown()

        // 验证不在冷却期内
        XCTAssertFalse(manager.isInCooldownPeriod(), "重置后不应该在冷却期内")
        XCTAssertEqual(manager.remainingCooldownTime(), 0, "重置后剩余冷却时间应该为 0")
    }

    // MARK: - 刷新状态测试

    /// 测试初始刷新状态
    func testInitialRefreshingState() {
        XCTAssertFalse(manager.isRefreshing, "初始状态不应该在刷新中")
    }

    // MARK: - 错误类型测试

    /// 测试 CookieRefreshError 错误描述
    func testCookieRefreshErrorDescriptions() throws {
        let errors: [CookieRefreshError] = [
            .alreadyRefreshing,
            .timeout,
            .networkError(NSError(domain: "test", code: -1)),
            .verificationFailed,
            .maxRetriesExceeded,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "错误应该有描述信息")
            XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty), "错误描述不应该为空")
        }
    }

    /// 测试 alreadyRefreshing 错误
    func testAlreadyRefreshingError() {
        let error = CookieRefreshError.alreadyRefreshing
        XCTAssertEqual(error.errorDescription, "Cookie 刷新已在进行中")
    }

    /// 测试 timeout 错误
    func testTimeoutError() {
        let error = CookieRefreshError.timeout
        XCTAssertEqual(error.errorDescription, "Cookie 刷新超时")
    }

    /// 测试 verificationFailed 错误
    func testVerificationFailedError() {
        let error = CookieRefreshError.verificationFailed
        XCTAssertEqual(error.errorDescription, "Cookie 验证失败")
    }

    /// 测试 maxRetriesExceeded 错误
    func testMaxRetriesExceededError() {
        let error = CookieRefreshError.maxRetriesExceeded
        XCTAssertEqual(error.errorDescription, "超过最大重试次数")
    }

    /// 测试 networkError 错误
    func testNetworkError() throws {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "测试错误"])
        let error = CookieRefreshError.networkError(underlyingError)

        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("网络错误")), "应该包含网络错误描述")
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("测试错误")), "应该包含底层错误描述")
    }

    // MARK: - RefreshResult 测试

    /// 测试创建成功的刷新结果
    func testRefreshResultSuccess() {
        let result = RefreshResult.success(type: .manual, verified: true)

        XCTAssertTrue(result.success, "结果应该标记为成功")
        XCTAssertTrue(result.verified, "结果应该标记为已验证")
        XCTAssertEqual(result.type, .manual, "刷新类型应该是手动")
        XCTAssertNil(result.error, "成功结果不应该有错误")
    }

    /// 测试创建失败的刷新结果
    func testRefreshResultFailure() {
        let testError = CookieRefreshError.timeout
        let result = RefreshResult.failure(type: .automatic, error: testError)

        XCTAssertFalse(result.success, "结果应该标记为失败")
        XCTAssertFalse(result.verified, "失败结果不应该标记为已验证")
        XCTAssertEqual(result.type, .automatic, "刷新类型应该是自动")
        XCTAssertNotNil(result.error, "失败结果应该有错误")
    }

    // MARK: - CooldownState 测试

    /// 测试冷却期状态 - 无上次刷新时间
    func testCooldownStateWithoutLastRefresh() {
        let state = CooldownState(lastRefreshTime: nil, cooldownPeriod: 60.0)

        XCTAssertFalse(state.isInCooldown, "没有上次刷新时间时不应该在冷却期内")
        XCTAssertEqual(state.remainingTime, 0, "没有上次刷新时间时剩余时间应该为 0")
    }

    /// 测试冷却期状态 - 在冷却期内
    func testCooldownStateInCooldown() {
        let lastTime = Date().addingTimeInterval(-30) // 30 秒前
        let state = CooldownState(lastRefreshTime: lastTime, cooldownPeriod: 60.0)

        XCTAssertTrue(state.isInCooldown, "应该在冷却期内")
        XCTAssertGreaterThan(state.remainingTime, 0, "剩余时间应该大于 0")
        XCTAssertLessThanOrEqual(state.remainingTime, 30, "剩余时间应该接近 30 秒")
    }

    /// 测试冷却期状态 - 不在冷却期内
    func testCooldownStateNotInCooldown() {
        let lastTime = Date().addingTimeInterval(-70) // 70 秒前
        let state = CooldownState(lastRefreshTime: lastTime, cooldownPeriod: 60.0)

        XCTAssertFalse(state.isInCooldown, "不应该在冷却期内")
        XCTAssertEqual(state.remainingTime, 0, "剩余时间应该为 0")
    }

    /// 测试冷却期状态 - 边界情况
    func testCooldownStateBoundary() {
        let lastTime = Date().addingTimeInterval(-60) // 正好 60 秒前
        let state = CooldownState(lastRefreshTime: lastTime, cooldownPeriod: 60.0)

        // 由于时间精度问题，这里可能是边界情况
        XCTAssertEqual(state.remainingTime, 0, "正好到期时剩余时间应该为 0")
    }

    // MARK: - RefreshType 枚举测试

    /// 测试刷新类型枚举的所有值
    func testRefreshTypeValues() {
        let types: [RefreshType] = [.reactive, .manual, .automatic]

        // 验证所有类型都可以创建
        XCTAssertEqual(types.count, 3, "应该有 3 种刷新类型")
    }

    // MARK: - 集成测试准备

    /// 测试管理器单例
    func testManagerSingleton() {
        let manager1 = SilentCookieRefreshManager.shared
        let manager2 = SilentCookieRefreshManager.shared

        XCTAssertTrue(manager1 === manager2, "应该返回同一个单例实例")
    }
}
