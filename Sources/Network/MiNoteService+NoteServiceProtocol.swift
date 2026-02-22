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
/// 内部实现通过 NoteAPI、FolderAPI、ResponseParser 等新 API 类完成
extension MiNoteService: NoteServiceProtocol {
    // MARK: - 笔记操作

    /// 获取所有笔记
    public func fetchNotes() async throws -> [Note] {
        let response = try await NoteAPI.shared.fetchPage()
        return ResponseParser.parseNotes(from: response)
    }

    /// 获取指定笔记
    public func fetchNote(id: String) async throws -> Note {
        let response = try await NoteAPI.shared.fetchNoteDetails(noteId: id)

        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let note = NoteMapper.fromMinoteListData(entry)
        else {
            throw MiNoteError.invalidResponse
        }

        return note
    }

    /// 创建新笔记
    public func createNote(_ note: Note) async throws -> Note {
        let title = note.title
        let content = note.content
        let folderId = note.folderId

        let response = try await NoteAPI.shared.createNote(
            title: title,
            content: content,
            folderId: folderId
        )

        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let createdNote = NoteMapper.fromMinoteListData(entry)
        else {
            throw MiNoteError.invalidResponse
        }

        return createdNote
    }

    /// 更新笔记
    public func updateNote(_ note: Note) async throws -> Note {
        let response = try await NoteAPI.shared.updateNote(
            noteId: note.id,
            title: note.title,
            content: note.content,
            folderId: note.folderId,
            existingTag: note.serverTag ?? "",
            originalCreateDate: Int(note.createdAt.timeIntervalSince1970 * 1000)
        )

        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let updatedNote = NoteMapper.fromMinoteListData(entry)
        else {
            throw MiNoteError.invalidResponse
        }

        return updatedNote
    }

    /// 删除笔记
    public func deleteNote(id: String) async throws {
        let note = try await fetchNote(id: id)
        _ = try await NoteAPI.shared.deleteNote(noteId: id, tag: note.serverTag ?? "", purge: false)
    }

    // MARK: - 同步操作

    /// 同步笔记
    public func syncNotes(since _: Date?) async throws -> SyncResult {
        let response = try await NoteAPI.shared.fetchPage()

        let notes = ResponseParser.parseNotes(from: response)
        let folders = ResponseParser.parseFolders(from: response)
        _ = ResponseParser.extractSyncTag(from: response)

        return SyncResult(
            notes: notes,
            deletedIds: [],
            folders: folders,
            deletedFolderIds: [],
            lastSyncTime: Date()
        )
    }

    /// 上传变更
    public func uploadChanges(_ changes: [NoteChange]) async throws {
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
    public func fetchFolders() async throws -> [Folder] {
        let response = try await NoteAPI.shared.fetchPage()
        return ResponseParser.parseFolders(from: response)
    }

    /// 创建文件夹
    public func createFolder(_ folder: Folder) async throws -> Folder {
        let response = try await FolderAPI.shared.createFolder(name: folder.name)

        guard let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let createdFolder = Folder.fromMinoteData(entry)
        else {
            throw MiNoteError.invalidResponse
        }

        return createdFolder
    }

    /// 更新文件夹
    public func updateFolder(_ folder: Folder) async throws -> Folder {
        let detailsResponse = try await FolderAPI.shared.fetchFolderDetails(folderId: folder.id)

        guard let data = detailsResponse["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let tag = entry["tag"] as? String
        else {
            throw MiNoteError.invalidResponse
        }

        let response = try await FolderAPI.shared.renameFolder(
            folderId: folder.id,
            newName: folder.name,
            existingTag: tag
        )

        guard let responseData = response["data"] as? [String: Any],
              let responseEntry = responseData["entry"] as? [String: Any],
              let updatedFolder = Folder.fromMinoteData(responseEntry)
        else {
            throw MiNoteError.invalidResponse
        }

        return updatedFolder
    }

    /// 删除文件夹
    public func deleteFolder(id: String) async throws {
        let detailsResponse = try await FolderAPI.shared.fetchFolderDetails(folderId: id)

        guard let data = detailsResponse["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any],
              let tag = entry["tag"] as? String
        else {
            throw MiNoteError.invalidResponse
        }

        _ = try await FolderAPI.shared.deleteFolder(folderId: id, tag: tag, purge: false)
    }
}
