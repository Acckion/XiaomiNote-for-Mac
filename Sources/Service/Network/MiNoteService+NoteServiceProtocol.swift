//
//  MiNoteService+NoteServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  MiNoteService 适配 NoteServiceProtocol
//

import Foundation

/// MiNoteService 实现 NoteServiceProtocol
///
/// 这个扩展将 MiNoteService 的现有方法适配到 NoteServiceProtocol 接口
/// 作为过渡期的适配层,最终应该直接重构 MiNoteService 来实现协议
extension MiNoteService: NoteServiceProtocol {
    // MARK: - 笔记操作

    /// 获取所有笔记
    func fetchNotes() async throws -> [Note] {
        // 使用 fetchPage 获取所有笔记
        let response = try await fetchPage()
        return parseNotes(from: response)
    }

    /// 获取指定笔记
    func fetchNote(id: String) async throws -> Note {
        let response = try await fetchNoteDetails(noteId: id)
        
        // 从响应中解析笔记
        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let note = Note.fromMinoteData(entry) else {
            throw MiNoteError.invalidResponse
        }
        
        return note
    }

    /// 创建新笔记
    func createNote(_ note: Note) async throws -> Note {
        // 提取标题和内容
        let title = note.title
        let content = note.content
        let folderId = note.folderId
        
        // 调用现有的 createNote 方法
        let response = try await createNote(
            title: title,
            content: content,
            folderId: folderId
        )
        
        // 从响应中解析创建后的笔记
        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let createdNote = Note.fromMinoteData(entry) else {
            throw MiNoteError.invalidResponse
        }
        
        return createdNote
    }

    /// 更新笔记
    func updateNote(_ note: Note) async throws -> Note {
        // 调用现有的 updateNote 方法
        let response = try await updateNote(
            noteId: note.id,
            title: note.title,
            content: note.content,
            folderId: note.folderId,
            existingTag: note.serverTag ?? "",
            originalCreateDate: Int(note.createdAt.timeIntervalSince1970 * 1000)
        )
        
        // 从响应中解析更新后的笔记
        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let updatedNote = Note.fromMinoteData(entry) else {
            throw MiNoteError.invalidResponse
        }
        
        return updatedNote
    }

    /// 删除笔记
    func deleteNote(id: String) async throws {
        // 首先获取笔记的 serverTag
        let note = try await fetchNote(id: id)
        
        // 调用现有的 deleteNote 方法
        _ = try await deleteNote(noteId: id, tag: note.serverTag ?? "", purge: false)
    }

    // MARK: - 同步操作

    /// 同步笔记
    func syncNotes(since: Date?) async throws -> SyncResult {
        // 如果提供了 since 参数,使用增量同步
        // 否则使用完整同步
        let response = try await fetchPage()
        
        // 解析笔记和文件夹
        let notes = parseNotes(from: response)
        let folders = parseFolders(from: response)
        
        // 提取 syncTag 作为最后同步时间的标记
        _ = extractSyncTag(from: response)
        
        // 构造同步结果
        // 注意:这里简化了实现,实际应该根据 since 参数过滤结果
        return SyncResult(
            notes: notes,
            deletedIds: [], // MiNoteService 的 fetchPage 不返回删除的笔记ID
            folders: folders,
            deletedFolderIds: [], // MiNoteService 的 fetchPage 不返回删除的文件夹ID
            lastSyncTime: Date() // 使用当前时间作为同步时间
        )
    }

    /// 上传变更
    func uploadChanges(_ changes: [NoteChange]) async throws {
        // 遍历所有变更并应用
        for change in changes {
            switch change.type {
            case .create:
                guard let note = change.note else { continue }
                _ = try await createNote(note)
                
            case .update:
                guard let note = change.note else { continue }
                _ = try await updateNote(note)
                
            case .delete:
                try await deleteNote(id: change.noteId)
            }
        }
    }

    // MARK: - 文件夹操作

    /// 获取所有文件夹
    func fetchFolders() async throws -> [Folder] {
        let response = try await fetchPage()
        return parseFolders(from: response)
    }

    /// 创建文件夹
    func createFolder(_ folder: Folder) async throws -> Folder {
        let response = try await createFolder(name: folder.name)
        
        // 从响应中解析创建后的文件夹
        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let createdFolder = Folder.fromMinoteData(entry) else {
            throw MiNoteError.invalidResponse
        }
        
        return createdFolder
    }

    /// 更新文件夹
    func updateFolder(_ folder: Folder) async throws -> Folder {
        // 首先获取文件夹的详细信息以获取 tag
        let detailsResponse = try await fetchFolderDetails(folderId: folder.id)
        
        guard let data = detailsResponse["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let tag = entry["tag"] as? String else {
            throw MiNoteError.invalidResponse
        }
        
        // 调用现有的 renameFolder 方法
        let response = try await renameFolder(
            folderId: folder.id,
            newName: folder.name,
            existingTag: tag
        )
        
        // 从响应中解析更新后的文件夹
        guard let responseData = response["data"] as? [String: Any],
              let responseEntry = responseData["entry"] as? [String: Any],
              let updatedFolder = Folder.fromMinoteData(responseEntry) else {
            throw MiNoteError.invalidResponse
        }
        
        return updatedFolder
    }

    /// 删除文件夹
    func deleteFolder(id: String) async throws {
        // 首先获取文件夹的详细信息以获取 tag
        let detailsResponse = try await fetchFolderDetails(folderId: id)
        
        guard let data = detailsResponse["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let tag = entry["tag"] as? String else {
            throw MiNoteError.invalidResponse
        }
        
        // 调用现有的 deleteFolder 方法
        _ = try await deleteFolder(folderId: id, tag: tag, purge: false)
    }
}
