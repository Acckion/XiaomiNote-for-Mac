import XCTest
@testable import MiNoteLibrary

/// 测试 SilentCookieRefreshManager 的防重入保护机制
/// 
/// 验证需求 6.1, 6.2, 6.3：
/// - 6.1: 刷新操作开始时设置刷新中标志
/// - 6.2: 刷新进行中且收到新请求时拒绝新请求
/// - 6.3: 刷新操作完成时清除刷新中标志
@MainActor
final class SilentCookieRefreshManagerReentrancyTests: XCTestCase {
    
    var manager: SilentCookieRefreshManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = SilentCookieRefreshManager.shared
        
        // 重置冷却期，确保测试不受冷却期影响
        manager.resetCooldown()
    }
    
    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - 测试防重入标志的基本行为
    
    /// 测试初始状态下刷新标志为 false
    func testInitialRefreshingStateShouldBeFalse() {
        XCTAssertFalse(manager.isRefreshing, "初始状态下 isRefreshing 应该为 false")
    }
    
    /// 测试并发刷新请求被正确拒绝
    /// 
    /// 验证需求 6.2: 刷新进行中且收到新请求时拒绝新请求
    func testConcurrentRefreshRequestsShouldBeRejected() async {
        // 启动第一个刷新请求（这个请求会超时，但我们不等待它完成）
        let firstRefreshTask = Task {
            do {
                _ = try await manager.refresh(type: .manual)
            } catch {
                // 预期会超时或失败，忽略错误
            }
        }
        
        // 等待一小段时间，确保第一个刷新已经开始
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        // 验证刷新标志已设置
        XCTAssertTrue(manager.isRefreshing, "第一个刷新开始后，isRefreshing 应该为 true")
        
        // 尝试启动第二个刷新请求
        do {
            _ = try await manager.refresh(type: .manual)
            XCTFail("第二个刷新请求应该被拒绝并抛出 alreadyRefreshing 错误")
        } catch let error as CookieRefreshError {
            // 验证错误类型
            if case .alreadyRefreshing = error {
                // 测试通过
            } else {
                XCTFail("应该抛出 alreadyRefreshing 错误，但得到: \(error)")
            }
        } catch {
            XCTFail("应该抛出 CookieRefreshError.alreadyRefreshing，但得到: \(error)")
        }
        
        // 取消第一个刷新任务
        firstRefreshTask.cancel()
        
        // 等待任务完成
        _ = await firstRefreshTask.result
    }
    
    /// 测试多个并发请求都被正确拒绝
    /// 
    /// 验证需求 6.2: 同时发起多个刷新请求时，只有第一个被接受
    func testMultipleConcurrentRequestsShouldAllBeRejected() async {
        // 启动第一个刷新请求
        let firstRefreshTask = Task {
            do {
                _ = try await manager.refresh(type: .manual)
            } catch {
                // 预期会超时或失败，忽略错误
            }
        }
        
        // 等待一小段时间，确保第一个刷新已经开始
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        // 同时启动多个刷新请求
        let concurrentTasks = (1...5).map { index in
            Task {
                do {
                    _ = try await manager.refresh(type: .manual)
                    return false // 不应该成功
                } catch let error as CookieRefreshError {
                    if case .alreadyRefreshing = error {
                        return true // 正确被拒绝
                    }
                    return false
                } catch {
                    return false
                }
            }
        }
        
        // 等待所有并发任务完成
        let results = await withTaskGroup(of: Bool.self) { group in
            for task in concurrentTasks {
                group.addTask {
                    await task.value
                }
            }
            
            var allRejected = true
            for await result in group {
                if !result {
                    allRejected = false
                }
            }
            return allRejected
        }
        
        XCTAssertTrue(results, "所有并发刷新请求都应该被正确拒绝")
        
        // 取消第一个刷新任务
        firstRefreshTask.cancel()
        _ = await firstRefreshTask.result
    }
    
    // MARK: - 测试刷新完成后标志清除
    
    /// 测试刷新超时后标志被正确清除
    /// 
    /// 验证需求 6.3, 6.4: 刷新超时时清除刷新中标志
    func testRefreshingFlagShouldBeClearedAfterTimeout() async {
        // 启动一个会超时的刷新请求
        let refreshTask = Task { () -> Bool in
            do {
                _ = try await manager.refresh(type: .manual)
                return false // 刷新成功，不是我们期望的
            } catch let error as CookieRefreshError {
                if case .timeout = error {
                    return true // 正确超时
                }
                return false
            } catch {
                return false
            }
        }
        
        // 等待超时发生（30秒 + 一点缓冲时间）
        try? await Task.sleep(nanoseconds: 31_000_000_000) // 31秒
        
        let result = await refreshTask.value
        XCTAssertTrue(result, "刷新应该因超时而失败")
        
        // 验证刷新标志已被清除
        XCTAssertFalse(manager.isRefreshing, "超时后 isRefreshing 应该被清除为 false")
        
        // 验证可以启动新的刷新请求
        let canStartNewRefresh = !manager.isRefreshing
        XCTAssertTrue(canStartNewRefresh, "超时后应该能够启动新的刷新请求")
    }
    
    // MARK: - 测试不同刷新类型的防重入行为
    
    /// 测试响应式刷新也遵守防重入保护
    /// 
    /// 验证需求 6.2: 即使是响应式刷新，也不能在刷新进行中时启动
    func testReactiveRefreshShouldAlsoRespectReentrancyProtection() async {
        // 启动一个手动刷新
        let firstRefreshTask = Task {
            do {
                _ = try await manager.refresh(type: .manual)
            } catch {
                // 忽略错误
            }
        }
        
        // 等待刷新开始
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        // 尝试启动响应式刷新
        do {
            _ = try await manager.refresh(type: .reactive)
            XCTFail("响应式刷新也应该被防重入保护拒绝")
        } catch let error as CookieRefreshError {
            if case .alreadyRefreshing = error {
                // 测试通过
            } else {
                XCTFail("应该抛出 alreadyRefreshing 错误")
            }
        } catch {
            XCTFail("应该抛出 CookieRefreshError.alreadyRefreshing")
        }
        
        // 取消第一个刷新任务
        firstRefreshTask.cancel()
        _ = await firstRefreshTask.result
    }
    
    /// 测试自动刷新也遵守防重入保护
    /// 
    /// 验证需求 6.2: 自动刷新在刷新进行中时也应该被拒绝
    func testAutomaticRefreshShouldAlsoRespectReentrancyProtection() async {
        // 启动一个手动刷新
        let firstRefreshTask = Task {
            do {
                _ = try await manager.refresh(type: .manual)
            } catch {
                // 忽略错误
            }
        }
        
        // 等待刷新开始
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        // 尝试启动自动刷新
        do {
            _ = try await manager.refresh(type: .automatic)
            XCTFail("自动刷新也应该被防重入保护拒绝")
        } catch let error as CookieRefreshError {
            if case .alreadyRefreshing = error {
                // 测试通过
            } else {
                XCTFail("应该抛出 alreadyRefreshing 错误")
            }
        } catch {
            XCTFail("应该抛出 CookieRefreshError.alreadyRefreshing")
        }
        
        // 取消第一个刷新任务
        firstRefreshTask.cancel()
        _ = await firstRefreshTask.result
    }
    
    // MARK: - 边界条件测试
    
    /// 测试快速连续的刷新请求
    /// 
    /// 验证需求 6.2: 快速连续发起的刷新请求应该被正确处理
    func testRapidSuccessiveRefreshRequests() async {
        // 启动第一个刷新
        let firstRefreshTask = Task {
            do {
                _ = try await manager.refresh(type: .manual)
            } catch {
                // 忽略错误
            }
        }
        
        // 立即尝试启动第二个刷新（不等待）
        var rejectedCount = 0
        
        for _ in 1...10 {
            do {
                _ = try await manager.refresh(type: .manual)
            } catch let error as CookieRefreshError {
                if case .alreadyRefreshing = error {
                    rejectedCount += 1
                }
            } catch {
                // 忽略其他错误
            }
        }
        
        XCTAssertGreaterThan(rejectedCount, 0, "至少应该有一些请求被拒绝")
        
        // 取消第一个刷新任务
        firstRefreshTask.cancel()
        _ = await firstRefreshTask.result
    }
}
