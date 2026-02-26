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
/// 实现 NoteStorageProtocol，提供笔记的内存存储功能
/// 使用 actor 隔离保证线程安全
actor DefaultNoteStorage: NoteStorageProtocol {
    // MARK: - Properties

    private var notes: [String: Note] = [:]
    private var folders: [String: Folder] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - NoteStorageProtocol - 读取操作

    func fetchAllNotes() throws -> [Note] {
        Array(notes.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchNote(id: String) throws -> Note? {
        notes[id]
    }

    func fetchNotes(in folderId: String) throws -> [Note] {
        notes.values
            .filter { $0.folderId == folderId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func searchNotes(query: String) throws -> [Note] {
        let lowercasedQuery = query.lowercased()
        return notes.values
            .filter {
                $0.title.lowercased().contains(lowercasedQuery) ||
                    $0.content.lowercased().contains(lowercasedQuery)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchStarredNotes() throws -> [Note] {
        notes.values
            .filter(\.isStarred)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - NoteStorageProtocol - 写入操作

    func saveNote(_ note: Note) throws {
        notes[note.id] = note
    }

    func saveNotes(_ notes: [Note]) throws {
        for note in notes {
            self.notes[note.id] = note
        }
    }

    func deleteNote(id: String) throws {
        notes.removeValue(forKey: id)
    }

    func deleteNotes(ids: [String]) throws {
        for id in ids {
            notes.removeValue(forKey: id)
        }
    }

    // MARK: - NoteStorageProtocol - 批量操作

    func performBatchUpdate(_ block: @Sendable () throws -> Void) throws {
        try block()
    }

    // MARK: - NoteStorageProtocol - 文件夹操作

    func fetchAllFolders() throws -> [Folder] {
        Array(folders.values).sorted { $0.name < $1.name }
    }

    func fetchFolder(id: String) throws -> Folder? {
        folders[id]
    }

    func saveFolder(_ folder: Folder) throws {
        folders[folder.id] = folder
    }

    func saveFolders(_ folders: [Folder]) throws {
        for folder in folders {
            self.folders[folder.id] = folder
        }
    }

    func deleteFolder(id: String) throws {
        folders.removeValue(forKey: id)
    }

    // MARK: - NoteStorageProtocol - 统计操作

    func getNoteCount() throws -> Int {
        notes.count
    }

    func getNoteCount(in folderId: String) throws -> Int {
        notes.values.count(where: { $0.folderId == folderId })
    }

    // MARK: - 异步读取

    func getNote(id: String) async throws -> Note {
        guard let note = notes[id] else {
            throw StorageError.noteNotFound
        }
        return note
    }
}

enum StorageError: Error {
    case noteNotFound
}
