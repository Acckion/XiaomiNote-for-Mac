//
//  DefaultNoteService.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  默认笔记服务实现 - 实现 NoteServiceProtocol
//

import Foundation

/// 默认笔记服务
///
/// 实现 NoteServiceProtocol，提供笔记的网络操作功能
final class DefaultNoteService: NoteServiceProtocol {
    // MARK: - Dependencies

    private let client: NetworkClient

    // MARK: - Initialization

    init(client: NetworkClient) {
        self.client = client
    }

    /// 便利初始化方法
    convenience init(baseURL: String) {
        let client = NetworkClient(baseURL: baseURL)
        self.init(client: client)
    }

    // MARK: - NoteServiceProtocol - 笔记操作

    func fetchNotes() async throws -> [Note] {
        return try await client.request("/notes", method: .get)
    }

    func fetchNote(id: String) async throws -> Note {
        return try await client.request("/notes/\\(id)", method: .get)
    }

    func createNote(_ note: Note) async throws -> Note {
        let parameters = noteToParameters(note)
        return try await client.request("/notes", method: .post, parameters: parameters)
    }

    func updateNote(_ note: Note) async throws -> Note {
        let parameters = noteToParameters(note)
        return try await client.request("/notes/\\(note.id)", method: .put, parameters: parameters)
    }

    func deleteNote(id: String) async throws {
        let _: EmptyResponse = try await client.request("/notes/\\(id)", method: .delete)
    }

    // MARK: - NoteServiceProtocol - 同步操作

    func syncNotes(since: Date?) async throws -> SyncResult {
        var parameters: [String: Any] = [:]
        if let since = since {
            parameters["since"] = Int(since.timeIntervalSince1970 * 1000)
        }

        return try await client.request("/sync", method: .post, parameters: parameters)
    }

    func uploadChanges(_ changes: [NoteChange]) async throws {
        let parameters: [String: Any] = [
            "changes": changes.map { changeToParameters($0) }
        ]

        let _: EmptyResponse = try await client.request("/sync/upload", method: .post, parameters: parameters)
    }

    // MARK: - NoteServiceProtocol - 文件夹操作

    func fetchFolders() async throws -> [Folder] {
        return try await client.request("/folders", method: .get)
    }

    func createFolder(_ folder: Folder) async throws -> Folder {
        let parameters = folderToParameters(folder)
        return try await client.request("/folders", method: .post, parameters: parameters)
    }

    func updateFolder(_ folder: Folder) async throws -> Folder {
        let parameters = folderToParameters(folder)
        return try await client.request("/folders/\\(folder.id)", method: .put, parameters: parameters)
    }

    func deleteFolder(id: String) async throws {
        let _: EmptyResponse = try await client.request("/folders/\\(id)", method: .delete)
    }

    // MARK: - Private Methods

    private func noteToParameters(_ note: Note) -> [String: Any] {
        return [
            "id": note.id,
            "title": note.title,
            "content": note.content,
            "folderId": note.folderId,
            "isStarred": note.isStarred,
            "createdAt": Int(note.createdAt.timeIntervalSince1970 * 1000),
            "updatedAt": Int(note.updatedAt.timeIntervalSince1970 * 1000)
        ]
    }

    private func folderToParameters(_ folder: Folder) -> [String: Any] {
        return [
            "id": folder.id,
            "name": folder.name,
            "count": folder.count
        ]
    }

    private func changeToParameters(_ change: NoteChange) -> [String: Any] {
        var params: [String: Any] = [
            "id": change.id,
            "type": change.type.rawValue,
            "noteId": change.noteId,
            "timestamp": Int(change.timestamp.timeIntervalSince1970 * 1000)
        ]

        if let note = change.note {
            params["note"] = noteToParameters(note)
        }

        return params
    }
}

// MARK: - Supporting Types

private struct EmptyResponse: Decodable {}
