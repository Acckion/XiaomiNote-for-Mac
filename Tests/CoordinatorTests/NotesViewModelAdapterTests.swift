//
//  NotesViewModelAdapterTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  NotesViewModelAdapter 单元测试
//

import XCTest
import Combine
@testable import MiNoteLibrary

/// NotesViewModelAdapter 单元测试
///
/// 测试适配器的状态同步和方法委托功能
@MainActor
final class NotesViewModelAdapterTests: XCTestCase {
    
    // MARK: - Properties
    
    var sut: NotesViewModelAdapter!
    var coordinator: AppCoordinator!
    var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 配置依赖注入
        DIContainer.shared.configure()
        
        // 创建 AppCoordinator
        coordinator = AppCoordinator()
        
        // 创建适配器
        sut = NotesViewModelAdapter(coordinator: coordinator)
        
        // 初始化 Cancellables
        cancellables = Set<AnyCancellable>()
        
        print("[NotesViewModelAdapterTests] setUp 完成")
    }
    
    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        coordinator = nil
        
        try await super.tearDown()
        
        print("[NotesViewModelAdapterTests] tearDown 完成")
    }
    
    // MARK: - 初始化测试
    
    /// 测试适配器初始化
    func testAdapterInitialization() {
        // Given & When
        // 适配器已在 setUp 中创建
        
        // Then
        XCTAssertNotNil(sut, "适配器应该成功初始化")
        XCTAssertNotNil(sut.notes, "笔记列表应该初始化")
        XCTAssertNotNil(sut.folders, "文件夹列表应该初始化")
    }
    
    // MARK: - 状态同步测试
    
    /// 测试笔记列表同步
    func testNotesListSync() {
        // Given
        let expectation = expectation(description: "笔记列表同步")
        let testNote = Note(
            id: "test-1",
            title: "测试笔记",
            content: "测试内容",
            folderId: "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // When
        sut.$notes
            .dropFirst() // 跳过初始值
            .sink { notes in
                // Then
                XCTAssertEqual(notes.count, 1, "应该有 1 条笔记")
                XCTAssertEqual(notes.first?.id, testNote.id, "笔记 ID 应该匹配")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 添加笔记到 coordinator
        coordinator.noteListViewModel.notes = [testNote]
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// 测试文件夹列表同步
    func testFoldersListSync() {
        // Given
        let expectation = expectation(description: "文件夹列表同步")
        let testFolder = Folder(
            id: "test-folder-1",
            name: "测试文件夹",
            count: 0,
            isSystem: false
        )
        
        // When
        sut.$folders
            .dropFirst() // 跳过初始值
            .sink { folders in
                // Then
                XCTAssertEqual(folders.count, 1, "应该有 1 个文件夹")
                XCTAssertEqual(folders.first?.id, testFolder.id, "文件夹 ID 应该匹配")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 添加文件夹到 coordinator
        coordinator.folderViewModel.folders = [testFolder]
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// 测试选中笔记同步
    func testSelectedNoteSync() {
        // Given
        let expectation = expectation(description: "选中笔记同步")
        let testNote = Note(
            id: "test-1",
            title: "测试笔记",
            content: "测试内容",
            folderId: "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // When
        sut.$selectedNote
            .dropFirst() // 跳过初始值
            .sink { note in
                // Then
                XCTAssertNotNil(note, "应该有选中的笔记")
                XCTAssertEqual(note?.id, testNote.id, "笔记 ID 应该匹配")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 选中笔记
        coordinator.noteListViewModel.selectedNote = testNote
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// 测试加载状态同步
    func testLoadingStateSync() {
        // Given
        let expectation = expectation(description: "加载状态同步")
        
        // When
        sut.$isLoading
            .dropFirst() // 跳过初始值
            .sink { isLoading in
                // Then
                XCTAssertTrue(isLoading, "应该处于加载状态")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 设置加载状态
        coordinator.noteListViewModel.isLoading = true
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - 方法委托测试
    
    /// 测试加载文件夹
    func testLoadFolders() async {
        // Given
        // 适配器已初始化
        
        // When
        sut.loadFolders()
        
        // 等待异步操作完成
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then
        // 验证 coordinator 的 folderViewModel 被调用
        // (实际测试需要 Mock 对象来验证)
    }
    
    /// 测试选择文件夹
    func testSelectFolder() {
        // Given
        let testFolder = Folder(
            id: "test-folder-1",
            name: "测试文件夹",
            count: 0,
            isSystem: false
        )
        
        // When
        sut.selectFolderWithCoordinator(testFolder)
        
        // Then
        // 验证 coordinator 处理文件夹选择
        // (实际测试需要 Mock 对象来验证)
    }
    
    /// 测试选择笔记
    func testSelectNote() {
        // Given
        let testNote = Note(
            id: "test-1",
            title: "测试笔记",
            content: "测试内容",
            folderId: "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // When
        sut.selectNoteWithCoordinator(testNote)
        
        // Then
        // 验证 coordinator 处理笔记选择
        // (实际测试需要 Mock 对象来验证)
    }
    
    /// 测试创建新笔记
    func testCreateNewNote() {
        // Given
        let initialCount = sut.notes.count
        
        // When
        sut.createNewNote()
        
        // 等待异步操作完成
        let expectation = expectation(description: "创建新笔记")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(sut.notes.count, initialCount + 1, "应该增加一条笔记")
        XCTAssertEqual(sut.notes.first?.title, "新笔记", "新笔记标题应该是'新笔记'")
    }
    
    // MARK: - 性能测试
    
    /// 测试状态同步性能
    func testStateSyncPerformance() {
        measure {
            // 模拟大量状态更新
            for i in 0..<100 {
                let note = Note(
                    id: "test-\(i)",
                    title: "测试笔记 \(i)",
                    content: "测试内容",
                    folderId: "0",
                    isStarred: false,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                coordinator.noteListViewModel.notes.append(note)
            }
        }
    }
}
