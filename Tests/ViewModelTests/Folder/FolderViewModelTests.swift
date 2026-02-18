//
//  FolderViewModelTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  文件夹视图模型单元测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class FolderViewModelTests: XCTestCase {
    var sut: FolderViewModel!
    var mockNoteStorage: MockNoteStorage!
    var mockNoteService: MockNoteService!

    override func setUp() {
        super.setUp()
        mockNoteStorage = MockNoteStorage()
        mockNoteService = MockNoteService()
        sut = FolderViewModel(
            noteStorage: mockNoteStorage,
            noteService: mockNoteService
        )
    }

    override func tearDown() {
        sut = nil
        mockNoteStorage = nil
        mockNoteService = nil
        super.tearDown()
    }

    // MARK: - 加载文件夹测试

    func testLoadFolders_Success_UpdatesFolders() async {
        // Given
        let folder1 = Folder(id: "1", name: "工作", count: 5, createdAt: Date())
        let folder2 = Folder(id: "2", name: "生活", count: 3, createdAt: Date().addingTimeInterval(-3600))
        try? mockNoteStorage.saveFolder(folder1)
        try? mockNoteStorage.saveFolder(folder2)

        // When
        await sut.loadFolders()

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.folders.count, 2)
        XCTAssertNil(sut.errorMessage)
        // 验证按创建时间排序（新的在前）
        XCTAssertEqual(sut.folders.first?.id, "1")
    }

    func testLoadFolders_WithError_SetsErrorMessage() async {
        // Given
        mockNoteStorage.mockError = NSError(domain: "test", code: -1)

        // When
        await sut.loadFolders()

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.folders.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - 创建文件夹测试

    func testCreateFolder_WithValidName_CreatesFolder() async {
        // Given
        let folderName = "新文件夹"

        // When
        await sut.createFolder(name: folderName)

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.folders.count, 1)
        XCTAssertEqual(sut.folders.first?.name, folderName)
    }

    func testCreateFolder_WithEmptyName_SetsErrorMessage() async {
        // Given
        let folderName = "   "

        // When
        await sut.createFolder(name: folderName)

        // Then
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.folders.isEmpty)
    }

    func testCreateFolder_WithDuplicateName_SetsErrorMessage() async {
        // Given
        let folderName = "工作"
        let existingFolder = Folder(id: "1", name: folderName, count: 0)
        try? mockNoteStorage.saveFolder(existingFolder)
        await sut.loadFolders()

        // When
        await sut.createFolder(name: folderName)

        // Then
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.folders.count, 1) // 只有原来的文件夹
    }

    // MARK: - 删除文件夹测试

    func testDeleteFolder_WithNormalFolder_DeletesFolder() async {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0, isSystem: false)
        try? mockNoteStorage.saveFolder(folder)
        await sut.loadFolders()

        // When
        await sut.deleteFolder(folder)

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(sut.folders.isEmpty)
    }

    func testDeleteFolder_WithSystemFolder_SetsErrorMessage() async {
        // Given
        let systemFolder = Folder(id: "0", name: "所有笔记", count: 0, isSystem: true)

        // When
        await sut.deleteFolder(systemFolder)

        // Then
        XCTAssertNotNil(sut.errorMessage)
    }

    func testDeleteFolder_WhenSelected_ClearsSelection() async {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0)
        try? mockNoteStorage.saveFolder(folder)
        await sut.loadFolders()
        sut.selectFolder(folder)

        // When
        await sut.deleteFolder(folder)

        // Then
        XCTAssertNil(sut.selectedFolder)
    }

    // MARK: - 重命名文件夹测试

    func testRenameFolder_WithValidName_RenamesFolder() async {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0, isSystem: false)
        try? mockNoteStorage.saveFolder(folder)
        await sut.loadFolders()
        let newName = "工作笔记"

        // When
        await sut.renameFolder(folder, newName: newName)

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.folders.first?.name, newName)
    }

    func testRenameFolder_WithEmptyName_SetsErrorMessage() async {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0)

        // When
        await sut.renameFolder(folder, newName: "   ")

        // Then
        XCTAssertNotNil(sut.errorMessage)
    }

    func testRenameFolder_WithSystemFolder_SetsErrorMessage() async {
        // Given
        let systemFolder = Folder(id: "0", name: "所有笔记", count: 0, isSystem: true)

        // When
        await sut.renameFolder(systemFolder, newName: "新名称")

        // Then
        XCTAssertNotNil(sut.errorMessage)
    }

    func testRenameFolder_WithDuplicateName_SetsErrorMessage() async {
        // Given
        let folder1 = Folder(id: "1", name: "工作", count: 0)
        let folder2 = Folder(id: "2", name: "生活", count: 0)
        try? mockNoteStorage.saveFolder(folder1)
        try? mockNoteStorage.saveFolder(folder2)
        await sut.loadFolders()

        // When
        await sut.renameFolder(folder1, newName: "生活")

        // Then
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - 选择文件夹测试

    func testSelectFolder_UpdatesSelectedFolder() {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0)

        // When
        sut.selectFolder(folder)

        // Then
        XCTAssertEqual(sut.selectedFolder?.id, folder.id)
    }

    func testSelectFolder_WithNil_ClearsSelection() {
        // Given
        let folder = Folder(id: "1", name: "工作", count: 0)
        sut.selectFolder(folder)

        // When
        sut.selectFolder(nil)

        // Then
        XCTAssertNil(sut.selectedFolder)
    }
}
