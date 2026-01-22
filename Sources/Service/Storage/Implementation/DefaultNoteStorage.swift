//
//  DefaultNoteStorage.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  默认笔记存储实现 - 实现 NoteStorageProtocol
//

import Foundation

/// 默认笔记存储
///
/// 实现 NoteStorageProtocol，提供笔记的本地存储功能
/// 使用内存存储作为简化实现，实际项目中应使用数据库
final class DefaultNoteStorage: NoteStorageProtocol {
    // MARK: - Properties

    private var notes: [String: Note] = [:]
    private var folders: [String: Folder] = [:]
    private let lock = NSLock()

    // MARK: - Initialization

    init() {}

    // MARK: - NoteStorageProtocol - 读取操作

    func fetchAllNotes() throws -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        return Array(notes.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchNote(id: String) throws -> Note? {
        lock.lock()
        defer { lock.unlock() }
        return notes[id]
    }

    func fetchNotes(in folderId: String) throws -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        return notes.values
            .filter { $0.folderId == folderId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func searchNotes(query: String) throws -> [Note] {
        lock.lock()
        defer { lock.unlock() }

        let lowercasedQuery = query.lowercased()
        return notes.values
            .filter {
                $0.title.lowercased().contains(lowercasedQuery) ||
                $0.content.lowercased().contains(lowercasedQuery)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchStarredNotes() throws -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        return notes.values
            .filter { $0.isStarred }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - NoteStorageProtocol - 写入操作

    func saveNote(_ note: Note) throws {
        lock.lock()
        defer { lock.unlock() }
        notes[note.id] = note
    }

    func saveNotes(_ notes: [Note]) throws {
        lock.lock()
        defer { lock.unlock() }
        for note in notes {
            self.notes[note.id] = note
        }
    }

    func deleteNote(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        notes.removeValue(forKey: id)
    }

    func deleteNotes(ids: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
        for id in ids {
            notes.removeValue(forKey: id)
        }
    }

    // MARK: - NoteStorageProtocol - 批量操作

    func performBatchUpdate(_ block: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try block()
    }

    // MARK: - NoteStorageProtocol - 文件夹操作

    func fetchAllFolders() throws -> [Folder] {
        lock.lock()
        defer { lock.unlock() }
        return Array(folders.values).sorted { $0.name < $1.name }
    }

    func fetchFolder(id: String) throws -> Folder? {
        lock.lock()
        defer { lock.unlock() }
        return folders[id]
    }

    func saveFolder(_ folder: Folder) throws {
        lock.lock()
        defer { lock.unlock() }
        folders[folder.id] = folder
    }

    func saveFolders(_ folders: [Folder]) throws {
        lock.lock()
        defer { lock.unlock() }
        for folder in folders {
            self.folders[folder.id] = folder
        }
    }

    func deleteFolder(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        folders.removeValue(forKey: id)
    }

    // MARK: - NoteStorageProtocol - 统计操作

    func getNoteCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return notes.count
    }

    func getNoteCount(in folderId: String) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return notes.values.filter { $0.folderId == folderId }.count
    }

    // MARK: - 同步支持

    func getPendingChanges() async throws -> [NoteChange] {
        // 简化实现：返回空数组
        // 实际应用中应该跟踪本地更改
        return []
    }

    func getNote(id: String) async throws -> Note {
        lock.lock()
        defer { lock.unlock() }

        guard let note = notes[id] else {
            throw StorageError.noteNotFound
        }

        return note
    }
}

enum StorageError: Error {
    case noteNotFound
}
