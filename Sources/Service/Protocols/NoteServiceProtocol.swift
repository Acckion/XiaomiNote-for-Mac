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
protocol NoteServiceProtocol {
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
struct SyncResult: Codable {
    /// 同步的笔记
    let notes: [Note]

    /// 删除的笔记ID
    let deletedIds: [String]

    /// 同步的文件夹
    let folders: [Folder]

    /// 删除的文件夹ID
    let deletedFolderIds: [String]

    /// 最后同步时间
    let lastSyncTime: Date
}

/// 笔记变更
struct NoteChange: Codable {
    /// 变更ID
    let id: String

    /// 变更类型
    let type: ChangeType

    /// 笔记ID
    let noteId: String

    /// 笔记数据（创建和更新时需要）
    let note: Note?

    /// 时间戳
    let timestamp: Date

    enum ChangeType: String, Codable {
        case create
        case update
        case delete
    }
}
