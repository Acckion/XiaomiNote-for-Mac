//
//  MockNoteService.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 笔记网络服务 - 用于测试
//

import Foundation
@testable import MiNoteLibrary

/// Mock 笔记网络服务
///
/// 用于测试的笔记服务实现，可以模拟各种场景：
/// - 成功的网络请求
/// - 网络错误
/// - 特定的返回数据
public final class MockNoteService: NoteServiceProtocol, @unchecked Sendable {
    // MARK: - Mock 数据

    public var mockNotes: [Note] = []
    public var mockFolders: [Folder] = []
    public var mockError: Error?
    public var mockSyncResult: SyncResult?

    // MARK: - 调用计数

    public var fetchNotesCallCount = 0
    public var fetchNoteCallCount = 0
    public var createNoteCallCount = 0
    public var updateNoteCallCount = 0
    public var deleteNoteCallCount = 0
    public var syncNotesCallCount = 0
    public var uploadChangesCallCount = 0
    public var fetchFoldersCallCount = 0
    public var createFolderCallCount = 0
    public var updateFolderCallCount = 0
    public var deleteFolderCallCount = 0

    // MARK: - NoteServiceProtocol - 笔记操作

    public func fetchNotes() async throws -> [Note] {
        fetchNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        return mockNotes
    }

    public func fetchNote(id: String) async throws -> Note {
        fetchNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        guard let note = mockNotes.first(where: { $0.id == id }) else {
            throw NSError(domain: "MockError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Note not found"])
        }

        return note
    }

    public func createNote(_ note: Note) async throws -> Note {
        createNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        mockNotes.append(note)
        return note
    }

    public func updateNote(_ note: Note) async throws -> Note {
        updateNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        if let index = mockNotes.firstIndex(where: { $0.id == note.id }) {
            mockNotes[index] = note
        }

        return note
    }

    public func deleteNote(id: String) async throws {
        deleteNoteCallCount += 1

        if let error = mockError {
            throw error
        }

        mockNotes.removeAll { $0.id == id }
    }

    // MARK: - NoteServiceProtocol - 同步操作

    public func syncNotes(since _: Date?) async throws -> SyncResult {
        syncNotesCallCount += 1

        if let error = mockError {
            throw error
        }

        if let result = mockSyncResult {
            return result
        }

        return SyncResult(
            notes: mockNotes,
            deletedIds: [],
            folders: mockFolders,
            deletedFolderIds: [],
            lastSyncTime: Date()
        )
    }

    public func uploadChanges(_ changes: [NoteChange]) async throws {
        uploadChangesCallCount += 1

        if let error = mockError {
            throw error
        }

        // 模拟处理变更
        for change in changes {
            switch change.type {
            case .create, .update:
                if let note = change.note {
                    if let index = mockNotes.firstIndex(where: { $0.id == note.id }) {
                        mockNotes[index] = note
                    } else {
                        mockNotes.append(note)
                    }
                }
            case .delete:
                mockNotes.removeAll { $0.id == change.noteId }
            }
        }
    }

    // MARK: - NoteServiceProtocol - 文件夹操作

    public func fetchFolders() async throws -> [Folder] {
        fetchFoldersCallCount += 1

        if let error = mockError {
            throw error
        }

        return mockFolders
    }

    public func createFolder(_ folder: Folder) async throws -> Folder {
        createFolderCallCount += 1

        if let error = mockError {
            throw error
        }

        mockFolders.append(folder)
        return folder
    }

    public func updateFolder(_ folder: Folder) async throws -> Folder {
        updateFolderCallCount += 1

        if let error = mockError {
            throw error
        }

        if let index = mockFolders.firstIndex(where: { $0.id == folder.id }) {
            mockFolders[index] = folder
        }

        return folder
    }

    public func deleteFolder(id: String) async throws {
        deleteFolderCallCount += 1

        if let error = mockError {
            throw error
        }

        mockFolders.removeAll { $0.id == id }
    }

    // MARK: - Helper Methods

    /// 重置所有状态
    public func reset() {
        mockNotes.removeAll()
        mockFolders.removeAll()
        mockError = nil
        mockSyncResult = nil
        resetCallCounts()
    }

    /// 重置调用计数
    public func resetCallCounts() {
        fetchNotesCallCount = 0
        fetchNoteCallCount = 0
        createNoteCallCount = 0
        updateNoteCallCount = 0
        deleteNoteCallCount = 0
        syncNotesCallCount = 0
        uploadChangesCallCount = 0
        fetchFoldersCallCount = 0
        createFolderCallCount = 0
        updateFolderCallCount = 0
        deleteFolderCallCount = 0
    }
}
