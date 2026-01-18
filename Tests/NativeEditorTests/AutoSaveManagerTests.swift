//
//  AutoSaveManagerTests.swift
//  MiNoteMac
//
//  AutoSaveManager 单元测试
//  需求: 59.6
//

import XCTest
@testable import MiNoteMac

/// AutoSaveManager 单元测试
///
/// 测试自动保存管理器的核心功能：
/// 1. 防抖机制
/// 2. 保存调度
/// 3. 并发控制
/// 4. 取消保存
@MainActor
final class AutoSaveManagerTests: XCTestCase {
    
    // MARK: - 测试：防抖延迟生效
    
    /// 测试防抖延迟是否正确生效
    ///
    /// **验收标准**：防抖延迟 2 秒生效
    ///
    /// _Requirements: FR-6.1_
    func testDebounceDelay() async throws {
        // Given: 创建一个保存计数器
        var saveCount = 0
        let expectation = XCTestExpectation(description: "保存应该在延迟后执行")
        
        let manager = AutoSaveManager(debounceDelay: 0.5) {
            saveCount += 1
            expectation.fulfill()
        }
        
        // When: 调度保存
        manager.scheduleAutoSave()
        
        // Then: 立即检查，保存不应该执行
        XCTAssertEqual(saveCount, 0, "保存不应该立即执行")
        
        // 等待延迟时间
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // 保存应该已经执行
        XCTAssertEqual(saveCount, 1, "保存应该在延迟后执行")
    }
    
    // MARK: - 测试：防抖重置
    
    /// 测试连续调度是否会重置防抖计时器
    ///
    /// **验收标准**：多次调度只执行最后一次
    ///
    /// _Requirements: FR-6.1_
    func testDebounceReset() async throws {
        // Given: 创建一个保存计数器
        var saveCount = 0
        let expectation = XCTestExpectation(description: "只应该执行一次保存")
        
        let manager = AutoSaveManager(debounceDelay: 0.3) {
            saveCount += 1
            expectation.fulfill()
        }
        
        // When: 快速连续调度多次
        manager.scheduleAutoSave()
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        manager.scheduleAutoSave()
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        manager.scheduleAutoSave()
        
        // Then: 等待延迟时间
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // 只应该执行一次保存
        XCTAssertEqual(saveCount, 1, "连续调度应该只执行最后一次保存")
    }
    
    // MARK: - 测试：取消保存
    
    /// 测试取消待处理的保存
    ///
    /// **验收标准**：可以取消待处理的保存
    ///
    /// _Requirements: FR-6.3_
    func testCancelAutoSave() async throws {
        // Given: 创建一个保存计数器
        var saveCount = 0
        
        let manager = AutoSaveManager(debounceDelay: 0.3) {
            saveCount += 1
        }
        
        // When: 调度保存后立即取消
        manager.scheduleAutoSave()
        manager.cancelAutoSave()
        
        // Then: 等待延迟时间
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        // 保存不应该执行
        XCTAssertEqual(saveCount, 0, "取消后保存不应该执行")
    }
    
    // MARK: - 测试：立即保存
    
    /// 测试立即保存功能
    ///
    /// **验收标准**：立即保存不等待防抖延迟
    func testSaveImmediately() async throws {
        // Given: 创建一个保存计数器
        var saveCount = 0
        
        let manager = AutoSaveManager(debounceDelay: 2.0) {
            saveCount += 1
        }
        
        // When: 立即保存
        await manager.saveImmediately()
        
        // Then: 保存应该立即执行
        XCTAssertEqual(saveCount, 1, "立即保存应该不等待延迟")
    }
    
    // MARK: - 测试：并发控制
    
    /// 测试保存状态标记
    ///
    /// **验收标准**：并发保存正确处理
    ///
    /// _Requirements: FR-5.1, FR-5.3_
    func testSaveStateTracking() async throws {
        // Given: 创建管理器
        let manager = AutoSaveManager(debounceDelay: 0.5) {
            // 空回调
        }
        
        // When: 标记保存开始
        XCTAssertFalse(manager.isSaving, "初始状态不应该在保存中")
        XCTAssertNil(manager.currentSavingVersion, "初始状态没有保存版本")
        
        manager.markSaveStarted(version: 5)
        
        // Then: 应该在保存中
        XCTAssertTrue(manager.isSaving, "应该在保存中")
        XCTAssertEqual(manager.currentSavingVersion, 5, "保存版本应该是 5")
        
        // When: 标记保存完成
        manager.markSaveCompleted()
        
        // Then: 不应该在保存中
        XCTAssertFalse(manager.isSaving, "保存完成后不应该在保存中")
        XCTAssertNil(manager.currentSavingVersion, "保存完成后没有保存版本")
    }
    
    // MARK: - 测试：多次保存
    
    /// 测试多次保存是否正确执行
    func testMultipleSaves() async throws {
        // Given: 创建一个保存计数器
        var saveCount = 0
        let expectation1 = XCTestExpectation(description: "第一次保存")
        let expectation2 = XCTestExpectation(description: "第二次保存")
        
        let manager = AutoSaveManager(debounceDelay: 0.2) {
            saveCount += 1
            if saveCount == 1 {
                expectation1.fulfill()
            } else if saveCount == 2 {
                expectation2.fulfill()
            }
        }
        
        // When: 调度第一次保存
        manager.scheduleAutoSave()
        await fulfillment(of: [expectation1], timeout: 1.0)
        
        // 调度第二次保存
        manager.scheduleAutoSave()
        await fulfillment(of: [expectation2], timeout: 1.0)
        
        // Then: 应该执行两次保存
        XCTAssertEqual(saveCount, 2, "应该执行两次保存")
    }
    
    // MARK: - 测试：调试信息
    
    /// 测试调试信息输出
    func testDebugInfo() {
        // Given: 创建管理器
        let manager = AutoSaveManager(debounceDelay: 2.0) {
            // 空回调
        }
        
        // When: 获取调试信息
        let debugInfo = manager.getDebugInfo()
        
        // Then: 应该包含关键信息
        XCTAssertTrue(debugInfo.contains("AutoSaveManager"), "应该包含类名")
        XCTAssertTrue(debugInfo.contains("debounceDelay"), "应该包含防抖延迟")
        XCTAssertTrue(debugInfo.contains("isSaving"), "应该包含保存状态")
    }
    
    // MARK: - 测试：边界情况
    
    /// 测试零延迟
    func testZeroDelay() async throws {
        // Given: 创建零延迟的管理器
        var saveCount = 0
        let expectation = XCTestExpectation(description: "保存应该立即执行")
        
        let manager = AutoSaveManager(debounceDelay: 0.0) {
            saveCount += 1
            expectation.fulfill()
        }
        
        // When: 调度保存
        manager.scheduleAutoSave()
        
        // Then: 应该几乎立即执行
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertEqual(saveCount, 1, "零延迟应该立即执行")
    }
    
    /// 测试长延迟
    func testLongDelay() async throws {
        // Given: 创建长延迟的管理器
        var saveCount = 0
        
        let manager = AutoSaveManager(debounceDelay: 5.0) {
            saveCount += 1
        }
        
        // When: 调度保存后立即取消
        manager.scheduleAutoSave()
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        manager.cancelAutoSave()
        
        // Then: 保存不应该执行
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
        XCTAssertEqual(saveCount, 0, "取消后长延迟保存不应该执行")
    }
}
