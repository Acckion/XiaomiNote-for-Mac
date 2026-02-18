//
//  NoteServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  笔记网络服务协议 - 定义笔记相关的网络操作接口
//

import Foundation

/// 笔记网络服务协议
///
/// 定义了与服务器交互的笔记操作接口，包括：
/// - 笔记的 CRUD 操作
/// - 笔记同步操作
/// - 批量操作
@preconcurrency
public protocol NoteServiceProtocol: Sendable {
    // MARK: - 笔记操作

    /// 获取所有笔记
    /// - Returns: 笔记数组
    func fetchNotes() async throws -> [Note]

    /// 获取指定笔记
    /// - Parameter id: 笔记ID
    /// - Returns: 笔记对象
    func fetchNote(id: String) async throws -> Note

    /// 创建新笔记
    /// - Parameter note: 笔记对象
    /// - Returns: 创建后的笔记对象（包含服务器生成的ID等信息）
    func createNote(_ note: Note) async throws -> Note

    /// 更新笔记
    /// - Parameter note: 笔记对象
    /// - Returns: 更新后的笔记对象
    func updateNote(_ note: Note) async throws -> Note

    /// 删除笔记
    /// - Parameter id: 笔记ID
    func deleteNote(id: String) async throws

    // MARK: - 同步操作

    /// 同步笔记
    /// - Parameter since: 上次同步时间，nil 表示全量同步
    /// - Returns: 同步结果
    func syncNotes(since: Date?) async throws -> SyncResult

    /// 上传变更
    /// - Parameter changes: 变更数组
    func uploadChanges(_ changes: [NoteChange]) async throws

    // MARK: - 文件夹操作

    /// 获取所有文件夹
    /// - Returns: 文件夹数组
    func fetchFolders() async throws -> [Folder]

    /// 创建文件夹
    /// - Parameter folder: 文件夹对象
    /// - Returns: 创建后的文件夹对象
    func createFolder(_ folder: Folder) async throws -> Folder

    /// 更新文件夹
    /// - Parameter folder: 文件夹对象
    /// - Returns: 更新后的文件夹对象
    func updateFolder(_ folder: Folder) async throws -> Folder

    /// 删除文件夹
    /// - Parameter id: 文件夹ID
    func deleteFolder(id: String) async throws
}

// MARK: - Supporting Types

/// 同步结果
public struct SyncResult: Codable {
    /// 同步的笔记
    public let notes: [Note]

    /// 删除的笔记ID
    public let deletedIds: [String]

    /// 同步的文件夹
    public let folders: [Folder]

    /// 删除的文件夹ID
    public let deletedFolderIds: [String]

    /// 最后同步时间
    public let lastSyncTime: Date

    public init(notes: [Note], deletedIds: [String], folders: [Folder], deletedFolderIds: [String], lastSyncTime: Date) {
        self.notes = notes
        self.deletedIds = deletedIds
        self.folders = folders
        self.deletedFolderIds = deletedFolderIds
        self.lastSyncTime = lastSyncTime
    }
}

/// 笔记变更
public struct NoteChange: Codable, Sendable {
    /// 变更ID
    public let id: String

    /// 变更类型
    public let type: ChangeType

    /// 笔记ID
    public let noteId: String

    /// 笔记数据（创建和更新时需要）
    public let note: Note?

    /// 时间戳
    public let timestamp: Date

    public enum ChangeType: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    public init(id: String, type: ChangeType, noteId: String, note: Note?, timestamp: Date) {
        self.id = id
        self.type = type
        self.noteId = noteId
        self.note = note
        self.timestamp = timestamp
    }
}
