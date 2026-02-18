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
final class DefaultNoteStorage: NoteStorageProtocol, @unchecked Sendable {
    // MARK: - Properties

    private var notes: [String: Note] = [:]
    private var folders: [String: Folder] = [:]
    private let queue = DispatchQueue(label: "com.minote.storage", attributes: .concurrent)

    // MARK: - Initialization

    init() {}

    // MARK: - NoteStorageProtocol - 读取操作

    func fetchAllNotes() throws -> [Note] {
        queue.sync {
            Array(notes.values).sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func fetchNote(id: String) throws -> Note? {
        queue.sync {
            notes[id]
        }
    }

    func fetchNotes(in folderId: String) throws -> [Note] {
        queue.sync {
            notes.values
                .filter { $0.folderId == folderId }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func searchNotes(query: String) throws -> [Note] {
        queue.sync {
            let lowercasedQuery = query.lowercased()
            return notes.values
                .filter {
                    $0.title.lowercased().contains(lowercasedQuery) ||
                        $0.content.lowercased().contains(lowercasedQuery)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func fetchStarredNotes() throws -> [Note] {
        queue.sync {
            notes.values
                .filter(\.isStarred)
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: - NoteStorageProtocol - 写入操作

    func saveNote(_ note: Note) throws {
        queue.async(flags: .barrier) { [weak self] in
            self?.notes[note.id] = note
        }
    }

    func saveNotes(_ notes: [Note]) throws {
        queue.async(flags: .barrier) { [weak self] in
            for note in notes {
                self?.notes[note.id] = note
            }
        }
    }

    func deleteNote(id: String) throws {
        queue.async(flags: .barrier) { [weak self] in
            self?.notes.removeValue(forKey: id)
        }
    }

    func deleteNotes(ids: [String]) throws {
        queue.async(flags: .barrier) { [weak self] in
            for id in ids {
                self?.notes.removeValue(forKey: id)
            }
        }
    }

    // MARK: - NoteStorageProtocol - 批量操作

    func performBatchUpdate(_ block: () throws -> Void) throws {
        try queue.sync(flags: .barrier) {
            try block()
        }
    }

    // MARK: - NoteStorageProtocol - 文件夹操作

    func fetchAllFolders() throws -> [Folder] {
        queue.sync {
            Array(folders.values).sorted { $0.name < $1.name }
        }
    }

    func fetchFolder(id: String) throws -> Folder? {
        queue.sync {
            folders[id]
        }
    }

    func saveFolder(_ folder: Folder) throws {
        queue.async(flags: .barrier) { [weak self] in
            self?.folders[folder.id] = folder
        }
    }

    func saveFolders(_ folders: [Folder]) throws {
        queue.async(flags: .barrier) { [weak self] in
            for folder in folders {
                self?.folders[folder.id] = folder
            }
        }
    }

    func deleteFolder(id: String) throws {
        queue.async(flags: .barrier) { [weak self] in
            self?.folders.removeValue(forKey: id)
        }
    }

    // MARK: - NoteStorageProtocol - 统计操作

    func getNoteCount() throws -> Int {
        queue.sync {
            notes.count
        }
    }

    func getNoteCount(in folderId: String) throws -> Int {
        queue.sync {
            notes.values.count(where: { $0.folderId == folderId })
        }
    }

    // MARK: - 同步支持

    func getPendingChanges() async throws -> [NoteChange] {
        // 简化实现：返回空数组
        // 实际应用中应该跟踪本地更改
        []
    }

    func getNote(id: String) async throws -> Note {
        try queue.sync {
            guard let note = notes[id] else {
                throw StorageError.noteNotFound
            }
            return note
        }
    }
}

enum StorageError: Error {
    case noteNotFound
}
