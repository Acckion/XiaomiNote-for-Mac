//
//  SearchViewModelTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  搜索视图模型单元测试
//

import XCTest
@testable import MiNoteLibrary

@MainActor
final class SearchViewModelTests: XCTestCase {
    var sut: SearchViewModel!
    var mockNoteStorage: MockNoteStorage!
    var mockNoteService: MockNoteService!
    
    override func setUp() {
        super.setUp()
        mockNoteStorage = MockNoteStorage()
        mockNoteService = MockNoteService()
        sut = SearchViewModel(
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
    
    // MARK: - 搜索功能测试
    
    func testSearch_WithValidKeyword_ReturnsResults() async {
        // Given
        let note1 = Note(
            id: "1",
            title: "Swift 编程",
            content: "学习 Swift 语言",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        let note2 = Note(
            id: "2",
            title: "Python 教程",
            content: "学习 Python 语言",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNoteStorage.mockSearchResults = [note1, note2]
        
        // When
        sut.search(keyword: "Swift")
        
        // Wait for debounce
        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
        
        // Then
        XCTAssertFalse(sut.isSearching)
        XCTAssertEqual(sut.searchResults.count, 2)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testSearch_WithEmptyKeyword_ClearsResults() async {
        // Given
        sut.searchResults = [Note(
            id: "1",
            title: "Test",
            content: "Test",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )]
        
        // When
        sut.search(keyword: "")
        
        // Then
        XCTAssertFalse(sut.isSearching)
        XCTAssertTrue(sut.searchResults.isEmpty)
    }
    
    func testSearch_WithError_SetsErrorMessage() async {
        // Given
        mockNoteStorage.mockError = NSError(domain: "test", code: -1)
        
        // When
        sut.search(keyword: "test")
        
        // Wait for debounce
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // Then
        XCTAssertFalse(sut.isSearching)
        XCTAssertNotNil(sut.errorMessage)
    }
    
    func testSearch_CancelsPreviousSearch() async {
        // Given
        mockNoteStorage.mockSearchResults = []
        
        // When
        sut.search(keyword: "first")
        sut.search(keyword: "second")
        
        // Wait for debounce
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // Then
        // 只有最后一次搜索应该执行
        XCTAssertFalse(sut.isSearching)
    }
    
    // MARK: - 清除搜索测试
    
    func testClearSearch_ResetsAllProperties() {
        // Given
        sut.searchText = "test"
        sut.searchResults = [Note(
            id: "1",
            title: "Test",
            content: "Test",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )]
        sut.isSearching = true
        sut.errorMessage = "error"
        
        // When
        sut.clearSearch()
        
        // Then
        XCTAssertTrue(sut.searchText.isEmpty)
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertFalse(sut.isSearching)
        XCTAssertNil(sut.errorMessage)
    }
    
    // MARK: - 搜索历史测试
    
    func testAddToHistory_AddsKeyword() {
        // Given
        let keyword = "Swift"
        
        // When
        sut.addToHistory(keyword)
        
        // Then
        XCTAssertTrue(sut.searchHistory.contains(keyword))
        XCTAssertEqual(sut.searchHistory.first, keyword)
    }
    
    func testAddToHistory_WithEmptyKeyword_DoesNotAdd() {
        // Given
        let keyword = "   "
        
        // When
        sut.addToHistory(keyword)
        
        // Then
        XCTAssertTrue(sut.searchHistory.isEmpty)
    }
    
    func testAddToHistory_WithDuplicateKeyword_MovesToFront() {
        // Given
        sut.addToHistory("first")
        sut.addToHistory("second")
        
        // When
        sut.addToHistory("first")
        
        // Then
        XCTAssertEqual(sut.searchHistory.first, "first")
        XCTAssertEqual(sut.searchHistory.count, 2)
    }
    
    func testAddToHistory_LimitsHistoryCount() {
        // Given
        for i in 1...15 {
            sut.addToHistory("keyword\(i)")
        }
        
        // Then
        XCTAssertEqual(sut.searchHistory.count, 10) // maxHistoryCount = 10
    }
    
    func testClearHistory_RemovesAllHistory() {
        // Given
        sut.addToHistory("first")
        sut.addToHistory("second")
        
        // When
        sut.clearHistory()
        
        // Then
        XCTAssertTrue(sut.searchHistory.isEmpty)
    }
    
    // MARK: - 搜索过滤器测试
    
    func testApplyFilters_WithNoResults_DoesNothing() {
        // Given
        sut.searchResults = []
        sut.filterHasTags = true
        
        // When
        sut.applyFilters()
        
        // Then
        XCTAssertTrue(sut.searchResults.isEmpty)
    }
    
    func testApplyFilters_WithResults_ReappliesSearch() async {
        // Given
        let note = Note(
            id: "1",
            title: "Test",
            content: "Test content",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNoteStorage.mockSearchResults = [note]
        sut.searchText = "test"
        sut.search(keyword: "test")
        
        // Wait for initial search
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // When
        sut.filterHasTags = true
        sut.applyFilters()
        
        // Wait for filter application
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // Then
        XCTAssertFalse(sut.isSearching)
    }
    
    func testFilterIsPrivate_FiltersPrivateNotes() async {
        // Given
        let publicNote = Note(
            id: "1",
            title: "Public",
            content: "Public content",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date(),
            isPrivate: false
        )
        let privateNote = Note(
            id: "2",
            title: "Private",
            content: "Private content",
            folderId: "0",
            createdAt: Date(),
            updatedAt: Date(),
            isPrivate: true
        )
        mockNoteStorage.mockSearchResults = [publicNote, privateNote]
        
        // When
        sut.filterIsPrivate = true
        sut.search(keyword: "test")
        
        // Wait for debounce
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // Then
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertTrue(sut.searchResults.first?.isPrivate ?? false)
    }
}
