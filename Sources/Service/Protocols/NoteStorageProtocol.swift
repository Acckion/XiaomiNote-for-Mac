//
//  NoteStorageProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  笔记存储服务协议 - 定义本地数据库操作接口
//

import Foundation

/// 笔记存储服务协议
///
/// 定义了本地数据库的笔记操作接口，包括：
/// - 笔记的 CRUD 操作
/// - 查询和搜索
/// - 批量操作
protocol NoteStorageProtocol {
    // MARK: - 读取操作

    /// 获取所有笔记
    /// - Returns: 笔记数组
    func fetchAllNotes() throws -> [Note]

    /// 获取指定笔记
    /// - Parameter id: 笔记ID
    /// - Returns: 笔记对象，如果不存在返回 nil
    func fetchNote(id: String) throws -> Note?

    /// 获取指定文件夹中的笔记
    /// - Parameter folderId: 文件夹ID
    /// - Returns: 笔记数组
    func fetchNotes(in folderId: String) throws -> [Note]

    /// 搜索笔记
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的笔记数组
    func searchNotes(query: String) throws -> [Note]

    /// 获取收藏的笔记
    /// - Returns: 收藏的笔记数组
    func fetchStarredNotes() throws -> [Note]

    // MARK: - 写入操作

    /// 保存笔记
    /// - Parameter note: 笔记对象
    func saveNote(_ note: Note) throws

    /// 批量保存笔记
    /// - Parameter notes: 笔记数组
    func saveNotes(_ notes: [Note]) throws

    /// 删除笔记
    /// - Parameter id: 笔记ID
    func deleteNote(id: String) throws

    /// 批量删除笔记
    /// - Parameter ids: 笔记ID数组
    func deleteNotes(ids: [String]) throws

    // MARK: - 批量操作

    /// 执行批量更新
    /// - Parameter block: 更新操作闭包
    func performBatchUpdate(_ block: () throws -> Void) throws

    // MARK: - 文件夹操作

    /// 获取所有文件夹
    /// - Returns: 文件夹数组
    func fetchAllFolders() throws -> [Folder]

    /// 获取指定文件夹
    /// - Parameter id: 文件夹ID
    /// - Returns: 文件夹对象，如果不存在返回 nil
    func fetchFolder(id: String) throws -> Folder?

    /// 保存文件夹
    /// - Parameter folder: 文件夹对象
    func saveFolder(_ folder: Folder) throws

    /// 批量保存文件夹
    /// - Parameter folders: 文件夹数组
    func saveFolders(_ folders: [Folder]) throws

    /// 删除文件夹
    /// - Parameter id: 文件夹ID
    func deleteFolder(id: String) throws

    // MARK: - 统计操作

    /// 获取笔记总数
    /// - Returns: 笔记总数
    func getNoteCount() throws -> Int

    /// 获取指定文件夹的笔记数量
    /// - Parameter folderId: 文件夹ID
    /// - Returns: 笔记数量
    func getNoteCount(in folderId: String) throws -> Int
}
