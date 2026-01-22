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
    
    func fetchAllNotes() throws -> [Note] {
        return try getAllNotes()
    }
    
    func fetchNote(id: String) throws -> Note? {
        return try loadNote(noteId: id)
    }
    
    func fetchNotes(in folderId: String) throws -> [Note] {
        // DatabaseService 没有专门的按文件夹获取笔记的方法
        // 从所有笔记中筛选指定文件夹的笔记
        let allNotes = try getAllNotes()
        return allNotes.filter { $0.folderId == folderId }
    }
    
    func searchNotes(query: String) throws -> [Note] {
        // DatabaseService 没有专门的搜索方法
        // 从所有笔记中搜索标题或内容包含查询字符串的笔记
        let allNotes = try getAllNotes()
        let lowercasedQuery = query.lowercased()
        return allNotes.filter { note in
            note.title.lowercased().contains(lowercasedQuery) ||
            note.content.lowercased().contains(lowercasedQuery)
        }
    }
    
    func fetchStarredNotes() throws -> [Note] {
        // DatabaseService 没有专门的 getStarredNotes 方法
        // 从所有笔记中筛选收藏的笔记
        let allNotes = try getAllNotes()
        return allNotes.filter { $0.isStarred }
    }
    
    // MARK: - 写入操作
    
    func save(_ note: Note) throws {
        try saveNote(note)
    }
    
    func save(_ notes: [Note]) throws {
        for note in notes {
            try saveNote(note)
        }
    }
    
    func deleteNote(id: String) throws {
        try deleteNote(id: id)
    }
    
    func deleteNotes(ids: [String]) throws {
        for id in ids {
            try deleteNote(id: id)
        }
    }
    
    // MARK: - 批量操作
    
    func performBatchUpdate(_ block: () throws -> Void) throws {
        // DatabaseService 已经是线程安全的，直接执行
        try block()
    }
    
    // MARK: - 文件夹操作
    
    func fetchAllFolders() throws -> [Folder] {
        return try loadFolders()
    }
    
    func fetchFolder(id: String) throws -> Folder? {
        // DatabaseService 没有单独获取文件夹的方法，需要从所有文件夹中查找
        let folders = try loadFolders()
        return folders.first { $0.id == id }
    }
    
    func save(_ folder: Folder) throws {
        try saveFolder(folder)
    }
    
    func save(_ folders: [Folder]) throws {
        for folder in folders {
            try saveFolder(folder)
        }
    }
    
    func deleteFolder(id: String) throws {
        try deleteFolder(folderId: id)
    }
    
    // MARK: - 统计操作
    
    func getNoteCount() throws -> Int {
        return try getAllNotes().count
    }
    
    func getNoteCount(in folderId: String) throws -> Int {
        let notes = try fetchNotes(in: folderId)
        return notes.count
    }
    
    // MARK: - 同步支持
    
    func getPendingChanges() async throws -> [NoteChange] {
        // DatabaseService 不直接跟踪变更
        // 这个功能由 UnifiedOperationQueue 处理
        return []
    }
    
    func getNote(id: String) async throws -> Note {
        guard let note = try loadNote(noteId: id) else {
            throw StorageError.noteNotFound
        }
        return note
    }
}

// MARK: - Storage Error

// 移除重复的 StorageError 定义，使用协议中的定义
