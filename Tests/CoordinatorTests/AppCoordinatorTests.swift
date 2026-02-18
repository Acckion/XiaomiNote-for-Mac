//
//  AppCoordinatorTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  应用协调器集成测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class AppCoordinatorTests: XCTestCase {
    var sut: AppCoordinator!
    var container: DIContainer!
    var mockNoteStorage: MockNoteStorage!
    var mockNoteService: MockNoteService!
    var mockSyncService: MockSyncService!
    var mockNetworkMonitor: MockNetworkMonitor!
    var mockAuthService: MockAuthenticationService!
    var mockAudioService: MockAudioService!

    override func setUp() {
        super.setUp()

        // 创建 Mock 服务
        mockNoteStorage = MockNoteStorage()
        mockNoteService = MockNoteService()
        mockSyncService = MockSyncService()
        mockNetworkMonitor = MockNetworkMonitor()
        mockAuthService = MockAuthenticationService()
        mockAudioService = MockAudioService()

        // 配置 DIContainer
        container = DIContainer.shared
        container.register(NoteStorageProtocol.self, instance: mockNoteStorage)
        container.register(NoteServiceProtocol.self, instance: mockNoteService)
        container.register(SyncServiceProtocol.self, instance: mockSyncService)
        container.register(NetworkMonitorProtocol.self, instance: mockNetworkMonitor)
        container.register(AuthenticationServiceProtocol.self, instance: mockAuthService)
        container.register(AudioServiceProtocol.self, instance: mockAudioService)

        // 创建 AppCoordinator
        sut = AppCoordinator(container: container)
    }

    override func tearDown() {
        sut = nil
        container.reset()
        mockNoteStorage = nil
        mockNoteService = nil
        mockSyncService = nil
        mockNetworkMonitor = nil
        mockAuthService = nil
        mockAudioService = nil
        super.tearDown()
    }

    // MARK: - 初始化测试

    func testInit_CreatesAllViewModels() {
        // Then
        XCTAssertNotNil(sut.noteListViewModel)
        XCTAssertNotNil(sut.noteEditorViewModel)
        XCTAssertNotNil(sut.syncCoordinator)
        XCTAssertNotNil(sut.authViewModel)
        XCTAssertNotNil(sut.searchViewModel)
        XCTAssertNotNil(sut.folderViewModel)
        XCTAssertNotNil(sut.audioPanelViewModel)
    }

    // MARK: - 启动测试

    func testStart_LoadsFoldersAndNotes() async {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0)
        try? mockNoteStorage.saveFolder(folder)

        let note = Note(
            id: "1",
            title: "测试笔记",
            content: "测试内容",
            folderId: "1",
            createdAt: Date(),
            updatedAt: Date()
        )
        try? mockNoteStorage.saveNote(note)

        // When
        await sut.start()

        // Then
        XCTAssertEqual(sut.folderViewModel.folders.count, 1)
        XCTAssertEqual(sut.noteListViewModel.notes.count, 1)
    }

    func testStart_WhenLoggedIn_StartsSync() async {
        // Given
        mockAuthService.mockIsLoggedIn = true
        sut.authViewModel.isLoggedIn = true

        // When
        await sut.start()

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(mockSyncService.startSyncCallCount, 1)
    }

    // MARK: - 笔记选择通信测试

    func testNoteSelection_LoadsNoteInEditor() async {
        // Given
        let note = Note(
            id: "1",
            title: "测试笔记",
            content: "测试内容",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        try? mockNoteStorage.saveNote(note)

        // When
        sut.handleNoteSelection(note)

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(sut.noteEditorViewModel.currentNote?.id, note.id)
    }

    // MARK: - 文件夹选择通信测试

    func testFolderSelection_FiltersNoteList() async {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0)
        try? mockNoteStorage.saveFolder(folder)

        let note1 = Note(
            id: "1",
            title: "工作笔记",
            content: "内容",
            folderId: "1",
            createdAt: Date(),
            updatedAt: Date()
        )
        let note2 = Note(
            id: "2",
            title: "生活笔记",
            content: "内容",
            folderId: "2",
            createdAt: Date(),
            updatedAt: Date()
        )
        try? mockNoteStorage.saveNote(note1)
        try? mockNoteStorage.saveNote(note2)

        // When
        sut.handleFolderSelection(folder)

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(sut.noteListViewModel.selectedFolder?.id, folder.id)
    }

    // MARK: - 同步完成通信测试

    func testSyncCompletion_RefreshesNoteList() async {
        // Given
        let note = Note(
            id: "1",
            title: "新笔记",
            content: "内容",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )

        let syncResult = SyncResult(
            notes: [note],
            deletedIds: [],
            folders: [],
            deletedFolderIds: [],
            lastSyncTime: Date()
        )

        try? mockNoteStorage.saveNote(note)

        // When
        sut.syncCoordinator.syncResult = syncResult

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(sut.noteListViewModel.notes.count, 1)
    }

    // MARK: - 认证状态通信测试

    func testLogin_StartsSync() async {
        // Given
        mockAuthService.mockIsLoggedIn = true

        // When
        sut.authViewModel.isLoggedIn = true

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(mockSyncService.startSyncCallCount, 1)
    }

    func testLogout_StopsSync() async {
        // Given
        sut.authViewModel.isLoggedIn = true

        // When
        sut.authViewModel.isLoggedIn = false

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(mockSyncService.stopSyncCallCount, 1)
    }

    // MARK: - 搜索通信测试

    func testSearch_UpdatesNoteList() async {
        // Given
        let note = Note(
            id: "1",
            title: "Swift 编程",
            content: "学习 Swift",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNoteStorage.mockSearchResults = [note]

        // When
        sut.handleSearchRequest("Swift")

        // Wait for debounce and async operation
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Then
        XCTAssertEqual(sut.noteListViewModel.notes.count, 1)
    }

    func testClearSearch_RestoresNoteList() async {
        // Given
        let note1 = Note(
            id: "1",
            title: "笔记1",
            content: "内容1",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        let note2 = Note(
            id: "2",
            title: "笔记2",
            content: "内容2",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        try? mockNoteStorage.saveNote(note1)
        try? mockNoteStorage.saveNote(note2)

        // 先搜索
        mockNoteStorage.mockSearchResults = [note1]
        sut.handleSearchRequest("笔记1")
        try? await Task.sleep(nanoseconds: 400_000_000)

        // When - 清除搜索
        sut.handleClearSearch()

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(sut.noteListViewModel.notes.count, 2)
    }

    // MARK: - 动作处理测试

    func testHandleSyncRequest_StartsSync() async {
        // When
        await sut.handleSyncRequest()

        // Then
        XCTAssertEqual(mockSyncService.startSyncCallCount, 1)
    }
}
