//
//  ViewModelTestTemplate.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  ViewModel 单元测试模板
//

import XCTest
@testable import MiNoteLibrary

/// ViewModel 测试模板
///
/// 使用此模板创建新的 ViewModel 测试
/// 复制此文件并重命名为 <YourViewModel>Tests.swift
///
/// 示例:
/// ```swift
/// final class NoteListViewModelTests: ViewModelTestCase {
///     var sut: NoteListViewModel!
///     var mockNoteService: MockNoteService!
///
///     override func setUp() {
///         super.setUp()
///         mockNoteService = MockNoteService()
///         container.register(NoteServiceProtocol.self, instance: mockNoteService)
///         sut = NoteListViewModel(noteService: mockNoteService)
///     }
///
///     override func tearDown() {
///         sut = nil
///         mockNoteService = nil
///         super.tearDown()
///     }
///
///     func testInitialization() {
///         // Given: ViewModel 已初始化
///         // When: 检查初始状态
///         // Then: 应该处于正确的初始状态
///         XCTAssertNotNil(sut)
///     }
/// }
/// ```
class ViewModelTestCase: BaseTestCase {

    // MARK: - Test Lifecycle

    override func setUp() {
        super.setUp()
        // 配置 ViewModel 测试所需的通用服务
        configureCommonServices()
    }

    // MARK: - Configuration

    /// 配置通用服务
    ///
    /// 为 ViewModel 测试配置常用的 mock 服务
    /// 子类可以重写此方法来添加额外的服务
    func configureCommonServices() {
        // 注册常用的 mock 服务
        let mockNoteService = MockNoteService()
        let mockSyncService = MockSyncService()
        let mockAuthService = MockAuthenticationService()
        let mockNoteStorage = MockNoteStorage()
        let mockNetworkMonitor = MockNetworkMonitor()

        container.register(NoteServiceProtocol.self, instance: mockNoteService)
        container.register(SyncServiceProtocol.self, instance: mockSyncService)
        container.register(AuthenticationServiceProtocol.self, instance: mockAuthService)
        container.register(NoteStorageProtocol.self, instance: mockNoteStorage)
        container.register(NetworkMonitorProtocol.self, instance: mockNetworkMonitor)
    }

    // MARK: - Helper Methods

    /// 等待 ViewModel 状态变化
    /// - Parameters:
    ///   - timeout: 超时时间
    ///   - condition: 条件闭包
    func waitForViewModelState(timeout: TimeInterval = 2.0, condition: @escaping () -> Bool) {
        let expectation = XCTestExpectation(description: "ViewModel state change")

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if condition() {
                expectation.fulfill()
                timer.invalidate()
            }
        }

        wait(for: [expectation], timeout: timeout)
        timer.invalidate()
    }

    /// 验证 ViewModel 发布的事件
    /// - Parameters:
    ///   - publisher: Combine Publisher
    ///   - timeout: 超时时间
    ///   - validation: 验证闭包
    func verifyPublishedValue<T>(
        _ publisher: Published<T>.Publisher,
        timeout: TimeInterval = 2.0,
        validation: @escaping (T) -> Bool
    ) {
        let expectation = XCTestExpectation(description: "Published value")

        let cancellable = publisher.sink { value in
            if validation(value) {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: timeout)
        cancellable.cancel()
    }
}

// MARK: - Test Assertions

extension ViewModelTestCase {

    /// 断言 ViewModel 处于加载状态
    /// - Parameter viewModel: 实现 LoadableViewModel 的 ViewModel
    func assertIsLoading(_ viewModel: some LoadableViewModel, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(viewModel.isLoading, "ViewModel should be loading", file: file, line: line)
    }

    /// 断言 ViewModel 不处于加载状态
    /// - Parameter viewModel: 实现 LoadableViewModel 的 ViewModel
    func assertIsNotLoading(_ viewModel: some LoadableViewModel, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(viewModel.isLoading, "ViewModel should not be loading", file: file, line: line)
    }

    /// 断言 ViewModel 有错误
    /// - Parameters:
    ///   - viewModel: 实现 LoadableViewModel 的 ViewModel
    ///   - expectedError: 期望的错误类型
    func assertHasError(
        _ viewModel: some LoadableViewModel,
        expectedError: Error? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertNotNil(viewModel.error, "ViewModel should have an error", file: file, line: line)

        if let expectedError {
            XCTAssertEqual(
                viewModel.error?.localizedDescription,
                expectedError.localizedDescription,
                "Error should match expected error",
                file: file,
                line: line
            )
        }
    }
}

// MARK: - LoadableViewModel Protocol (for testing)

/// 可加载的 ViewModel 协议
///
/// 用于测试支持加载状态的 ViewModel
protocol LoadableViewModel {
    var isLoading: Bool { get }
    var error: Error? { get }
}
