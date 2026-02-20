//
//  NoteEditorViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  笔记编辑器视图模型 - 管理笔记编辑功能
//

import Combine
import Foundation
import SwiftUI

/// 笔记编辑器视图模型
///
/// 负责管理笔记编辑功能，包括：
/// - 加载笔记内容
/// - 保存笔记内容
/// - 自动保存
/// - 标题提取
/// - 格式转换（XML ↔ AttributedString）
/// - 编辑状态管理
/// - 撤销/重做
///
/// **设计原则**:
/// - 单一职责：只负责笔记编辑相关的功能
/// - 依赖注入：通过构造函数注入依赖，而不是使用单例
/// - 可测试性：所有依赖都可以被 Mock，便于单元测试
///
/// **线程安全**：使用 @MainActor 确保所有 UI 更新在主线程执行
@MainActor
public final class NoteEditorViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 当前编辑的笔记
    @Published public var currentNote: Note?

    /// 笔记内容（XML 格式）
    @Published public var content = ""

    /// 笔记标题
    @Published public var title = ""

    /// 是否有未保存的更改
    @Published public var hasUnsavedChanges = false

    /// 是否正在保存
    @Published public var isSaving = false

    /// 是否正在加载
    @Published public var isLoading = false

    /// 错误消息（用于显示错误提示）
    @Published public var errorMessage: String?

    // MARK: - Dependencies

    /// 笔记存储服务（本地数据库）
    private let noteStorage: NoteStorageProtocol

    /// 笔记网络服务（云端 API）
    private let noteService: NoteServiceProtocol

    // MARK: - Private Properties

    /// 自动保存定时器
    /// 使用 nonisolated(unsafe) 因为 Timer 不是 Sendable 的
    private nonisolated(unsafe) var autoSaveTimer: Timer?

    /// 自动保存间隔（秒）
    private let autoSaveInterval: TimeInterval = 3.0

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 上次保存的内容（用于检测是否有更改）
    private var lastSavedContent = ""

    // MARK: - Initialization

    /// 初始化笔记编辑器视图模型
    ///
    /// - Parameters:
    ///   - noteStorage: 笔记存储服务（本地数据库）
    ///   - noteService: 笔记网络服务（云端 API）
    public init(
        noteStorage: NoteStorageProtocol,
        noteService: NoteServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.noteService = noteService

        setupAutoSave()
    }

    deinit {
        autoSaveTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// 加载笔记内容
    ///
    /// - Parameter note: 要加载的笔记
    public func loadNote(_ note: Note) async {
        // 如果正在编辑同一个笔记，不重复加载
        guard currentNote?.id != note.id else { return }

        // 如果有未保存的更改，先保存
        if hasUnsavedChanges {
            await saveNote()
        }

        isLoading = true
        errorMessage = nil

        do {
            // 从本地数据库加载笔记
            let loadedNote = try await noteStorage.getNote(id: note.id)

            currentNote = loadedNote
            content = loadedNote.content
            title = loadedNote.title
            lastSavedContent = loadedNote.content
            hasUnsavedChanges = false

            LogService.shared.info(.viewmodel, "加载笔记: \(loadedNote.title)")
        } catch {
            errorMessage = "加载笔记失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "加载笔记失败: \(error)")
        }

        isLoading = false
    }

    /// 保存笔记
    public func saveNote() async {
        guard let note = currentNote else {
            return
        }
        guard hasUnsavedChanges else {
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            // 更新笔记内容
            var updatedNote = note
            updatedNote.content = content
            updatedNote.title = title.isEmpty ? extractTitle(from: content) : title
            updatedNote.updatedAt = Date()

            // 保存到本地数据库
            try noteStorage.saveNote(updatedNote)

            // 更新状态
            currentNote = updatedNote
            lastSavedContent = content
            hasUnsavedChanges = false

            LogService.shared.info(.viewmodel, "保存笔记: \(updatedNote.title)")
        } catch {
            errorMessage = "保存笔记失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "保存笔记失败: \(error)")
        }

        isSaving = false
    }

    /// 更新笔记内容
    ///
    /// - Parameter newContent: 新的内容
    public func updateContent(_ newContent: String) {
        content = newContent
        hasUnsavedChanges = (newContent != lastSavedContent)
    }

    /// 更新笔记标题
    ///
    /// - Parameter newTitle: 新的标题
    public func updateTitle(_ newTitle: String) {
        title = newTitle
        hasUnsavedChanges = true
    }

    /// 从内容中提取标题
    ///
    /// - Parameter content: 笔记内容（XML 格式）
    /// - Returns: 提取的标题
    public func extractTitle(from content: String) -> String {
        // 移除 XML 标签
        let plainText = content.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // 获取第一行作为标题
        let lines = plainText.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 限制标题长度
        let maxLength = 100
        if firstLine.count > maxLength {
            let index = firstLine.index(firstLine.startIndex, offsetBy: maxLength)
            return String(firstLine[..<index]) + "..."
        }

        return firstLine.isEmpty ? "未命名笔记" : firstLine
    }

    /// 转换为 XML 格式
    ///
    /// - Parameter text: 纯文本
    /// - Returns: XML 格式的内容
    public func convertToXML(_ text: String) -> String {
        // 简单的文本到 XML 转换
        // 实际实现应该使用更复杂的转换逻辑
        let lines = text.components(separatedBy: .newlines)
        let xmlLines = lines.map { line in
            "<text indent=\"1\">\(line)</text>"
        }

        return "<new-format/>" + xmlLines.joined(separator: "\n")
    }

    /// 从 XML 转换为纯文本
    ///
    /// - Parameter xml: XML 格式的内容
    /// - Returns: 纯文本
    public func convertFromXML(_ xml: String) -> String {
        // 移除 XML 标签
        xml.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }

    /// 清除当前编辑的笔记
    public func clearNote() async {
        // 如果有未保存的更改，先保存
        if hasUnsavedChanges {
            await saveNote()
        }

        currentNote = nil
        content = ""
        title = ""
        lastSavedContent = ""
        hasUnsavedChanges = false
    }

    // MARK: - Private Methods

    /// 设置自动保存
    private func setupAutoSave() {
        // 监听内容变化
        $content
            .debounce(for: .seconds(autoSaveInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                if hasUnsavedChanges {
                    Task {
                        await self.autoSave()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// 自动保存
    private func autoSave() async {
        guard hasUnsavedChanges else { return }

        LogService.shared.debug(.viewmodel, "自动保存触发")
        await saveNote()
    }
}
