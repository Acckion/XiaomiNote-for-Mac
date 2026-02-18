//
//  AppCoordinatorIntegrationTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  AppCoordinator 集成测试
//

import XCTest
@testable import MiNoteLibrary

/// AppCoordinator 集成测试
///
/// 测试 AppCoordinator 的完整集成流程
@MainActor
final class AppCoordinatorIntegrationTests: XCTestCase {
    var sut: AppCoordinator!
    var container: DIContainer!

    override func setUp() async throws {
        try await super.setUp()

        // 创建测试容器
        container = DIContainer.shared

        // 注册 Mock 服务
        let mockNoteStorage = MockNoteStorage()
        let mockNoteService = MockNoteService()
        let mockSyncService = MockSyncService()
        let mockNetworkMonitor = MockNetworkMonitor()
        let mockAuthService = MockAuthenticationService()
        let mockAudioService = MockAudioService()

        container.register(NoteStorageProtocol.self, instance: mockNoteStorage)
        container.register(NoteServiceProtocol.self, instance: mockNoteService)
        container.register(SyncServiceProtocol.self, instance: mockSyncService)
        container.register(NetworkMonitorProtocol.self, instance: mockNetworkMonitor)
        container.register(AuthenticationServiceProtocol.self, instance: mockAuthService)
        container.register(AudioServiceProtocol.self, instance: mockAudioService)

        // 创建 AppCoordinator
        sut = AppCoordinator(container: container)
    }

    override func tearDown() async throws {
        sut = nil
        container.reset()
        try await super.tearDown()
    }

    // MARK: - 初始化测试

    func testAppCoordinatorInitialization() {
        // Then: 所有 ViewModel 都应该被创建
        XCTAssertNotNil(sut.noteListViewModel)
        XCTAssertNotNil(sut.noteEditorViewModel)
        XCTAssertNotNil(sut.syncCoordinator)
        XCTAssertNotNil(sut.authViewModel)
        XCTAssertNotNil(sut.searchViewModel)
        XCTAssertNotNil(sut.folderViewModel)
        XCTAssertNotNil(sut.audioPanelViewModel)
    }

    // MARK: - 启动流程测试

    func testAppCoordinatorStart() async {
        // When: 启动应用
        await sut.start()

        // Then: 应该加载文件夹和笔记
        // 注意: 由于使用 Mock 服务,这里只验证方法被调用
        XCTAssertFalse(sut.folderViewModel.isLoading)
        XCTAssertFalse(sut.noteListViewModel.isLoading)
    }

    // MARK: - ViewModel 通信测试

    func testNoteSelectionTriggersEditorLoad() async {
        // Given: 创建一个测试笔记
        let note = Note(
            id: "test-note",
            title: "Test Note",
            content: "<new-format/><text>Test content</text>",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )

        // When: 选择笔记
        sut.handleNoteSelection(note)

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then: 编辑器应该加载笔记
        XCTAssertEqual(sut.noteEditorViewModel.currentNote?.id, note.id)
    }

    func testFolderSelectionTriggersNoteListFilter() async {
        // Given: 创建一个测试文件夹
        let folder = Folder(
            id: "test-folder",
            name: "Test Folder",
            createdAt: Date(),
            updatedAt: Date()
        )

        // When: 选择文件夹
        sut.handleFolderSelection(folder)

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then: 笔记列表应该过滤
        XCTAssertEqual(sut.noteListViewModel.selectedFolder?.id, folder.id)
    }

    func testSearchTriggersNoteListUpdate() {
        // When: 执行搜索
        sut.handleSearchRequest("test")

        // Then: 搜索 ViewModel 应该更新
        XCTAssertEqual(sut.searchViewModel.searchText, "test")
    }

    func testClearSearchRestoresNoteList() async {
        // Given: 先执行搜索
        sut.handleSearchRequest("test")

        // When: 清除搜索
        sut.handleClearSearch()

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then: 搜索文本应该被清空
        XCTAssertTrue(sut.searchViewModel.searchText.isEmpty)
    }

    // MARK: - 性能测试

    func testAppCoordinatorStartupPerformance() {
        measure {
            let coordinator = AppCoordinator(container: container)
            XCTAssertNotNil(coordinator)
        }
    }
}
