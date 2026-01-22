//
//  FolderViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  文件夹 ViewModel - 负责文件夹管理功能
//

@preconcurrency import Foundation
@preconcurrency import Combine

/// 文件夹 ViewModel
///
/// 负责管理文件夹相关的逻辑，包括：
/// - 文件夹列表管理
/// - 创建、编辑、删除文件夹
/// - 文件夹选择
/// - 笔记数量统计
@MainActor
final class FolderViewModel: LoadableViewModel {
    // MARK: - Dependencies

    nonisolated(unsafe) private let noteStorage: NoteStorageProtocol
    nonisolated(unsafe) private let noteService: NoteServiceProtocol

    // MARK: - Published Properties

    /// 文件夹列表
    @Published var folders: [Folder] = []

    /// 当前选中的文件夹ID
    @Published var selectedFolderId: String?

    /// 新文件夹名称（用于创建）
    @Published var newFolderName: String = ""

    // MARK: - Computed Properties

    /// 当前选中的文件夹
    var selectedFolder: Folder? {
        guard let id = selectedFolderId else { return nil }
        return folders.first { $0.id == id }
    }

    // MARK: - Initialization

    init(
        noteStorage: NoteStorageProtocol,
        noteService: NoteServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.noteService = noteService
        super.init()
    }

    // MARK: - Public Methods

    /// 加载文件夹列表
    func loadFolders() async {
        await withLoadingSafe {
            let loadedFolders = try noteStorage.fetchAllFolders()
            self.folders = loadedFolders
        }
    }

    /// 刷新文件夹列表
    func refreshFolders() async {
        await loadFolders()
    }

    /// 选择文件夹
    /// - Parameter folderId: 文件夹ID
    func selectFolder(_ folderId: String?) {
        selectedFolderId = folderId
    }

    /// 创建新文件夹
    func createFolder() async {
        guard !newFolderName.isEmpty else {
            error = NSError(domain: "Folder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Folder name is required"])
            return
        }

        let folder = Folder(
            id: UUID().uuidString,
            name: newFolderName,
            count: 0,
            isSystem: false
        )

        await withLoadingSafe {
            // 保存到本地
            try noteStorage.saveFolder(folder)

            // 同步到服务器
            _ = try await noteService.createFolder(folder)

            self.folders.append(folder)
            self.newFolderName = ""
        }
    }

    /// 重命名文件夹
    /// - Parameters:
    ///   - folderId: 文件夹ID
    ///   - newName: 新名称
    func renameFolder(_ folderId: String, to newName: String) async {
        guard !newName.isEmpty else { return }
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }

        var folder = folders[index]
        folder.name = newName

        await withLoadingSafe {
            try noteStorage.saveFolder(folder)
            _ = try await noteService.updateFolder(folder)
            self.folders[index] = folder
        }
    }

    /// 删除文件夹
    /// - Parameter folderId: 文件夹ID
    func deleteFolder(_ folderId: String) async {
        guard let folder = folders.first(where: { $0.id == folderId }) else { return }
        guard !folder.isSystem else {
            error = NSError(domain: "Folder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot delete system folder"])
            return
        }

        await withLoadingSafe {
            try noteStorage.deleteFolder(id: folderId)
            try await noteService.deleteFolder(id: folderId)

            self.folders.removeAll { $0.id == folderId }

            // 如果删除的是当前选中的文件夹，清除选择
            if selectedFolderId == folderId {
                selectedFolderId = nil
            }
        }
    }

    /// 更新文件夹笔记数量
    /// - Parameter folderId: 文件夹ID
    func updateFolderCount(_ folderId: String) async {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }

        do {
            let count = try noteStorage.getNoteCount(in: folderId)
            var folder = folders[index]
            folder.count = count
            folders[index] = folder
        } catch {
            self.error = error
        }
    }

    /// 更新所有文件夹的笔记数量
    func updateAllFolderCounts() async {
        for folder in folders {
            await updateFolderCount(folder.id)
        }
    }
}
