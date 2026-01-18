import XCTest
@testable import MiNoteLibrary

/// 手动测试 SilentCookieRefreshManager 的防重入保护机制
/// 
/// 这些测试用于手动验证防重入保护的基本功能
@MainActor
final class SilentCookieRefreshManagerReentrancyManualTests: XCTestCase {
    
    var manager: SilentCookieRefreshManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = SilentCookieRefreshManager.shared
        manager.resetCooldown()
    }
    
    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }
    
    /// 测试初始状态
    func testInitialState() {
        XCTAssertFalse(manager.isRefreshing, "初始状态下 isRefreshing 应该为 false")
        print("✅ 初始状态测试通过")
    }
    
    /// 测试防重入检查的基本功能
    func testBasicReentrancyProtection() async {
        print("\n=== 测试防重入保护 ===")
        
        // 启动第一个刷新（会超时，但我们只关心防重入）
        let firstTask = Task {
            do {
                print("🔄 启动第一个刷新请求...")
                _ = try await manager.refresh(type: .manual)
            } catch {
                print("❌ 第一个刷新失败（预期）: \(error)")
            }
        }
        
        // 等待一小段时间确保第一个刷新已开始
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
        
        // 检查刷新标志
        let isRefreshingAfterStart = manager.isRefreshing
        print("📊 第一个刷新开始后，isRefreshing = \(isRefreshingAfterStart)")
        XCTAssertTrue(isRefreshingAfterStart, "第一个刷新开始后，isRefreshing 应该为 true")
        
        // 尝试第二个刷新
        do {
            print("🔄 尝试启动第二个刷新请求...")
            _ = try await manager.refresh(type: .manual)
            XCTFail("❌ 第二个刷新不应该成功")
        } catch let error as CookieRefreshError {
            if case .alreadyRefreshing = error {
                print("✅ 第二个刷新被正确拒绝: \(error)")
            } else {
                XCTFail("❌ 错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("❌ 错误类型不正确: \(error)")
        }
        
        // 取消第一个任务
        firstTask.cancel()
        _ = await firstTask.result
        
        print("=== 测试完成 ===\n")
    }
    
    /// 测试刷新标志在错误后被清除
    func testRefreshingFlagClearedAfterError() async {
        print("\n=== 测试错误后标志清除 ===")
        
        // 启动一个会超时的刷新
        let task = Task { () -> Bool in
            do {
                print("🔄 启动刷新请求（将超时）...")
                _ = try await manager.refresh(type: .manual)
                return false // 刷新成功，不是我们期望的
            } catch let error as CookieRefreshError {
                if case .timeout = error {
                    print("⏰ 刷新超时（预期）")
                    return true
                }
                return false
            } catch {
                print("❌ 其他错误: \(error)")
                return false
            }
        }
        
        // 等待超时（31秒）
        print("⏳ 等待超时（31秒）...")
        try? await Task.sleep(nanoseconds: 31_000_000_000)
        
        let result = await task.value
        print("📊 超时结果: \(result)")
        
        // 检查标志是否被清除
        let isRefreshingAfterTimeout = manager.isRefreshing
        print("📊 超时后，isRefreshing = \(isRefreshingAfterTimeout)")
        XCTAssertFalse(isRefreshingAfterTimeout, "超时后 isRefreshing 应该为 false")
        
        print("=== 测试完成 ===\n")
    }
}
