//
//  MockNoteStorage.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 笔记存储服务 - 用于测试
//

import Foundation
@testable import MiNoteLibrary

/// Mock 笔记存储服务
///
/// 用于测试的存储服务实现，使用内存存储模拟数据库操作
public final class MockNoteStorage: NoteStorageProtocol, @unchecked Sendable {
    // MARK: - Mock 数据

    private var notes: [String: Note] = [:]
    private var folders: [String: Folder] = [:]
    public var mockError: Error?
    public var mockPendingChanges: [NoteChange] = []
    public var mockSearchResults: [Note]?

    // MARK: - 调用计数

    public var fetchAllNotesCallCount = 0
    public var fetchNoteCallCount = 0
    public var fetchNotesInFolderCallCount = 0
    public var searchNotesCallCount = 0
    public var fetchStarredNotesCallCount = 0
    public var saveNoteCallCount = 0
    public var saveNotesCallCount = 0
    public var deleteNoteCallCount = 0
    public var deleteNotesCallCount = 0
    public var performBatchUpdateCallCount = 0

    // MARK: - NoteStorageProtocol - 读取操作

    public func fetchAllNotes() throws -> [Note] {
        fetchAllNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        return Array(notes.values)
    }

    public func fetchNote(id: String) throws -> Note? {
        fetchNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        return notes[id]
    }

    public func fetchNotes(in folderId: String) throws -> [Note] {
        fetchNotesInFolderCallCount += 1

        if let error = mockError {
            throw error
        }

        return notes.values.filter { $0.folderId == folderId }
    }

    public func searchNotes(query: String) throws -> [Note] {
        searchNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        // 如果设置了 mockSearchResults，直接返回
        if let mockResults = mockSearchResults {
            return mockResults
        }

        let lowercasedQuery = query.lowercased()
        return notes.values.filter {
            $0.title.lowercased().contains(lowercasedQuery) ||
            $0.content.lowercased().contains(lowercasedQuery)
        }
    }

    public func fetchStarredNotes() throws -> [Note] {
        fetchStarredNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        return notes.values.filter { $0.isStarred }
    }

    // MARK: - NoteStorageProtocol - 写入操作

    public func saveNote(_ note: Note) throws {
        saveNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        notes[note.id] = note
    }

    public func saveNotes(_ notes: [Note]) throws {
        saveNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        for note in notes {
            self.notes[note.id] = note
        }
    }

    public func deleteNote(id: String) throws {
        deleteNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        notes.removeValue(forKey: id)
    }

    public func deleteNotes(ids: [String]) throws {
        deleteNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        for id in ids {
            notes.removeValue(forKey: id)
        }
    }

    // MARK: - NoteStorageProtocol - 批量操作

    public func performBatchUpdate(_ block: () throws -> Void) throws {
        performBatchUpdateCallCount += 1

        if let error = mockError {
            throw error
        }

        try block()
    }

    // MARK: - NoteStorageProtocol - 文件夹操作

    public func fetchAllFolders() throws -> [Folder] {
        if let error = mockError {
            throw error
        }

        return Array(folders.values)
    }

    public func fetchFolder(id: String) throws -> Folder? {
        if let error = mockError {
            throw error
        }

        return folders[id]
    }

    public func saveFolder(_ folder: Folder) throws {
        if let error = mockError {
            throw error
        }

        folders[folder.id] = folder
    }

    public func saveFolders(_ folders: [Folder]) throws {
        if let error = mockError {
            throw error
        }

        for folder in folders {
            self.folders[folder.id] = folder
        }
    }

    public func deleteFolder(id: String) throws {
        if let error = mockError {
            throw error
        }

        folders.removeValue(forKey: id)
    }

    // MARK: - NoteStorageProtocol - 统计操作

    public func getNoteCount() throws -> Int {
        if let error = mockError {
            throw error
        }

        return notes.count
    }

    public func getNoteCount(in folderId: String) throws -> Int {
        if let error = mockError {
            throw error
        }

        return notes.values.filter { $0.folderId == folderId }.count
    }

    // MARK: - Helper Methods

    /// 重置所有状态
    public func reset() {
        notes.removeAll()
        folders.removeAll()
        mockError = nil
        mockSearchResults = nil
        resetCallCounts()
    }

    /// 重置调用计数
    public func resetCallCounts() {
        fetchAllNotesCallCount = 0
        fetchNoteCallCount = 0
        fetchNotesInFolderCallCount = 0
        searchNotesCallCount = 0
        fetchStarredNotesCallCount = 0
        saveNoteCallCount = 0
        saveNotesCallCount = 0
        deleteNoteCallCount = 0
        deleteNotesCallCount = 0
        performBatchUpdateCallCount = 0
    }
    
    // MARK: - NoteStorageProtocol - 同步支持
    
    public func getPendingChanges() async throws -> [NoteChange] {
        if let error = mockError {
            throw error
        }
        return mockPendingChanges
    }
    
    public func getNote(id: String) async throws -> Note {
        if let error = mockError {
            throw error
        }
        
        guard let note = notes[id] else {
            throw NSError(domain: "MockNoteStorage", code: 404, userInfo: [NSLocalizedDescriptionKey: "Note not found"])
        }
        
        return note
    }
}
