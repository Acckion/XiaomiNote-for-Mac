//
//  MockNoteStorage.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 笔记存储服务 - 用于测试
//

import Foundation
@testable import MiNoteMac

/// Mock 笔记存储服务
///
/// 用于测试的存储服务实现，使用内存存储模拟数据库操作
class MockNoteStorage: NoteStorageProtocol {
    // MARK: - Mock 数据

    private var notes: [String: Note] = [:]
    private var folders: [String: Folder] = [:]
    var mockError: Error?

    // MARK: - 调用计数

    var fetchAllNotesCallCount = 0
    var fetchNoteCallCount = 0
    var fetchNotesInFolderCallCount = 0
    var searchNotesCallCount = 0
    var fetchStarredNotesCallCount = 0
    var saveNoteCallCount = 0
    var saveNotesCallCount = 0
    var deleteNoteCallCount = 0
    var deleteNotesCallCount = 0
    var performBatchUpdateCallCount = 0

    // MARK: - NoteStorageProtocol - 读取操作

    func fetchAllNotes() throws -> [Note] {
        fetchAllNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        return Array(notes.values)
    }

    func fetchNote(id: String) throws -> Note? {
        fetchNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        return notes[id]
    }

    func fetchNotes(in folderId: String) throws -> [Note] {
        fetchNotesInFolderCallCount += 1

        if let error = mockError {
            throw error
        }

        return notes.values.filter { $0.folderId == folderId }
    }

    func searchNotes(query: String) throws -> [Note] {
        searchNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        let lowercasedQuery = query.lowercased()
        return notes.values.filter {
            $0.title.lowercased().contains(lowercasedQuery) ||
            $0.content.lowercased().contains(lowercasedQuery)
        }
    }

    func fetchStarredNotes() throws -> [Note] {
        fetchStarredNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        return notes.values.filter { $0.isStarred }
    }

    // MARK: - NoteStorageProtocol - 写入操作

    func saveNote(_ note: Note) throws {
        saveNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        notes[note.id] = note
    }

    func saveNotes(_ notes: [Note]) throws {
        saveNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        for note in notes {
            self.notes[note.id] = note
        }
    }

    func deleteNote(id: String) throws {
        deleteNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        notes.removeValue(forKey: id)
    }

    func deleteNotes(ids: [String]) throws {
        deleteNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        for id in ids {
            notes.removeValue(forKey: id)
        }
    }

    // MARK: - NoteStorageProtocol - 批量操作

    func performBatchUpdate(_ block: () throws -> Void) throws {
        performBatchUpdateCallCount += 1

        if let error = mockError {
            throw error
        }

        try block()
    }

    // MARK: - NoteStorageProtocol - 文件夹操作

    func fetchAllFolders() throws -> [Folder] {
        if let error = mockError {
            throw error
        }

        return Array(folders.values)
    }

    func fetchFolder(id: String) throws -> Folder? {
        if let error = mockError {
            throw error
        }

        return folders[id]
    }

    func saveFolder(_ folder: Folder) throws {
        if let error = mockError {
            throw error
        }

        folders[folder.id] = folder
    }

    func saveFolders(_ folders: [Folder]) throws {
        if let error = mockError {
            throw error
        }

        for folder in folders {
            self.folders[folder.id] = folder
        }
    }

    func deleteFolder(id: String) throws {
        if let error = mockError {
            throw error
        }

        folders.removeValue(forKey: id)
    }

    // MARK: - NoteStorageProtocol - 统计操作

    func getNoteCount() throws -> Int {
        if let error = mockError {
            throw error
        }

        return notes.count
    }

    func getNoteCount(in folderId: String) throws -> Int {
        if let error = mockError {
            throw error
        }

        return notes.values.filter { $0.folderId == folderId }.count
    }

    // MARK: - Helper Methods

    /// 重置所有状态
    func reset() {
        notes.removeAll()
        folders.removeAll()
        mockError = nil
        resetCallCounts()
    }

    /// 重置调用计数
    func resetCallCounts() {
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
}
