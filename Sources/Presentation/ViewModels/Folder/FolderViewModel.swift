//
//  FolderViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  文件夹视图模型 - 管理文件夹功能
//

import Foundation
import Combine

/// 文件夹视图模型
///
/// 负责管理文件夹功能，包括：
/// - 加载文件夹列表
/// - 创建/删除/重命名文件夹
/// - 文件夹选择状态管理
@MainActor
public final class FolderViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// 文件夹列表
    @Published public var folders: [Folder] = []
    
    /// 选中的文件夹
    @Published public var selectedFolder: Folder?
    
    /// 是否正在加载
    @Published public var isLoading: Bool = false
    
    /// 错误消息
    @Published public var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let noteStorage: NoteStorageProtocol
    private let noteService: NoteServiceProtocol
    
    // MARK: - Initialization
    
    /// 初始化文件夹视图模型
    /// - Parameters:
    ///   - noteStorage: 笔记存储服务
    ///   - noteService: 笔记服务
    public init(
        noteStorage: NoteStorageProtocol,
        noteService: NoteServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.noteService = noteService
    }
    
    // MARK: - Public Methods
    
    /// 加载文件夹列表
    public func loadFolders() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 从本地存储加载文件夹
            let loadedFolders = try noteStorage.fetchAllFolders()
            
            // 按创建时间排序
            folders = loadedFolders.sorted { $0.createdAt > $1.createdAt }
            
        } catch {
            errorMessage = "加载文件夹失败: \(error.localizedDescription)"
            print("[FolderViewModel] 加载文件夹失败: \(error)")
        }
        
        isLoading = false
    }
    
    /// 创建文件夹
    /// - Parameter name: 文件夹名称
    public func createFolder(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 验证文件夹名称
        guard !trimmedName.isEmpty else {
            errorMessage = "文件夹名称不能为空"
            return
        }
        
        // 检查是否已存在同名文件夹
        if folders.contains(where: { $0.name == trimmedName }) {
            errorMessage = "文件夹名称已存在"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 创建新文件夹
            let newFolder = Folder(
                id: UUID().uuidString,
                name: trimmedName,
                count: 0,
                isSystem: false,
                createdAt: Date()
            )
            
            // 保存到本地存储
            try noteStorage.saveFolder(newFolder)
            
            // 尝试同步到云端
            do {
                _ = try await noteService.createFolder(newFolder)
            } catch {
                print("[FolderViewModel] 同步文件夹到云端失败: \(error)")
                // 不阻塞本地操作
            }
            
            // 重新加载文件夹列表
            await loadFolders()
            
        } catch {
            errorMessage = "创建文件夹失败: \(error.localizedDescription)"
            print("[FolderViewModel] 创建文件夹失败: \(error)")
        }
        
        isLoading = false
    }
    
    /// 删除文件夹
    /// - Parameter folder: 要删除的文件夹
    public func deleteFolder(_ folder: Folder) async {
        // 不能删除系统文件夹
        guard !folder.isSystem else {
            errorMessage = "不能删除系统文件夹"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 从本地存储删除
            try noteStorage.deleteFolder(id: folder.id)
            
            // 尝试从云端删除
            do {
                try await noteService.deleteFolder(id: folder.id)
            } catch {
                print("[FolderViewModel] 从云端删除文件夹失败: \(error)")
                // 不阻塞本地操作
            }
            
            // 如果删除的是当前选中的文件夹，清除选中状态
            if selectedFolder?.id == folder.id {
                selectedFolder = nil
            }
            
            // 重新加载文件夹列表
            await loadFolders()
            
        } catch {
            errorMessage = "删除文件夹失败: \(error.localizedDescription)"
            print("[FolderViewModel] 删除文件夹失败: \(error)")
        }
        
        isLoading = false
    }
    
    /// 重命名文件夹
    /// - Parameters:
    ///   - folder: 要重命名的文件夹
    ///   - newName: 新名称
    public func renameFolder(_ folder: Folder, newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 验证新名称
        guard !trimmedName.isEmpty else {
            errorMessage = "文件夹名称不能为空"
            return
        }
        
        // 不能重命名系统文件夹
        guard !folder.isSystem else {
            errorMessage = "不能重命名系统文件夹"
            return
        }
        
        // 检查是否已存在同名文件夹
        if folders.contains(where: { $0.name == trimmedName && $0.id != folder.id }) {
            errorMessage = "文件夹名称已存在"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 更新文件夹名称
            var updatedFolder = folder
            updatedFolder.name = trimmedName
            
            // 保存到本地存储
            try noteStorage.saveFolder(updatedFolder)
            
            // 尝试同步到云端
            do {
                _ = try await noteService.updateFolder(updatedFolder)
            } catch {
                print("[FolderViewModel] 同步文件夹到云端失败: \(error)")
                // 不阻塞本地操作
            }
            
            // 重新加载文件夹列表
            await loadFolders()
            
        } catch {
            errorMessage = "重命名文件夹失败: \(error.localizedDescription)"
            print("[FolderViewModel] 重命名文件夹失败: \(error)")
        }
        
        isLoading = false
    }
    
    /// 选择文件夹
    /// - Parameter folder: 要选择的文件夹
    public func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
    }
    
    /// 切换文件夹置顶状态
    /// - Parameter folder: 要切换置顶状态的文件夹
    public func toggleFolderPin(_ folder: Folder) async {
        // 不能置顶系统文件夹
        guard !folder.isSystem else {
            errorMessage = "不能置顶系统文件夹"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 更新文件夹置顶状态
            var updatedFolder = folder
            updatedFolder.isPinned.toggle()
            
            // 保存到本地存储
            try noteStorage.saveFolder(updatedFolder)
            
            print("[FolderViewModel] 文件夹置顶状态已更新: \(folder.name) -> \(updatedFolder.isPinned)")
            
            // 重新加载文件夹列表（会自动按置顶状态排序）
            await loadFolders()
            
            // 如果是当前选中的文件夹，更新选中状态
            if selectedFolder?.id == folder.id {
                selectedFolder = updatedFolder
            }
            
        } catch {
            errorMessage = "更新文件夹置顶状态失败: \(error.localizedDescription)"
            print("[FolderViewModel] 更新文件夹置顶状态失败: \(error)")
        }
        
        isLoading = false
    }
}
