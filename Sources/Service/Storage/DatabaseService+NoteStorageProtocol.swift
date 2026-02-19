//
//  DatabaseService+NoteStorageProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  DatabaseService 实现 NoteStorageProtocol 协议
//

import Foundation

// MARK: - NoteStorageProtocol Conformance

extension DatabaseService: NoteStorageProtocol {
    // MARK: - 读取操作

    public func fetchAllNotes() throws -> [Note] {
        try getAllNotes()
    }

    public func fetchNote(id: String) throws -> Note? {
        try loadNote(noteId: id)
    }

    public func fetchNotes(in folderId: String) throws -> [Note] {
        let allNotes = try getAllNotes()
        return allNotes.filter { $0.folderId == folderId }
    }

    public func searchNotes(query: String) throws -> [Note] {
        let allNotes = try getAllNotes()
        let lowercasedQuery = query.lowercased()
        return allNotes.filter { note in
            note.title.lowercased().contains(lowercasedQuery) ||
                note.content.lowercased().contains(lowercasedQuery)
        }
    }

    public func fetchStarredNotes() throws -> [Note] {
        let allNotes = try getAllNotes()
        return allNotes.filter(\.isStarred)
    }

    // MARK: - 写入操作

    // saveNote 和 saveNotes 已在 DatabaseService+Notes.swift 中实现

    public func deleteNote(id: String) throws {
        try deleteNote(noteId: id)
    }

    public func deleteNotes(ids: [String]) throws {
        for id in ids {
            try deleteNote(noteId: id)
        }
    }

    // MARK: - 批量操作

    public func performBatchUpdate(_ block: () throws -> Void) throws {
        // 使用 dbQueue 保证线程安全
        try dbQueue.sync(flags: .barrier) {
            executeSQL("BEGIN TRANSACTION;")
            do {
                try block()
                executeSQL("COMMIT;")
            } catch {
                executeSQL("ROLLBACK;")
                throw error
            }
        }
    }

    // MARK: - 文件夹操作

    public func fetchAllFolders() throws -> [Folder] {
        try loadFolders()
    }

    public func fetchFolder(id: String) throws -> Folder? {
        let folders = try loadFolders()
        return folders.first { $0.id == id }
    }

    // saveFolder 和 saveFolders 已在 DatabaseService+Folders.swift 中实现

    public func deleteFolder(id: String) throws {
        try deleteFolder(folderId: id)
    }

    // MARK: - 统计操作

    public func getNoteCount() throws -> Int {
        try getAllNotes().count
    }

    public func getNoteCount(in folderId: String) throws -> Int {
        let notes = try fetchNotes(in: folderId)
        return notes.count
    }

    // MARK: - 同步支持

    public func getPendingChanges() async throws -> [NoteChange] {
        // DatabaseService 不直接跟踪变更
        // 这个功能由 UnifiedOperationQueue 处理
        []
    }

    public func getNote(id: String) async throws -> Note {
        guard let note = try loadNote(noteId: id) else {
            throw StorageError.noteNotFound
        }
        return note
    }
}
