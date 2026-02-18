//
//  NoteEditorViewModelTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  NoteEditorViewModel 单元测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class NoteEditorViewModelTests: XCTestCase {
    // MARK: - Properties

    var sut: NoteEditorViewModel!
    var mockNoteStorage: MockNoteStorage!
    var mockNoteService: MockNoteService!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        mockNoteStorage = MockNoteStorage()
        mockNoteService = MockNoteService()

        sut = NoteEditorViewModel(
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

    // MARK: - Tests: loadNote(_:)

    func testLoadNote_Success() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "<new-format/><text>Test content</text>")
        try? mockNoteStorage.saveNote(note)

        // When
        await sut.loadNote(note)

        // Then
        XCTAssertEqual(sut.currentNote?.id, "1")
        XCTAssertEqual(sut.title, "Test Note")
        XCTAssertEqual(sut.content, "<new-format/><text>Test content</text>")
        XCTAssertFalse(sut.hasUnsavedChanges)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadNote_Failure() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note")
        mockNoteStorage.mockError = NSError(domain: "test", code: 1)

        // When
        await sut.loadNote(note)

        // Then
        XCTAssertNil(sut.currentNote)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testLoadNote_SameNote() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Test content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        // When - 再次加载同一个笔记
        await sut.loadNote(note)

        // Then - 不应该重复加载
        XCTAssertEqual(mockNoteStorage.fetchNoteCallCount, 1)
    }

    func testLoadNote_WithUnsavedChanges() async {
        // Given
        let note1 = Note.mock(id: "1", title: "Note 1", content: "Content 1")
        let note2 = Note.mock(id: "2", title: "Note 2", content: "Content 2")
        try? mockNoteStorage.saveNote(note1)
        try? mockNoteStorage.saveNote(note2)

        await sut.loadNote(note1)
        sut.updateContent("Modified content")

        // When - 加载另一个笔记
        await sut.loadNote(note2)

        // Then - 应该先保存之前的笔记
        XCTAssertEqual(mockNoteStorage.saveNoteCallCount, 1)
        XCTAssertEqual(sut.currentNote?.id, "2")
    }

    // MARK: - Tests: saveNote()

    func testSaveNote_Success() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Original content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        sut.updateContent("Modified content")

        // When
        await sut.saveNote()

        // Then
        XCTAssertFalse(sut.hasUnsavedChanges)
        XCTAssertFalse(sut.isSaving)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockNoteStorage.saveNoteCallCount, 1)
    }

    func testSaveNote_Failure() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Original content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        sut.updateContent("Modified content")
        mockNoteStorage.mockError = NSError(domain: "test", code: 1)

        // When
        await sut.saveNote()

        // Then
        XCTAssertTrue(sut.hasUnsavedChanges) // 保存失败，仍有未保存的更改
        XCTAssertFalse(sut.isSaving)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testSaveNote_NoCurrentNote() async {
        // Given - 没有加载笔记

        // When
        await sut.saveNote()

        // Then - 不应该调用保存
        XCTAssertEqual(mockNoteStorage.saveNoteCallCount, 0)
    }

    func testSaveNote_NoUnsavedChanges() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        // When - 没有修改内容就保存
        await sut.saveNote()

        // Then - 不应该调用保存
        XCTAssertEqual(mockNoteStorage.saveNoteCallCount, 0)
    }

    // MARK: - Tests: updateContent(_:)

    func testUpdateContent() {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Original content")
        try? mockNoteStorage.saveNote(note)

        // When
        sut.updateContent("New content")

        // Then
        XCTAssertEqual(sut.content, "New content")
        XCTAssertTrue(sut.hasUnsavedChanges)
    }

    func testUpdateContent_SameContent() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Original content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        // When - 更新为相同的内容
        sut.updateContent("Original content")

        // Then - 不应该标记为有未保存的更改
        XCTAssertFalse(sut.hasUnsavedChanges)
    }

    // MARK: - Tests: updateTitle(_:)

    func testUpdateTitle() {
        // Given
        let note = Note.mock(id: "1", title: "Original Title", content: "Content")
        try? mockNoteStorage.saveNote(note)

        // When
        sut.updateTitle("New Title")

        // Then
        XCTAssertEqual(sut.title, "New Title")
        XCTAssertTrue(sut.hasUnsavedChanges)
    }

    // MARK: - Tests: extractTitle(from:)

    func testExtractTitle_FromXML() {
        // Given
        let xml = "<new-format/><text>First Line</text><text>Second Line</text>"

        // When
        let title = sut.extractTitle(from: xml)

        // Then
        XCTAssertEqual(title, "First Line")
    }

    func testExtractTitle_FromPlainText() {
        // Given
        let text = "First Line\nSecond Line"

        // When
        let title = sut.extractTitle(from: text)

        // Then
        XCTAssertEqual(title, "First Line")
    }

    func testExtractTitle_EmptyContent() {
        // Given
        let text = ""

        // When
        let title = sut.extractTitle(from: text)

        // Then
        XCTAssertEqual(title, "未命名笔记")
    }

    func testExtractTitle_LongContent() {
        // Given
        let longText = String(repeating: "a", count: 150)

        // When
        let title = sut.extractTitle(from: longText)

        // Then
        XCTAssertEqual(title.count, 103) // 100 + "..."
        XCTAssertTrue(title.hasSuffix("..."))
    }

    // MARK: - Tests: convertToXML(_:)

    func testConvertToXML() {
        // Given
        let text = "Line 1\nLine 2\nLine 3"

        // When
        let xml = sut.convertToXML(text)

        // Then
        XCTAssertTrue(xml.hasPrefix("<new-format/>"))
        XCTAssertTrue(xml.contains("<text indent=\"1\">Line 1</text>"))
        XCTAssertTrue(xml.contains("<text indent=\"1\">Line 2</text>"))
        XCTAssertTrue(xml.contains("<text indent=\"1\">Line 3</text>"))
    }

    // MARK: - Tests: convertFromXML(_:)

    func testConvertFromXML() {
        // Given
        let xml = "<new-format/><text>Line 1</text><text>Line 2</text>"

        // When
        let text = sut.convertFromXML(xml)

        // Then
        XCTAssertEqual(text, "Line 1Line 2")
    }

    // MARK: - Tests: clearNote()

    func testClearNote() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        // When
        await sut.clearNote()

        // Then
        XCTAssertNil(sut.currentNote)
        XCTAssertEqual(sut.content, "")
        XCTAssertEqual(sut.title, "")
        XCTAssertFalse(sut.hasUnsavedChanges)
    }

    func testClearNote_WithUnsavedChanges() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Original content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        sut.updateContent("Modified content")

        // When
        await sut.clearNote()

        // Then - 应该先保存
        XCTAssertEqual(mockNoteStorage.saveNoteCallCount, 1)
        XCTAssertNil(sut.currentNote)
    }

    // MARK: - Tests: autoSave()

    func testAutoSave() async {
        // Given
        let note = Note.mock(id: "1", title: "Test Note", content: "Original content")
        try? mockNoteStorage.saveNote(note)
        await sut.loadNote(note)

        // When - 更新内容并等待自动保存
        sut.updateContent("Modified content")

        // 等待自动保存触发（3秒 + 一点缓冲时间）
        try? await Task.sleep(nanoseconds: 3_500_000_000)

        // Then - 应该自动保存
        XCTAssertEqual(mockNoteStorage.saveNoteCallCount, 1)
        XCTAssertFalse(sut.hasUnsavedChanges)
    }
}

// MARK: - Mock Extensions

extension Note {
    static func mock(
        id: String = UUID().uuidString,
        title: String = "Test Note",
        content: String = "",
        folderId: String = "default",
        isStarred: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Note {
        Note(
            id: id,
            title: title,
            content: content,
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
