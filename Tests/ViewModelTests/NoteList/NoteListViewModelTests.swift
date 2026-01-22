//
//  NoteListViewModelTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  NoteListViewModel 单元测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class NoteListViewModelTests: XCTestCase {
    // MARK: - Properties
    
    var sut: NoteListViewModel!
    var mockNoteStorage: MockNoteStorage!
    var mockNoteService: MockNoteService!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockNoteStorage = MockNoteStorage()
        mockNoteService = MockNoteService()
        
        sut = NoteListViewModel(
            noteStorage: mockNoteStorage,
            noteService: mockNoteService
        )
    }
    
    override func tearDown() async throws {
        sut = nil
        mockNoteStorage = nil
        mockNoteService = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Tests: loadNotes()
    
    func testLoadNotes_Success() async {
        // Given
        let expectedNotes = [
            Note.mock(id: "1", title: "Note 1"),
            Note.mock(id: "2", title: "Note 2"),
            Note.mock(id: "3", title: "Note 3")
        ]
        // 将笔记添加到 mock storage
        for note in expectedNotes {
            try? mockNoteStorage.saveNote(note)
        }
        
        // When
        await sut.loadNotes()
        
        // Then
        XCTAssertEqual(sut.notes.count, 3)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testLoadNotes_Failure() async {
        // Given
        mockNoteStorage.mockError = NSError(domain: "test", code: 1)
        
        // When
        await sut.loadNotes()
        
        // Then
        XCTAssertEqual(sut.notes.count, 0)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    func testLoadNotes_EmptyList() async {
        // Given
        // mock storage 默认为空
        
        // When
        await sut.loadNotes()
        
        // Then
        XCTAssertEqual(sut.notes.count, 0)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }
    
    // MARK: - Tests: filterNotes(by:)
    
    func testFilterNotes_ByFolder() {
        // Given
        let folder = Folder.mock(id: "folder1", name: "Work")
        sut.notes = [
            Note.mock(id: "1", folderId: "folder1"),
            Note.mock(id: "2", folderId: "folder2"),
            Note.mock(id: "3", folderId: "folder1")
        ]
        
        // When
        sut.filterNotes(by: folder)
        
        // Then
        XCTAssertEqual(sut.selectedFolder?.id, "folder1")
        XCTAssertEqual(sut.filteredNotes.count, 2)
        XCTAssertTrue(sut.filteredNotes.allSatisfy { $0.folderId == "folder1" })
    }
    
    func testFilterNotes_NoFolder() {
        // Given
        sut.notes = [
            Note.mock(id: "1", folderId: "folder1"),
            Note.mock(id: "2", folderId: "folder2"),
            Note.mock(id: "3", folderId: "folder1")
        ]
        
        // When
        sut.filterNotes(by: nil)
        
        // Then
        XCTAssertNil(sut.selectedFolder)
        XCTAssertEqual(sut.filteredNotes.count, 3)
    }
    
    // MARK: - Tests: setSortOrder(by:direction:)
    
    func testSetSortOrder_ByEditDate_Descending() {
        // Given
        let now = Date()
        sut.notes = [
            Note.mock(id: "1", updatedAt: now.addingTimeInterval(-100)),
            Note.mock(id: "2", updatedAt: now),
            Note.mock(id: "3", updatedAt: now.addingTimeInterval(-50))
        ]
        
        // When
        sut.setSortOrder(by: .editDate, direction: .descending)
        
        // Then
        XCTAssertEqual(sut.sortOrder, .editDate)
        XCTAssertEqual(sut.sortDirection, .descending)
        XCTAssertEqual(sut.filteredNotes[0].id, "2") // 最新的
        XCTAssertEqual(sut.filteredNotes[1].id, "3")
        XCTAssertEqual(sut.filteredNotes[2].id, "1") // 最旧的
    }
    
    func testSetSortOrder_ByTitle_Ascending() {
        // Given
        sut.notes = [
            Note.mock(id: "1", title: "Zebra"),
            Note.mock(id: "2", title: "Apple"),
            Note.mock(id: "3", title: "Mango")
        ]
        
        // When
        sut.setSortOrder(by: .title, direction: .ascending)
        
        // Then
        XCTAssertEqual(sut.sortOrder, .title)
        XCTAssertEqual(sut.sortDirection, .ascending)
        XCTAssertEqual(sut.filteredNotes[0].title, "Apple")
        XCTAssertEqual(sut.filteredNotes[1].title, "Mango")
        XCTAssertEqual(sut.filteredNotes[2].title, "Zebra")
    }
    
    // MARK: - Tests: selectNote(_:)
    
    func testSelectNote() {
        // Given
        let note = Note.mock(id: "1", title: "Test Note")
        
        // When
        sut.selectNote(note)
        
        // Then
        XCTAssertEqual(sut.selectedNote?.id, "1")
        XCTAssertEqual(sut.selectedNote?.title, "Test Note")
    }
    
    // MARK: - Tests: deleteNote(_:)
    
    func testDeleteNote_Success() async {
        // Given
        let note = Note.mock(id: "1", title: "To Delete")
        sut.notes = [
            note,
            Note.mock(id: "2", title: "Keep")
        ]
        sut.selectedNote = note
        
        // When
        await sut.deleteNote(note)
        
        // Then
        XCTAssertEqual(sut.notes.count, 1)
        XCTAssertEqual(sut.notes[0].id, "2")
        XCTAssertNil(sut.selectedNote) // 选中的笔记应该被清除
        XCTAssertNil(sut.errorMessage)
    }
    
    func testDeleteNote_Failure() async {
        // Given
        let note = Note.mock(id: "1", title: "To Delete")
        sut.notes = [note]
        mockNoteStorage.mockError = NSError(domain: "test", code: 1)
        
        // When
        await sut.deleteNote(note)
        
        // Then
        XCTAssertEqual(sut.notes.count, 1) // 笔记应该还在
        XCTAssertNotNil(sut.errorMessage)
    }
    
    // MARK: - Tests: moveNote(_:to:)
    
    func testMoveNote_Success() async {
        // Given
        let note = Note.mock(id: "1", folderId: "folder1")
        let targetFolder = Folder.mock(id: "folder2", name: "Target")
        sut.notes = [note]
        
        // When
        await sut.moveNote(note, to: targetFolder)
        
        // Then
        XCTAssertEqual(sut.notes[0].folderId, "folder2")
        XCTAssertNil(sut.errorMessage)
    }
    
    func testMoveNote_Failure() async {
        // Given
        let note = Note.mock(id: "1", folderId: "folder1")
        let targetFolder = Folder.mock(id: "folder2", name: "Target")
        sut.notes = [note]
        mockNoteStorage.mockError = NSError(domain: "test", code: 1)
        
        // When
        await sut.moveNote(note, to: targetFolder)
        
        // Then
        XCTAssertEqual(sut.notes[0].folderId, "folder1") // 文件夹ID应该没变
        XCTAssertNotNil(sut.errorMessage)
    }
    
    // MARK: - Tests: toggleStar(_:)
    
    func testToggleStar_Success() async {
        // Given
        let note = Note.mock(id: "1", isStarred: false)
        sut.notes = [note]
        
        // When
        await sut.toggleStar(note)
        
        // Then
        XCTAssertTrue(sut.notes[0].isStarred)
        XCTAssertNil(sut.errorMessage)
    }
    
    // MARK: - Tests: filteredNotes
    
    func testFilteredNotes_WithFolderAndStarred() {
        // Given
        let folder = Folder.mock(id: "folder1", name: "Work")
        sut.notes = [
            Note.mock(id: "1", folderId: "folder1", isStarred: true),
            Note.mock(id: "2", folderId: "folder1", isStarred: false),
            Note.mock(id: "3", folderId: "folder2", isStarred: true)
        ]
        
        // When
        sut.filterNotes(by: folder)
        sut.showStarredOnly = true
        
        // Then
        XCTAssertEqual(sut.filteredNotes.count, 1)
        XCTAssertEqual(sut.filteredNotes[0].id, "1")
    }
    
    func testFilteredNotes_NoFilters() {
        // Given
        sut.notes = [
            Note.mock(id: "1"),
            Note.mock(id: "2"),
            Note.mock(id: "3")
        ]
        
        // When & Then
        XCTAssertEqual(sut.filteredNotes.count, 3)
    }
}

// MARK: - Mock Extensions

extension Note {
    static func mock(
        id: String = UUID().uuidString,
        title: String = "Test Note",
        folderId: String = "default",
        isStarred: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Note {
        Note(
            id: id,
            title: title,
            content: "",
            folderId: folderId,
            isStarred: isStarred,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: [],
            rawData: nil,
            snippet: "Test snippet",
            colorId: 0,
            subject: nil,
            alertDate: nil,
            type: "note",
            serverTag: nil,
            status: "normal",
            settingJson: nil,
            extraInfoJson: nil
        )
    }
}

extension Folder {
    static func mock(
        id: String = UUID().uuidString,
        name: String = "Test Folder"
    ) -> Folder {
        Folder(
            id: id,
            name: name,
            count: 0,
            isSystem: false,
            isPinned: false,
            createdAt: Date(),
            rawData: nil
        )
    }
}
